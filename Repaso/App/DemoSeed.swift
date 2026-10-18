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
              (try? ctx.fetchCount(FetchDescriptor<Recording>())) == 0 else { return }
        let docs = env.videos.directory.deletingLastPathComponent()
        let seed = docs.appendingPathComponent("seed.mov")
        guard FileManager.default.fileExists(atPath: seed.path) else { return }
        do {
            let meta = try await VideoMetadata.load(seed)
            let lib = env.library(ctx)
            func recording(recordedAt: Date? = nil) throws -> Recording {
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
                try FileManager.default.copyItem(at: seed, to: copy)
                return try lib.addRecording(fileName: try env.videos.adopt(fileAt: copy), duration: meta.duration,
                                            recordedAt: recordedAt ?? meta.recordedAt, photosAssetID: nil)
            }

            let footwork = try lib.createFolder(named: "Footwork", in: nil)
            let turns = try lib.createFolder(named: "Turns", in: nil)
            let hammerlock = try lib.createFolder(named: "Hammerlock", in: turns)

            // A class kept whole, with three clips cut from it.
            let teachers = ["Ataca & Alemana"]
            let thursday = try recording()
            let whole = try lib.addWholeClip(to: thursday, name: "Thursday class", instructors: teachers)
            let c1 = try lib.addClip(to: thursday, name: "Hammerlock exit", instructors: teachers, start: 4, end: 12)
            let c2 = try lib.addClip(to: thursday, name: "Double turn prep", instructors: teachers, start: 18, end: 24)
            let c3 = try lib.addClip(to: thursday, name: "Wrap and unwrap", instructors: teachers, start: 30, end: 41)
            try lib.setNote(c1, "Keep her right hand low until count 3, then lift.")
            try lib.setNote(c2, "Prep on 4, turn on 5 and 6.")
            try lib.toggleFavorite(c1)
            try lib.toggleLearned(c2)
            try lib.finish(thursday, folders: [whole.id: turns, c1.id: hammerlock, c2.id: turns, c3.id: turns])

            let saturday = try recording()
            let basic = try lib.addClip(to: saturday, name: "Basic with styling", instructors: [], start: 44, end: 50)
            try lib.finish(saturday, folders: [basic.id: footwork])

            // Still in Unsorted, one clip named before Continue later.
            let sunday = try recording(recordedAt: Date(timeIntervalSince1970: 1_791_000_000))
            _ = try lib.addClip(to: sunday, name: "Cross body lead", instructors: teachers, start: 2, end: 8)

            // -seedImport: two more videos, as if just picked, with the guide open on them (the Photos picker can't be
            // driven from UI tests).
            if ProcessInfo.processInfo.arguments.contains("-seedImport") {
                let picked = [try recording(), try recording()]
                env.guide = ImportGuideModel(resuming: picked, env: env, context: ctx)
            }

            // -seedLarge: a 240-clip folder, for the scroll performance test (acceptance: smooth with 200+ clips).
            if ProcessInfo.processInfo.arguments.contains("-seedLarge") {
                let practice = try lib.createFolder(named: "Practice", in: nil)
                for n in 0..<6 {
                    let workshop = try recording()
                    var folders: [UUID: Folder] = [:]
                    for i in 0..<40 {
                        let start = Double(i % 25) * 2
                        let clip = try lib.addClip(to: workshop, name: "Workshop \(n + 1) move \(i + 1)", instructors: [],
                                                   start: start, end: start + 1.5)
                        folders[clip.id] = practice
                    }
                    try lib.finish(workshop, folders: folders)
                }
            }
        } catch {
            print("DemoSeed failed: \(error)")
        }
    }
}
#endif
