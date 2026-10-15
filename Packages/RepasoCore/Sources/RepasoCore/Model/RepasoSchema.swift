import SwiftData

public enum RepasoSchema {
    public static let models: [any PersistentModel.Type] = [Folder.self, Original.self, Clip.self]

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(models), configurations: config)
    }
}
