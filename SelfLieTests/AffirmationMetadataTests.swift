import XCTest
import CoreData
@testable import SelfLie

final class AffirmationMetadataTests: XCTestCase {
    func testBackfillPopulatesMissingTimestamps() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let creationDate = Date(timeIntervalSince1970: 1_000_000)

        let affirmation = Affirmation(context: context)
        affirmation.id = UUID()
        affirmation.text = "Test"
        affirmation.audioFileName = "test.m4a"
        affirmation.repeatCount = 5
        affirmation.targetCount = 1000
        affirmation.dateCreated = creationDate
        affirmation.setValue(nil, forKey: "updatedAt")
        affirmation.lastPracticedAt = nil
        affirmation.isArchived = false

        try context.save()

        persistence.backfillAffirmationMetadataIfNeeded()

        let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
        request.fetchLimit = 1
        let result = try context.fetch(request).first

        XCTAssertNotNil(result?.updatedAt)
        XCTAssertEqual(result?.updatedAt, creationDate)
        XCTAssertNotNil(result?.lastPracticedAt)
        XCTAssertEqual(result?.lastPracticedAt, creationDate)
    }

    func testBackfillLeavesLastPracticedNilWhenNoReps() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let creationDate = Date(timeIntervalSince1970: 2_000_000)

        let affirmation = Affirmation(context: context)
        affirmation.id = UUID()
        affirmation.text = "Zero Reps"
        affirmation.audioFileName = "zero.m4a"
        affirmation.repeatCount = 0
        affirmation.targetCount = 1000
        affirmation.dateCreated = creationDate
        affirmation.setValue(nil, forKey: "updatedAt")
        affirmation.lastPracticedAt = nil
        affirmation.isArchived = false

        try context.save()

        persistence.backfillAffirmationMetadataIfNeeded()

        let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
        request.fetchLimit = 1
        let result = try context.fetch(request).first

        XCTAssertNotNil(result?.updatedAt)
        XCTAssertEqual(result?.updatedAt, creationDate)
        XCTAssertNil(result?.lastPracticedAt)
    }
}
