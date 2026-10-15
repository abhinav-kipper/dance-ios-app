import Foundation
import os

/// Video files in Documents/Videos, named `<uuid>.<ext>`.
public struct VideoStore: Sendable {
    public let directory: URL
    private static let log = Logger(subsystem: "com.amudgal.repaso", category: "videos")

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func appDefault() throws -> VideoStore {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return VideoStore(directory: docs.appendingPathComponent("Videos", isDirectory: true))
    }

    public func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    /// Moves (or copies, if moving fails) `source` into the store under a fresh UUID name.
    public func adopt(fileAt source: URL) throws -> String {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        let dest = url(for: name)
        do {
            try FileManager.default.moveItem(at: source, to: dest)
        } catch {
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return name
    }

    public func remove(fileName: String) {
        do {
            try FileManager.default.removeItem(at: url(for: fileName))
        } catch {
            Self.log.error("remove \(fileName) failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func sweepOrphans(keeping referenced: Set<String>) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let orphans = names.filter { !referenced.contains($0) && !$0.hasPrefix(".") }.sorted()
        orphans.forEach(remove(fileName:))
        return orphans
    }

    public func fileSize(_ fileName: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url(for: fileName).path)[.size] as? NSNumber)?.int64Value
    }
}
