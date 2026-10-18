import Foundation
import SwiftData

public enum RepasoSchema {
    public static let models: [any PersistentModel.Type] = [Folder.self, Recording.self, Clip.self]
    /// A fresh file for the clips-only model; the old `default.store` is not migrated (see `removeLegacyStore`).
    static let storeName = "Repaso-v2.store"

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: URL.applicationSupportDirectory.appending(path: storeName))
        return try ModelContainer(for: Schema(models), configurations: config)
    }

    /// Deletes the store from before clips were the only kind of thing. Its video files are swept separately.
    public static func removeLegacyStore() {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fm.removeItem(at: URL.applicationSupportDirectory.appending(path: "default.store\(suffix)"))
        }
    }
}
