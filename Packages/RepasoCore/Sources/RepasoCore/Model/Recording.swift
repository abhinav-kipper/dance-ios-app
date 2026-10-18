import Foundation
import SwiftData

/// A video file in the library. Never shown as a thing of its own: people see its clips (one of which may cover the
/// whole video). Pending while it's in the import guide or waiting in Unsorted.
@Model
public final class Recording {
    @Attribute(.unique) public var id: UUID
    public var fileName: String
    public var duration: Double
    public var recordedAt: Date?
    public var importedAt: Date
    /// Photos asset it was imported from, for the "Delete from Photos?" offer.
    public var photosAssetID: String?
    public var isPending: Bool = true
    /// The guide's "Keep the full video too?" answer; nil until asked. false exports the clips to their own files
    /// at Finish.
    public var keepWholeVideo: Bool?
    /// Order in Unsorted.
    public var sortIndex: Int
    @Relationship(deleteRule: .cascade, inverse: \Clip.recording) public var clips: [Clip] = []

    public init(fileName: String, duration: Double, recordedAt: Date?, photosAssetID: String?, sortIndex: Int,
                importedAt: Date = .now) {
        self.id = UUID()
        self.fileName = fileName
        self.duration = duration
        self.recordedAt = recordedAt
        self.photosAssetID = photosAssetID
        self.sortIndex = sortIndex
        self.importedAt = importedAt
    }

    public var thumbnailRequest: ThumbnailRequest {
        ThumbnailRequest(id: id, fileName: fileName, time: duration * 0.3)
    }
}
