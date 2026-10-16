#if DEBUG
import Foundation
import SwiftData
import RepasoCore

/// `-seedDemo`: builds a small library from `Documents/seed.mov` (copied in with `simctl get_app_container`)
/// so UI walkthroughs don't depend on the system Photos picker. Debug builds only.
@MainActor
enum DemoSeed {
    static func runIfRequested(_ ctx: ModelContext, env: AppEnvironment) async {
        guard ProcessInfo.processInfo.arguments.contains("-seedDemo"),
              (try? ctx.fetchCount(FetchDescriptor<Original>())) == 0 else { return }
        let docs = env.videos.directory.deletingLastPathComponent()
        let seed = docs.appendingPathComponent("seed.mov")
        guard FileManager.default.fileExists(atPath: seed.path) else { return }
        do {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: seed, to: copy)
            let meta = try await VideoMetadata.load(copy)
            let lib = env.library(ctx)

            let footwork = try lib.createFolder(named: "Footwork", in: nil)
            let turns = try lib.createFolder(named: "Turns", in: nil)
            let hammerlock = try lib.createFolder(named: "Hammerlock", in: turns)

            let thursday = try lib.addOriginal(title: "Thursday class", fileName: try env.videos.adopt(fileAt: copy),
                                               duration: meta.duration, recordedAt: meta.recordedAt, to: turns)
            let c1 = try lib.addClip(to: thursday, start: 4, end: 12)
            let c2 = try lib.addClip(to: thursday, start: 18, end: 24)
            let c3 = try lib.addClip(to: thursday, start: 30, end: 41)
            try lib.updateInfo(c1, name: "Hammerlock exit", note: "Keep her right hand low until count 3, then lift.")
            try lib.updateInfo(c2, name: "Double turn prep", note: "Prep on 4, turn on 5 and 6.")
            try lib.updateInfo(c3, name: "Wrap and unwrap", note: "")
            try lib.toggleFavorite(c1)
            try lib.toggleLearned(c2)
            try lib.moveClip(c1, to: hammerlock)

            let copy2 = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: seed, to: copy2)
            let saturday = try lib.addOriginal(title: "Saturday social", fileName: try env.videos.adopt(fileAt: copy2),
                                               duration: meta.duration, recordedAt: nil, to: nil)
            let loose = try lib.addClip(to: saturday, start: 44, end: 50)
            try lib.updateInfo(loose, name: "Basic with styling", note: "")
            try lib.moveClip(loose, to: footwork)

            // -seedLarge: a 240-clip folder, for the scroll performance test (acceptance: smooth with 200+ clips).
            if ProcessInfo.processInfo.arguments.contains("-seedLarge") {
                let practice = try lib.createFolder(named: "Practice", in: nil)
                for n in 0..<6 {
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
                    try FileManager.default.copyItem(at: seed, to: copy)
                    let original = try lib.addOriginal(title: "Workshop \(n + 1)", fileName: try env.videos.adopt(fileAt: copy),
                                                       duration: meta.duration, recordedAt: nil, to: practice)
                    for i in 0..<40 {
                        let start = Double(i % 25) * 2
                        try lib.addClip(to: original, start: start, end: start + 1.5)
                    }
                }
            }
        } catch {
            print("DemoSeed failed: \(error)")
        }
    }
}
#endif
