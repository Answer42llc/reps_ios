import Foundation
import CloudKit
import CoreData
import Observation
import OSLog

@MainActor
protocol CloudSyncCoordinating: AnyObject {
    func start()
    func enqueueUpload(for affirmationID: NSManagedObjectID)
    func requestFullSync()
    var isBusy: Bool { get }
    var lastSyncDate: Date? { get }
}

@MainActor
@Observable
final class CloudSyncService: CloudSyncCoordinating {
    private struct Constants {
        static let zoneName = "AffirmationsZone"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let context: NSManagedObjectContext
    private let shouldConfigureZone: Bool
    private let logger: Logger
    @ObservationIgnored
    private let operationQueue = OperationQueue()
    private(set) var isConfigured = false
    private(set) var lastSyncError: Error?
    private var isSyncEnabled = true
    @ObservationIgnored
    private var pendingUploads: Set<NSManagedObjectID> = []
    private var isPerformingSync = false
    private var lastFetchDate: Date?

    var isBusy: Bool { isPerformingSync }
    var lastSyncDate: Date? { lastFetchDate }

    init(container: CKContainer = CKContainer.default(),
         databaseScope: CKDatabase.Scope = .private,
         context: NSManagedObjectContext,
         configureZone: Bool = true) {
        self.container = container
        self.database = container.database(with: databaseScope)
        self.context = context
        self.zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        self.shouldConfigureZone = configureZone
        let subsystem = Bundle.main.bundleIdentifier ?? "SelfLie"
        self.logger = Logger(subsystem: subsystem, category: "CloudSync")
        operationQueue.name = "com.selflie.cloudsync"
        operationQueue.maxConcurrentOperationCount = 1
        logger.debug("CloudSyncService initialised. configureZone=\(configureZone, privacy: .public)")
    }

    func start() {
        guard !isConfigured else { return }
        logger.debug("Starting CloudSyncService")
        if shouldConfigureZone {
            configureZoneIfNeeded()
        }
        isConfigured = true
    }

    func enqueueUpload(for affirmationID: NSManagedObjectID) {
        guard isConfigured else {
            logger.debug("enqueueUpload skipped – service not configured yet")
            return
        }
        guard isSyncEnabled else {
            logger.debug("enqueueUpload skipped – sync disabled")
            return
        }
        pendingUploads.insert(affirmationID)
        logger.debug("Enqueued upload for \(affirmationID, privacy: .public); pending count = \(self.pendingUploads.count, privacy: .public)")
        scheduleUploadIfNeeded()
    }

    func requestFullSync() {
        guard isConfigured, isSyncEnabled else { return }
        performFetch()
    }

    func setSyncEnabled(_ enabled: Bool) {
        let wasEnabled = isSyncEnabled
        isSyncEnabled = enabled
        logger.notice("Sync \(enabled ? "enabled" : "disabled", privacy: .public)")

        if enabled && !wasEnabled {
            backfillPendingUploads()
        }
    }

    private func configureZoneIfNeeded() {
        logger.debug("Configuring custom zone if needed")
        let createZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [CKRecordZone(zoneID: zoneID)], recordZoneIDsToDelete: [])
        createZoneOperation.modifyRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.lastSyncError = nil
                self?.logger.notice("CloudKit zone available")
                if self?.isSyncEnabled == true {
                    self?.backfillPendingUploads()
                }
                self?.performFetch()
            case .failure(let error):
                self?.lastSyncError = error
                self?.logger.error("Failed to configure CloudKit zone: \(error as NSError, privacy: .public)")
            }
        }
        database.add(createZoneOperation)
    }

    private func scheduleUploadIfNeeded() {
        guard !pendingUploads.isEmpty else { return }
        let pendingCount = pendingUploads.count
        logger.debug("Scheduling upload for \(pendingCount, privacy: .public) items")
        operationQueue.addOperation { [weak self] in
            Task { await self?.performUploadBatch() }
        }
    }

    @MainActor
    private func performUploadBatch() async {
        guard !pendingUploads.isEmpty else {
            logger.debug("performUploadBatch called with no pending uploads")
            return
        }
        let objectIDs = pendingUploads
        pendingUploads.removeAll()

        isPerformingSync = true
        defer { isPerformingSync = false }

        do {
            logger.debug("Preparing upload batch of \(objectIDs.count, privacy: .public) affirmations")
            let records = try await buildRecords(for: Array(objectIDs))
            guard !records.isEmpty else {
                logger.debug("No eligible records found in upload batch; skipping CloudKit call")
                return
            }

            try await modify(records: records)
            lastSyncError = nil
            lastFetchDate = Date()
            logger.notice("Uploaded \(records.count, privacy: .public) affirmation records to CloudKit")
        } catch {
            lastSyncError = error
            logger.error("Upload batch failed: \(error as NSError, privacy: .public)")
            // Requeue pending uploads for retry
            pendingUploads.formUnion(objectIDs)
            logger.debug("Requeued \(objectIDs.count, privacy: .public) items after failure")
        }
    }

    @MainActor
    private func buildRecords(for objectIDs: [NSManagedObjectID]) async throws -> [CKRecord] {
        let context = self.context
        let logger = self.logger
        return await context.perform {
            var records: [CKRecord] = []
            var skippedInactive = 0
            var missingObjects: [NSManagedObjectID] = []
            for objectID in objectIDs {
                guard let affirmation = try? context.existingObject(with: objectID) as? Affirmation else {
                    missingObjects.append(objectID)
                    continue
                }
                guard affirmation.isActive else {
                    skippedInactive += 1
                    continue
                }
                guard let record = try? self.makeRecord(from: affirmation) else { continue }
                records.append(record)
            }
            if !missingObjects.isEmpty {
                logger.error("Failed to resolve \(missingObjects.count, privacy: .public) managed objects for upload: \(missingObjects, privacy: .public)")
            }
            if skippedInactive > 0 {
                logger.debug("Skipped \(skippedInactive, privacy: .public) inactive affirmations during upload build")
            }
            logger.debug("Built \(records.count, privacy: .public) records for upload")
            return records
        }
    }

    private func backfillPendingUploads() {
        let context = self.context
        context.perform { [weak self] in
            guard let self else { return }
            let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
            request.predicate = NSPredicate(format: "isArchived == NO OR isArchived == nil")

            do {
                let affirmations = try context.fetch(request)
                let ids = affirmations.map { $0.objectID }
                guard !ids.isEmpty else {
                    self.logger.debug("Backfill found no active affirmations to enqueue")
                    return
                }

                self.logger.debug("Backfill enqueuing \(ids.count, privacy: .public) affirmations for upload")
                Task { @MainActor in
                    for id in ids {
                        self.enqueueUpload(for: id)
                    }
                }
            } catch {
                self.logger.error("Backfill fetch failed: \(error as NSError, privacy: .public)")
            }
        }
    }

    nonisolated private func makeRecord(from affirmation: Affirmation) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: affirmation.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "Affirmation", recordID: recordID)
        record["text"] = affirmation.text
        record["repeatCount"] = affirmation.repeatCount as NSNumber
        record["targetCount"] = affirmation.targetCount as NSNumber
        record["dateCreated"] = affirmation.dateCreated as NSDate
        let updatedAt = affirmation.updatedAt ?? affirmation.dateCreated
        record["updatedAt"] = updatedAt as NSDate
        if let audioFileName = affirmation.audioFileName, !audioFileName.isEmpty {
            record["audioFileName"] = audioFileName as NSString
        }
        if let lastPracticed = affirmation.lastPracticedAt {
            record["lastPracticedAt"] = lastPracticed as NSDate
        }
        record["isArchived"] = NSNumber(value: affirmation.isArchived)
        if let wordData = affirmation.wordTimingsData {
            record["wordTimings"] = wordData as NSData
        }

        if let assetURL = affirmation.audioURL, FileManager.default.fileExists(atPath: assetURL.path) {
            record["audio"] = CKAsset(fileURL: assetURL)
        }

        return record
    }

    private func modify(records: [CKRecord]) async throws {
        let logger = self.logger
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: [])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    logger.debug("CKModifyRecordsOperation succeeded for \(records.count, privacy: .public) records")
                    continuation.resume(returning: ())
                case .failure(let error):
                    logger.error("CKModifyRecordsOperation failed: \(error as NSError, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    @MainActor
    private func performFetch() {
        guard !isPerformingSync else { return }
        isPerformingSync = true
        logger.debug("Starting CloudKit fetch")

        Task {
            defer { isPerformingSync = false }
            do {
                let records = try await fetchAllRecords()
                logger.debug("Fetch returned \(records.count, privacy: .public) records")
                try await merge(records: records)
                lastSyncError = nil
                lastFetchDate = Date()
            } catch let error as CKError {
                switch error.code {
                case .unknownItem:
                    // Record type not found yet; treat as empty sync.
                    lastSyncError = nil
                    lastFetchDate = Date()
                    logger.notice("Fetch completed with unknownItem; waiting for first upload to create schema")
                case .zoneNotFound:
                    lastSyncError = nil
                    logger.notice("Zone not found; scheduling reconfiguration")
                    configureZoneIfNeeded()
                default:
                    lastSyncError = error
                    logger.error("Fetch failed with CKError: \(error as NSError, privacy: .public)")
                }
            } catch {
                lastSyncError = error
                logger.error("Fetch failed: \(error as NSError, privacy: .public)")
            }
        }
    }

    private func fetchAllRecords(cursor: CKQueryOperation.Cursor? = nil) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                let query = CKQuery(recordType: "Affirmation", predicate: NSPredicate(value: true))
                operation = CKQueryOperation(query: query)
                operation.zoneID = zoneID
            }

            var fetchedRecords: [CKRecord] = []
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    fetchedRecords.append(record)
                }
            }

            operation.queryResultBlock = { [weak self] result in
                switch result {
                case .success(let nextCursor):
                    if let nextCursor {
                        Task { [weak self] in
                            guard let self else {
                                continuation.resume(returning: fetchedRecords)
                                return
                            }
                            do {
                                let more = try await self.fetchAllRecords(cursor: nextCursor)
                                continuation.resume(returning: fetchedRecords + more)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        continuation.resume(returning: fetchedRecords)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    @MainActor
    private func merge(records: [CKRecord]) async throws {
        guard !records.isEmpty else { return }

        let context = self.context
        let logger = self.logger
        try await context.perform {
            for record in records {
                self.upsert(record: record)
            }

            if context.hasChanges {
                try context.save()
                logger.debug("Merged \(records.count, privacy: .public) records from CloudKit")
            }
        }
    }

    nonisolated private func upsert(record: CKRecord) {
        guard let uuid = UUID(uuidString: record.recordID.recordName) else { return }
        let context = self.context
        let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1

        let recordDate = (record["updatedAt"] as? Date) ?? (record["dateCreated"] as? Date) ?? Date()

        let affirmation: Affirmation
        if let existingAffirmation = (try? context.fetch(request))?.first {
            if let currentDate = existingAffirmation.updatedAt, currentDate >= recordDate {
                return
            }
            affirmation = existingAffirmation
        } else {
            affirmation = Affirmation(context: context)
            affirmation.id = uuid
            affirmation.dateCreated = (record["dateCreated"] as? Date) ?? Date()
            logger.debug("Created local affirmation from CloudKit record \(uuid.uuidString, privacy: .public)")
        }

        affirmation.text = record["text"] as? String ?? affirmation.text
        affirmation.repeatCount = (record["repeatCount"] as? Int32) ?? affirmation.repeatCount
        affirmation.targetCount = (record["targetCount"] as? Int32) ?? affirmation.targetCount
        if let updated = record["updatedAt"] as? Date {
            affirmation.updatedAt = updated
        }
        if let lastPracticed = record["lastPracticedAt"] as? Date {
            affirmation.lastPracticedAt = lastPracticed
        }
        if let archived = record["isArchived"] as? Bool {
            affirmation.isArchived = archived
        }
        if let wordData = record["wordTimings"] as? Data {
            affirmation.wordTimingsData = wordData
        }
        if let audioFileName = record["audioFileName"] as? String {
            affirmation.audioFileName = audioFileName
        }

        if affirmation.updatedAt == nil {
            affirmation.updatedAt = recordDate
        }
        if affirmation.isArchivedRaw == nil {
            affirmation.isArchived = false
        }

        if let asset = record["audio"] as? CKAsset, let fileURL = asset.fileURL {
            do {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destination = documentsPath.appendingPathComponent("\(affirmation.id.uuidString).m4a")
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: fileURL, to: destination)
                affirmation.audioFileName = destination.lastPathComponent
            } catch {
                print("⚠️ [CloudSyncService] Failed to copy audio asset: \(error)")
                logger.error("Failed to copy audio asset for record \(affirmation.id.uuidString, privacy: .public): \(error as NSError, privacy: .public)")
            }
        }
    }
}

extension CloudSyncService {
    static func liveService(persistence: PersistenceController = .shared) -> CloudSyncService {
        let context = persistence.container.viewContext
        return CloudSyncService(context: context)
    }
}
