import Foundation
import CloudKit

@MainActor
struct CloudSyncStateStore {
    private let fileURL: URL

    init(filename: String = "cloudsync-state.json") {
        let baseDirectory: URL
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseDirectory = appSupport
        } else {
            baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }

        if !FileManager.default.fileExists(atPath: baseDirectory.path) {
            try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }

        self.fileURL = baseDirectory.appendingPathComponent(filename)
    }

    func load() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func save(_ serialization: CKSyncEngine.State.Serialization) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(serialization)
        try data.write(to: fileURL, options: [.atomic])
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
