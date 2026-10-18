import Foundation
@testable import RepasoCore

/// Test shortcuts for a library that already went through the import guide.
@MainActor
extension LibraryService {
    /// A recording that has been through the guide (not pending).
    func filedRecording(_ fileName: String = "\(UUID().uuidString).mov", duration: Double = 120,
                        recordedAt: Date? = nil) throws -> Recording {
        let r = try addRecording(fileName: fileName, duration: duration, recordedAt: recordedAt, photosAssetID: nil)
        r.isPending = false
        try context.save()
        return r
    }

    /// A named clip filed in `folder`, on `recording` or a fresh one of its own.
    func filedClip(_ name: String = "Clip", in folder: Folder, on recording: Recording? = nil,
                   start: Double = 1, end: Double = 3, instructors: [String] = []) throws -> Clip {
        let r = try recording ?? filedRecording()
        let clip = try addClip(to: r, name: name, instructors: instructors, start: start, end: end)
        try moveClip(clip, to: folder)
        return clip
    }
}
