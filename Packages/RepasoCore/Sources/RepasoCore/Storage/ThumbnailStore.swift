import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Poster frames: memory cache → JPEG in Caches → generated from the video on a miss.
public actor ThumbnailStore {
    private let directory: URL
    private let videos: VideoStore
    private let memory = NSCache<NSUUID, CGImageBox>()

    public init(directory: URL, videos: VideoStore) {
        self.directory = directory
        self.videos = videos
        memory.countLimit = 300
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func appDefault(videos: VideoStore) throws -> ThumbnailStore {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ThumbnailStore(directory: caches.appendingPathComponent("Thumbnails", isDirectory: true), videos: videos)
    }

    public func image(for request: ThumbnailRequest, maxPixel: Int = 400) async -> CGImage? {
        if let hit = memory.object(forKey: request.id as NSUUID) { return hit.image }
        let file = fileURL(request.id)
        if let image = Self.decode(file) {
            memory.setObject(CGImageBox(image), forKey: request.id as NSUUID)
            return image
        }
        let video = videos.url(for: request.fileName)
        guard FileManager.default.fileExists(atPath: video.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: request.time, preferredTimescale: 600)) else {
            return nil
        }
        Self.writeJPEG(image, to: file)
        memory.setObject(CGImageBox(image), forKey: request.id as NSUUID)
        return image
    }

    public func remove(ids: [UUID]) {
        for id in ids {
            memory.removeObject(forKey: id as NSUUID)
            try? FileManager.default.removeItem(at: fileURL(id))
        }
    }

    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id).jpg") }

    private static func decode(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

/// Immutable wrapper so CGImages can live in NSCache.
final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
