import Foundation
import CoreData

@objc(Affirmation)
public class Affirmation: NSManagedObject, Identifiable {
    
}

extension Affirmation {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Affirmation> {
        return NSFetchRequest<Affirmation>(entityName: "Affirmation")
    }

    @NSManaged public var id: UUID
    @NSManaged public var text: String
    @NSManaged public var audioFileName: String?
    @NSManaged public var repeatCount: Int32
    @NSManaged public var targetCount: Int32
    @NSManaged public var dateCreated: Date
    @NSManaged public var updatedAt: Date?
    @NSManaged public var lastPracticedAt: Date?
    @NSManaged public var syncRecordSystemFields: Data?
    @NSManaged @objc(isArchived) internal var isArchivedRaw: NSNumber?
    @NSManaged public var wordTimingsData: Data?
    
    var audioURL: URL? {
        guard let audioFileName, !audioFileName.isEmpty else { return nil }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(audioFileName)
    }
    
    var progressText: String {
        return "\(repeatCount)/\(targetCount)"
    }
    
    var progressPercentage: Float {
        return Float(repeatCount) / Float(targetCount)
    }

    var isArchived: Bool {
        get { isArchivedRaw?.boolValue ?? false }
        set { isArchivedRaw = NSNumber(value: newValue) }
    }

    var isActive: Bool {
        !isArchived
    }
    
    /// Word timings for precise playback highlighting
    var wordTimings: [WordTiming] {
        get {
            guard let data = wordTimingsData else { return [] }
            do {
                return try JSONDecoder().decode([WordTiming].self, from: data)
            } catch {
                print("⚠️ Failed to decode word timings: \(error)")
                return []
            }
        }
        set {
            do {
                wordTimingsData = try JSONEncoder().encode(newValue)
            } catch {
                print("⚠️ Failed to encode word timings: \(error)")
                wordTimingsData = nil
            }
        }
    }
    
}
