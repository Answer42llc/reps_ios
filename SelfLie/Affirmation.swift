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
    @NSManaged public var audioFileName: String
    @NSManaged public var repeatCount: Int32
    @NSManaged public var targetCount: Int32
    @NSManaged public var dateCreated: Date
    
    var audioURL: URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(audioFileName)
    }
    
    var progressText: String {
        return "\(repeatCount)/\(targetCount)"
    }
    
    var progressPercentage: Float {
        return Float(repeatCount) / Float(targetCount)
    }
}
