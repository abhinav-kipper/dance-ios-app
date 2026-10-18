import Foundation

/// The import guide's steps for one video.
public enum ImportStep: Equatable, Sendable {
    /// "Make clips from it?" (Make clips / Use the whole video)
    case trimChoice
    /// The cutter: mark a clip, name it, repeat.
    case cut
    /// "Keep the full video too?"
    case keepWhole
    /// A folder for each clip, then Finish.
    case file
}

/// Which steps a video goes through, from what it already has. Pure, so the guide's order is testable.
public struct ImportGuideFlow: Equatable, Sendable {
    public let clipCount: Int
    /// It already has a clip that is the full video (kept, or "Use the whole video").
    public let hasWholeClip: Bool
    public let keepWholeVideo: Bool?

    public init(clipCount: Int, hasWholeClip: Bool, keepWholeVideo: Bool?) {
        self.clipCount = clipCount
        self.hasWholeClip = hasWholeClip
        self.keepWholeVideo = keepWholeVideo
    }

    /// It was kept whole and named ("Use the whole video"), with nothing cut from it.
    public var usesWholeVideoOnly: Bool { clipCount == 1 && hasWholeClip }

    /// Where a video opens: at the start if nothing was made yet, at filing if it was kept whole, otherwise back in
    /// the cutter with the clips made before Continue later.
    public var startStep: ImportStep {
        if clipCount == 0 { return .trimChoice }
        return usesWholeVideoOnly ? .file : .cut
    }

    public func next(after step: ImportStep, usedWholeVideo: Bool) -> ImportStep? {
        switch step {
        case .trimChoice: usedWholeVideo ? .file : .cut
        case .cut: asksKeep ? .keepWhole : .file
        case .keepWhole: .file
        case .file: nil
        }
    }

    /// The step dots: steps that don't apply are left out, not greyed.
    public func visibleSteps(usedWholeVideo: Bool) -> [ImportStep] {
        if usedWholeVideo { return [.trimChoice, .file] }
        return asksKeep ? [.trimChoice, .cut, .keepWhole, .file] : [.trimChoice, .cut, .file]
    }

    private var asksKeep: Bool { keepWholeVideo == nil && !hasWholeClip }

    /// Every clip's folder, top to bottom: one picked by hand keeps it; any other follows the clip above it, and the
    /// first follows the last-used folder. Clips with nowhere to follow are left out.
    @MainActor
    public static func folders(for clipIDs: [UUID], picked: [UUID: Folder], lastUsed: Folder?) -> [UUID: Folder] {
        var out: [UUID: Folder] = [:]
        var previous: Folder?
        for id in clipIDs {
            let folder = picked[id] ?? defaultFolder(previousInList: previous, lastUsed: lastUsed)
            out[id] = folder
            previous = folder
        }
        return out
    }

    /// A clip's folder chip starts as the one chosen for the clip above it, else the folder last used in any import
    /// (unless that has since been deleted).
    @MainActor
    public static func defaultFolder(previousInList: Folder?, lastUsed: Folder?) -> Folder? {
        if let previousInList { return previousInList }
        guard let lastUsed, lastUsed.modelContext != nil, !lastUsed.isDeleted else { return nil }
        return lastUsed
    }
}
