import Foundation
import os

/// Videos handed over by the Share extension, waiting in the App Group container for the app to import them.
/// The extension writes each copy under a hidden `.partial-` name and renames it when complete, so the app never
/// picks up a half-written file. Names start with the share time, so draining keeps share order.
public struct ShareInbox: Sendable {
    public static let appGroupID = "group.com.amudgal.repaso"
    /// Opened by the extension once the videos are in the inbox.
    public static let openURL = URL(string: "repaso://inbox")!

    public let directory: URL
    private static let log = Logger(subsystem: "com.amudgal.repaso", category: "share-inbox")

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The inbox in the shared App Group container (nil if the entitlement is missing).
    public static func appGroup() -> ShareInbox? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            .map { ShareInbox(directory: $0.appendingPathComponent("Inbox", isDirectory: true)) }
    }

    /// Copies `source` into the inbox; the source stays (the sharing app owns it).
    @discardableResult
    public func deposit(fileAt source: URL) throws -> URL {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let stamp = String(format: "%020llu", clock_gettime_nsec_np(CLOCK_REALTIME))
        let name = "\(stamp)-\(UUID().uuidString).\(ext)"
        let partial = directory.appendingPathComponent(".partial-\(name)")
        let final = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: partial)
        try FileManager.default.moveItem(at: partial, to: final)
        return final
    }

    /// Moves every finished video into `destination`, oldest share first, and returns their new URLs.
    public func drain(into destination: URL) -> [URL] {
        let fm = FileManager.default
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let names = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        return names.compactMap { name in
            let dest = destination.appendingPathComponent(name)
            do {
                try fm.moveItem(at: directory.appendingPathComponent(name), to: dest)
                return dest
            } catch {
                Self.log.error("drain \(name) failed: \(error.localizedDescription)")
                return nil
            }
        }
    }
}
