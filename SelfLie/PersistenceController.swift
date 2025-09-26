import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Add sample data for previews
        let sampleAffirmation = Affirmation(context: viewContext)
        sampleAffirmation.id = UUID()
        sampleAffirmation.text = "I never smoke, because smoking is smelly"
        sampleAffirmation.audioFileName = "sample.m4a"
        sampleAffirmation.repeatCount = 84
        sampleAffirmation.targetCount = 1000
        sampleAffirmation.dateCreated = Date()
        sampleAffirmation.updatedAt = Date()
        sampleAffirmation.lastPracticedAt = Date()
        sampleAffirmation.isArchived = false

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SelfLie")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        backfillAffirmationMetadataIfNeeded()
    }

    func backfillAffirmationMetadataIfNeeded() {
        let context = container.viewContext
        context.perform {
            let request: NSFetchRequest<Affirmation> = Affirmation.fetchRequest()
            request.predicate = NSPredicate(format: "updatedAt == nil OR (repeatCount > 0 AND lastPracticedAt == nil) OR audioFileName == nil")
            request.fetchBatchSize = 100

            do {
                let results = try context.fetch(request)
                var didChange = false

                for affirmation in results {
                    if affirmation.updatedAt == nil {
                        affirmation.updatedAt = affirmation.dateCreated
                        didChange = true
                    }

                    if affirmation.lastPracticedAt == nil, affirmation.repeatCount > 0 {
                        affirmation.lastPracticedAt = affirmation.dateCreated
                        didChange = true
                    }

                    if affirmation.audioFileName == nil {
                        affirmation.audioFileName = ""
                        didChange = true
                    }

                    if affirmation.isArchivedRaw == nil {
                        affirmation.isArchived = false
                        didChange = true
                    }
                }

                if didChange {
                    try context.save()
                }
            } catch {
                // Ignore backfill errors for now; production logging can be added later.
            }
        }
    }
}
