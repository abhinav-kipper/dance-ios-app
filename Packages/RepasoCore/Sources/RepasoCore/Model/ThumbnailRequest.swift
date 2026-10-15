import Foundation

public struct ThumbnailRequest: Hashable, Sendable {
    public let id: UUID
    public let fileName: String
    public let time: Double

    public init(id: UUID, fileName: String, time: Double) {
        self.id = id
        self.fileName = fileName
        self.time = time
    }
}
