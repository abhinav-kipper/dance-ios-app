import SwiftUI
import SwiftData
import RepasoCore

@main
struct RepasoApp: App {
    /// Held for the app's lifetime: a ModelContext traps once its container is gone.
    private let container: ModelContainer
    /// UI tests use an empty in-memory store; the orphan sweep would then delete every real video.
    private let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    @State private var env: AppEnvironment

    init() {
        do {
            container = try RepasoSchema.makeContainer(inMemory: uiTesting)
            _env = State(initialValue: try AppEnvironment())
        } catch {
            fatalError("Repaso storage unavailable: \(error)")   // no writable sandbox: unrecoverable
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(env)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    #if DEBUG
                    await DemoSeed.runIfRequested(container.mainContext, env: env)
                    #endif
                    if !uiTesting { env.sweepOrphans(container.mainContext) }
                }
        }
        .modelContainer(container)
    }
}
