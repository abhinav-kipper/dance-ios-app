import Foundation
import SwiftData

@Model
public final class Clip {
    /// How close to the ends a clip may be and still count as the whole video.
    public static let wholeTolerance = 0.05

    @Attribute(.unique) public var id: UUID
    public var name: String
    public var instructors: [String] = []
    public var start: Double
    public var end: Double
    public var note: String?
    public var isFavorite: Bool = false
    public var isLearned: Bool = false
    public var lastPlayedAt: Date?
    public var addedAt: Date
    public var sortIndex: Int
    public var zoom: Double = 1
    public var panX: Double = 0
    public var panY: Double = 0
    public var recording: Recording?
    /// Where it lives; nil only while its recording is pending.
    public var folder: Folder?
    /// Its place in its folder once the folder has been arranged by hand; nil until then (and again after it moves).
    public var folderOrder: Int?
    /// Extra folders it also shows in.
    @Relationship(deleteRule: .nullify, inverse: \Folder.linkedClips) public var linkedFolders: [Folder] = []

    public init(name: String, start: Double, end: Double, sortIndex: Int, recording: Recording, addedAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.start = start
        self.end = end
        self.sortIndex = sortIndex
        self.recording = recording
        self.addedAt = addedAt
    }

    public var length: Double { end - start }

    /// True when the clip is the full video (the one kept at the guide's "Keep it").
    public var coversWholeRecording: Bool {
        guard let recording else { return false }
        return start <= Self.wholeTolerance && end >= recording.duration - Self.wholeTolerance
    }

    /// Shown in folders, search and the Player: its recording has been through the guide.
    public var isFiled: Bool { recording.map { !$0.isPending } ?? false }

    public var thumbnailRequest: ThumbnailRequest? {
        guard let recording else { return nil }
        return ThumbnailRequest(id: id, fileName: recording.fileName, time: start + (end - start) * 0.3)
    }
}
