import SwiftData
@testable import RepasoCore

/// A `ModelContext` traps once its container is deallocated, so tests keep every container alive.
@MainActor
enum TestContainers {
    static var retained: [ModelContainer] = []
}

@MainActor
func makeContext() throws -> ModelContext {
    let container = try RepasoSchema.makeContainer(inMemory: true)
    TestContainers.retained.append(container)
    return container.mainContext
}
