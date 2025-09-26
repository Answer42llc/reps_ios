import XCTest
import CoreData
@testable import SelfLie

final class NotificationManagerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try clearAffirmations()
    }

    override func tearDown() async throws {
        try clearAffirmations()
        try await super.tearDown()
    }

    func testHasPracticedTodayWhenRecentEntryExists() throws {
        let context = PersistenceController.shared.container.viewContext
        try context.performAndWait {
            let affirmation = Affirmation(context: context)
            affirmation.id = UUID()
            affirmation.text = "Today"
            affirmation.audioFileName = "today.m4a"
            affirmation.repeatCount = 1
            affirmation.targetCount = 1000
            affirmation.dateCreated = Date()
            affirmation.updatedAt = Date()
            affirmation.lastPracticedAt = Date()
            affirmation.isArchived = false
            try context.save()
        }

        XCTAssertTrue(NotificationManager.shared.hasPracticedToday)
    }

    func testHasPracticedTodayIsFalseForArchivedOrOldEntries() throws {
        let context = PersistenceController.shared.container.viewContext
        try context.performAndWait {
            let oldAffirmation = Affirmation(context: context)
            oldAffirmation.id = UUID()
            oldAffirmation.text = "Old"
            oldAffirmation.audioFileName = "old.m4a"
            oldAffirmation.repeatCount = 5
            oldAffirmation.targetCount = 1000
            oldAffirmation.dateCreated = Date().addingTimeInterval(-172_800)
            oldAffirmation.updatedAt = Date().addingTimeInterval(-172_800)
            oldAffirmation.lastPracticedAt = Date().addingTimeInterval(-172_800)
            oldAffirmation.isArchived = false

            let archivedAffirmation = Affirmation(context: context)
            archivedAffirmation.id = UUID()
            archivedAffirmation.text = "Archived"
            archivedAffirmation.audioFileName = "archived.m4a"
            archivedAffirmation.repeatCount = 2
            archivedAffirmation.targetCount = 1000
            archivedAffirmation.dateCreated = Date()
            archivedAffirmation.updatedAt = Date()
            archivedAffirmation.lastPracticedAt = Date()
            archivedAffirmation.isArchived = true

            try context.save()
        }

        XCTAssertFalse(NotificationManager.shared.hasPracticedToday)
    }

    private func clearAffirmations() throws {
        let context = PersistenceController.shared.container.viewContext
        try context.performAndWait {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Affirmation")
            let delete = NSBatchDeleteRequest(fetchRequest: fetch)
            try context.persistentStoreCoordinator?.execute(delete, with: context)
            try context.save()
        }
    }
}
