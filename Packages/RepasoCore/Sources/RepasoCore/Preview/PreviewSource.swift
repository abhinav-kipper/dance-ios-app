import Foundation

/// What a muted live preview loops: a short range of a recording's file.
public struct PreviewSource: Hashable, Sendable {
    public static let length = 3.0
    public let id: UUID
    public let fileName: String
    public let range: ClosedRange<Double>

    public init(id: UUID, fileName: String, range: ClosedRange<Double>) {
        self.id = id
        self.fileName = fileName
        self.range = range
    }
}

extension Clip {
    public var previewSource: PreviewSource? {
        guard let recording else { return nil }
        return PreviewSource(id: id, fileName: recording.fileName, range: start...min(end, start + PreviewSource.length))
    }
}
