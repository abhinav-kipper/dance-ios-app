import SwiftUI
import SwiftData
import RepasoCore

/// Portrait only (the Info.plist lists every orientation for iOS 26's multitasking checks).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct RepasoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Held for the app's lifetime: a ModelContext traps once its container is gone.
    private let container: ModelContainer
    /// UI tests use an empty in-memory store; the orphan sweep would then delete every real video.
    private let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    @State private var env: AppEnvironment

    init() {
        do {
            if uiTesting {
                UserDefaults.standard.removeObject(forKey: "import.lastFolderID")   // each test starts with no remembered folder
            } else {
                RepasoSchema.removeLegacyStore()   // clips-only model: the old store isn't migrated
            }
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
                    ShareSheet.clearExports()
                }
        }
        .modelContainer(container)
    }
}
