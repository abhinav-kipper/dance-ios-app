import Foundation

/// What a muted live preview loops: a short range of an original's file.
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
        guard let original else { return nil }
        return PreviewSource(id: id, fileName: original.fileName, range: start...min(end, start + PreviewSource.length))
    }
}

extension Original {
    public var previewSource: PreviewSource {
        let start = duration * 0.3
        return PreviewSource(id: id, fileName: fileName, range: start...min(duration, start + PreviewSource.length))
    }
}
