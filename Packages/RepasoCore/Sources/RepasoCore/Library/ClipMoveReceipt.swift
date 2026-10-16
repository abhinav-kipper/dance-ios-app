/// What a drag-drop changed, so the toast's Undo can put it back.
@MainActor
public struct ClipMoveReceipt {
    public let clip: Clip
    /// nil = the clip lived with its video.
    public let previousFolder: Folder?
    public let destination: Folder
}
