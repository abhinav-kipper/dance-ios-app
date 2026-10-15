import Foundation
import SwiftData

@Model
public final class Original {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var fileName: String
    public var importedAt: Date
    public var recordedAt: Date?
    public var duration: Double
    public var instructors: [String] = []
    public var event: String?
    public var folder: Folder?
    public var nextClipNumber: Int = 1
    @Relationship(deleteRule: .cascade, inverse: \Clip.original) public var clips: [Clip] = []

    public init(title: String, fileName: String, duration: Double, recordedAt: Date?, folder: Folder?, importedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.fileName = fileName
        self.duration = duration
        self.recordedAt = recordedAt
        self.folder = folder
        self.importedAt = importedAt
    }

    public var thumbnailRequest: ThumbnailRequest {
        ThumbnailRequest(id: id, fileName: fileName, time: duration * 0.3)
    }
}
