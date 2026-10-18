import Foundation

public enum PhotosCleanupText {
    public static func prompt(count: Int) -> String {
        count == 1 ? "Delete this video from Photos?" : "Delete \(count) videos from Photos?"
    }
    public static let detail = "They'll also leave iCloud Photos, so Repaso will have the only copy."
    public static let removed = "Removed from Photos"
    public static let kept = "Kept in Photos"
    public static let failed = "Couldn't remove from Photos"
    public static let needsAccess = "Allow full Photos access in Settings to delete"
}
