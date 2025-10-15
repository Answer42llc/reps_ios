import Foundation
import CloudKit
import CoreData
import Observation
import OSLog

@MainActor
protocol CloudSyncCoordinating: AnyObject {
    func activateSync()
    func deactivateSync()
    func enqueueUpload(for affirmationID: NSManagedObjectID)
    func enqueueDeletion(for affirmationID: NSManagedObjectID)
    func requestFullSync()
    var isBusy: Bool { get }
    var lastSyncDate: Date? { get }
}

@MainActor
@Observable
final class CloudSyncService: CloudSyncCoordinating {
    private struct Constants {
        static let zoneName = "AffirmationsZone"
        static let subscriptionID = "cloudsync.subscription"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let context: NSManagedObjectContext
    private let logger: Logger
    private let stateStore: CloudSyncStateStore
    @ObservationIgnored
    private lazy var syncEngine: CKSyncEngine = {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateStore.load(),
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        logger.debug("CloudSyncService initialised using CKSyncEngine")
        return engine
    }()

    private(set) var isConfigured = false
    private(set) var lastSyncError: Error?
    private var isSyncEnabled = false
    private var isPerformingSync = false
    private var lastFetchDate: Date?
    private var syncTask: Task<Void, Never>?
    private var resyncRequested = false
    private var forceResyncRequested = false

    var isBusy: Bool { isPerformingSync }
    var lastSyncDate: Date? { lastFetchDate }

    init(container: CKContainer = CKContainer.default(),
         databaseScope: CKDatabase.Scope = .private,
         context: NSManagedObjectContext) {
        self.container = container
        self.database = container.database(with: databaseScope)
        self.context = context
        self.zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        self.stateStore = CloudSyncStateStore()
        let subsystem = Bundle.main.bundleIdentifier ?? "SelfLie"
        self.logger = Logger(subsystem: subsystem, category: "CloudSync")

    }

    func activateSync() {
        let wasEnabled = isSyncEnabled
        guard !wasEnabled else {
            startIfNeeded()
            return
        }

        isSyncEnabled = true
        logger.notice("Sync enabled")

        startIfNeeded()

        if isConfigured {
            scheduleSync(forceFetch: true)
        }
    }

    func deactivateSync() {
        guard isSyncEnabled else { return }
        isSyncEnabled = false
        logger.notice("Sync disabled")

        syncTask?.cancel()
        syncTask = nil
        isPerformingSync = false
    }

    private func startIfNeeded() {
        guard !isConfigured else { return }
        logger.debug("Starting CloudSyncService")
        configureZoneIfNeeded()
        registerSubscriptionIfNeeded()
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
        var recordID: CKRecord.ID?
        context.performAndWait {
            guard let affirmation = try? context.existingObject(with: affirmationID) as? Affirmation, affirmation.isActive else {
                return
            }
            recordID = CKRecord.ID(recordName: affirmation.id.uuidString, zoneID: zoneID)
        }

        guard let recordID else { return }

        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        scheduleSync()
    }

    func enqueueDeletion(for affirmationID: NSManagedObjectID) {
        guard isConfigured else {
            logger.debug("enqueueDeletion skipped – service not configured yet")
            return
        }
        guard isSyncEnabled else {
            logger.debug("enqueueDeletion skipped – sync disabled")
            return
        }

        var recordID: CKRecord.ID?
        context.performAndWait {
            guard let affirmation = try? context.existingObject(with: affirmationID) as? Affirmation else {
                return
            }
            recordID = CKRecord.ID(recordName: affirmation.id.uuidString, zoneID: zoneID)
        }

        guard let recordID else { return }

        syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        scheduleSync()
    }

    func requestFullSync() {
        guard isConfigured, isSyncEnabled else { return }
        scheduleSync(forceFetch: true)
    }

    func setSyncEnabled(_ enabled: Bool) {
        if enabled {
            activateSync()
        } else {
            deactivateSync()
        }
    }

    private func scheduleSync(forceFetch: Bool = false) {
        if let _ = syncTask {
            resyncRequested = true
            if forceFetch {
                forceResyncRequested = true
            }
            return
        }

        resyncRequested = false
        forceResyncRequested = false

        syncTask = Task.detached { [weak self] in
            await self?.runSyncCycle(forceFetch: forceFetch)
        }
    }

    @MainActor
    private func runSyncCycle(forceFetch: Bool) async {
        defer { syncTask = nil }
        guard isSyncEnabled else { return }

        var shouldForceFetch = forceFetch

        repeat {
            do {
                if shouldForceFetch {
                    try await syncEngine.fetchChanges()
                }

                if !syncEngine.state.pendingDatabaseChanges.isEmpty || !syncEngine.state.pendingRecordZoneChanges.isEmpty {
                    try await syncEngine.sendChanges()
                }

                try await syncEngine.fetchChanges()
            } catch {
                handleSyncError(error)
            }

            let repeatRequested = resyncRequested
            shouldForceFetch = forceResyncRequested
            resyncRequested = false
            forceResyncRequested = false

            if !repeatRequested { break }
        } while true
    }

    private func handleSyncError(_ error: Error) {
        if let ckError = error as? CKError,
           ckError.code == .partialFailure,
           let partialErrors = ckError.partialErrorsByItemID as? [CKRecord.ID: CKError],
           partialErrors.values.allSatisfy({ $0.code == .serverRecordChanged }) {
            logger.notice("Sync conflict resolved by retrying server-changed records")
            return
        }
        lastSyncError = error
        logger.error("Sync engine operation failed: \(error as NSError, privacy: .public)")
    }

    private func registerSubscriptionIfNeeded() {
        let subscription = CKDatabaseSubscription(subscriptionID: Constants.subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
        operation.modifySubscriptionsResultBlock = { [weak self] result in
            if case .failure(let error) = result {
                self?.logger.error("Failed to register CloudKit subscription: \(error as NSError, privacy: .public)")
            }
        }
        database.add(operation)
    }

    private func configureZoneIfNeeded() {
        let zone = CKRecordZone(zoneID: zoneID)
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: [])
        operation.modifyRecordZonesResultBlock = { [weak self] result in
            if case .failure(let error) = result {
                self?.logger.error("Failed to ensure CloudKit zone: \(error as NSError, privacy: .public)")
            }
        }
        database.add(operation)
    }

    nonisolated private func makeRecord(from affirmation: Affirmation) -> CKRecord {
        let recordID = CKRecord.ID(recordName: affirmation.id.uuidString, zoneID: zoneID)
        let record: CKRecord

        if let systemData = affirmation.syncRecordSystemFields {
            do {
                let coder = try NSKeyedUnarchiver(forReadingFrom: systemData)
                coder.requiresSecureCoding = true
                if let decoded = CKRecord(coder: coder) {
                    record = decoded
                } else {
                    record = CKRecord(recordType: "Affirmation", recordID: recordID)
                }
                coder.finishDecoding()
            } catch {
                record = CKRecord(recordType: "Affirmation", recordID: recordID)
            }
        } else {
            record = CKRecord(recordType: "Affirmation", recordID: recordID)
        }

        record["text"] = affirmation.text
        record["repeatCount"] = affirmation.repeatCount as NSNumber
        record["targetCount"] = affirmation.targetCount as NSNumber
        record["dateCreated"] = affirmation.dateCreated as NSDate
        let updatedAt = affirmation.updatedAt ?? affirmation.dateCreated
        record["updatedAt"] = updatedAt as NSDate
        if let audioFileName = affirmation.audioFileName, !audioFileName.isEmpty {
            record["audioFileName"] = audioFileName as NSString
        } else {
            record["audioFileName"] = nil
        }
        if let lastPracticed = affirmation.lastPracticedAt {
            record["lastPracticedAt"] = lastPracticed as NSDate
        } else {
            record["lastPracticedAt"] = nil
        }
        record["isArchived"] = NSNumber(value: affirmation.isArchived)
        if let wordData = affirmation.wordTimingsData {
            record["wordTimings"] = wordData as NSData
        } else {
            record["wordTimings"] = nil
        }

        if let assetURL = affirmation.audioURL, FileManager.default.fileExists(atPath: assetURL.path) {
            record["audio"] = CKAsset(fileURL: assetURL)
        } else {
            record["audio"] = nil
        }

        return record
    }

    @MainActor
    private func recordForUpload(with recordID: CKRecord.ID) -> CKRecord? {
        guard let uuid = UUID(uuidString: recordID.recordName) else {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }

        let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1

        guard let affirmation = try? context.fetch(request).first else {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }

        if affirmation.isDeleted {
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }

        return makeRecord(from: affirmation)
    }

    @MainActor
    private func clearSystemFields(for recordID: CKRecord.ID) {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return }

        let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1

        if let affirmation = try? context.fetch(request).first {
            affirmation.syncRecordSystemFields = nil
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    logger.error("Failed to clear system fields for record \(recordID.recordName, privacy: .public): \(error as NSError, privacy: .public)")
                }
            }
        }
    }

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

    private func applyDeletions(for recordIDs: [CKRecord.ID]) async throws {
        guard !recordIDs.isEmpty else { return }
        let context = self.context
        try await context.perform {
            for recordID in recordIDs {
                guard let uuid = UUID(uuidString: recordID.recordName) else { continue }
                let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                request.fetchLimit = 1
                if let affirmation = try? context.fetch(request).first {
                    context.delete(affirmation)
                }
            }
            if context.hasChanges {
                try context.save()
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
            affirmation = existingAffirmation
        } else {
            affirmation = Affirmation(context: context)
            affirmation.id = uuid
            affirmation.dateCreated = (record["dateCreated"] as? Date) ?? Date()
            logger.debug("Created local affirmation from CloudKit record \(uuid.uuidString, privacy: .public)")
        }

        let currentDate = affirmation.updatedAt ?? .distantPast
        let serverIsNewer = currentDate < recordDate

        if serverIsNewer {
            affirmation.text = record["text"] as? String ?? affirmation.text
            affirmation.repeatCount = (record["repeatCount"] as? Int32) ?? affirmation.repeatCount
            affirmation.targetCount = (record["targetCount"] as? Int32) ?? affirmation.targetCount
            if let updated = record["updatedAt"] as? Date {
                affirmation.updatedAt = updated
            } else {
                affirmation.updatedAt = recordDate
            }
            if let lastPracticed = record["lastPracticedAt"] as? Date {
                affirmation.lastPracticedAt = lastPracticed
            }
            if let wordData = record["wordTimings"] as? Data {
                affirmation.wordTimingsData = wordData
            }
            if let audioFileName = record["audioFileName"] as? String {
                affirmation.audioFileName = audioFileName
            }
        }

        if let archived = record["isArchived"] as? Bool {
            affirmation.isArchived = archived
        }

        if affirmation.updatedAt == nil {
            affirmation.updatedAt = recordDate
        }
        if affirmation.isArchivedRaw == nil {
            affirmation.isArchived = false
        }

        do {
            let coder = NSKeyedArchiver(requiringSecureCoding: true)
            record.encodeSystemFields(with: coder)
            coder.finishEncoding()
            affirmation.syncRecordSystemFields = coder.encodedData
        } catch {
            logger.error("Failed to archive system fields for record \(record.recordID.recordName, privacy: .public): \(error as NSError, privacy: .public)")
        }

        if let asset = record["audio"] as? CKAsset, let fileURL = asset.fileURL {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = documentsPath.appendingPathComponent("\(affirmation.id.uuidString).m4a")

            let resolvedSource = fileURL.resolvingSymlinksInPath()
            let resolvedDestination = destination.resolvingSymlinksInPath()

            // If the asset already lives at the expected destination, no copy is necessary.
            guard resolvedSource != resolvedDestination else {
                affirmation.audioFileName = destination.lastPathComponent
                return
            }

            do {
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

extension CloudSyncService: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            do {
                try stateStore.save(update.stateSerialization)
            } catch {
                logger.error("Failed to persist sync state: \(error as NSError, privacy: .public)")
            }
        case .accountChange:
            logger.notice("Account changed; resetting sync state")
            stateStore.reset()
            let pendingRecordChanges = syncEngine.state.pendingRecordZoneChanges
            if !pendingRecordChanges.isEmpty {
                syncEngine.state.remove(pendingRecordZoneChanges: pendingRecordChanges)
            }
            let pendingDatabaseChanges = syncEngine.state.pendingDatabaseChanges
            if !pendingDatabaseChanges.isEmpty {
                syncEngine.state.remove(pendingDatabaseChanges: pendingDatabaseChanges)
            }
            lastFetchDate = nil
            scheduleSync(forceFetch: true)
        case .willFetchChanges:
            isPerformingSync = true
        case .didFetchChanges:
            isPerformingSync = false
            lastSyncError = nil
            lastFetchDate = Date()
        case .fetchedRecordZoneChanges(let details):
            let records = details.modifications.compactMap { $0.record }
            do {
                try await merge(records: records)
                try await applyDeletions(for: details.deletions.map { $0.recordID })
            } catch {
                handleSyncError(error)
            }
        case .sentRecordZoneChanges(let result):
            if !result.savedRecords.isEmpty {
                do {
                    try await merge(records: result.savedRecords)
                } catch {
                    handleSyncError(error)
                }
            }

            var pendingRecordChanges: [CKSyncEngine.PendingRecordZoneChange] = []
            var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []

            for failure in result.failedRecordSaves {
                let recordID = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    if let serverRecord = failure.error.serverRecord {
                        do {
                            try await merge(records: [serverRecord])
                        } catch {
                            logger.error("Failed to merge server record after conflict: \(error as NSError, privacy: .public)")
                        }
                    } else {
                        logger.error("Server record missing for conflict on \(recordID.recordName, privacy: .public)")
                    }
                    pendingRecordChanges.append(.saveRecord(recordID))
                case .zoneNotFound:
                    pendingDatabaseChanges.append(.saveZone(CKRecordZone(zoneID: recordID.zoneID)))
                    pendingRecordChanges.append(.saveRecord(recordID))
                    clearSystemFields(for: recordID)
                case .unknownItem:
                    clearSystemFields(for: recordID)
                    pendingRecordChanges.append(.saveRecord(recordID))
                case .networkFailure, .networkUnavailable, .serviceUnavailable, .zoneBusy, .notAuthenticated, .operationCancelled:
                    logger.debug("Retryable error while saving record \(recordID.recordName, privacy: .public): \(failure.error as NSError, privacy: .public)")
                default:
                    logger.error("Unhandled error saving record \(recordID.recordName, privacy: .public): \(failure.error as NSError, privacy: .public)")
                }
            }

            for (recordID, error) in result.failedRecordDeletes {
                switch error.code {
                case .zoneNotFound:
                    pendingDatabaseChanges.append(.saveZone(CKRecordZone(zoneID: recordID.zoneID)))
                    pendingRecordChanges.append(.deleteRecord(recordID))
                case .serverRecordChanged:
                    pendingRecordChanges.append(.deleteRecord(recordID))
                case .networkFailure, .networkUnavailable, .serviceUnavailable, .zoneBusy, .notAuthenticated, .operationCancelled:
                    logger.debug("Retryable error deleting record \(recordID.recordName, privacy: .public): \(error as NSError, privacy: .public)")
                case .unknownItem:
                    // The record is already gone; nothing else to do.
                    break
                default:
                    logger.error("Unhandled error deleting record \(recordID.recordName, privacy: .public): \(error as NSError, privacy: .public)")
                }
            }

            let hasDatabaseChanges = !pendingDatabaseChanges.isEmpty
            let hasRecordChanges = !pendingRecordChanges.isEmpty

            if hasDatabaseChanges {
                syncEngine.state.add(pendingDatabaseChanges: pendingDatabaseChanges)
            }
            if hasRecordChanges {
                syncEngine.state.add(pendingRecordZoneChanges: pendingRecordChanges)
            }

            if hasDatabaseChanges || hasRecordChanges {
                scheduleSync()
            }
        case .willSendChanges:
            isPerformingSync = true
        case .didSendChanges:
            isPerformingSync = false
            lastSyncError = nil
            lastFetchDate = Date()
        default:
            break
        }
    }

    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        if isSyncEnabled {
            return CKSyncEngine.FetchChangesOptions()
        } else {
            return CKSyncEngine.FetchChangesOptions(scope: .allExcluding([zoneID]))
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pendingChanges.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) { recordID in
            await MainActor.run {
                self.recordForUpload(with: recordID)
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
