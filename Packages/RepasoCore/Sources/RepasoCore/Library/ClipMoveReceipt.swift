/// What a drag-drop changed, so the toast's Undo can put it back.
@MainActor
public struct ClipMoveReceipt {
    public let clip: Clip
    /// nil only for a clip that had no folder yet.
    public let previousFolder: Folder?
    public let destination: Folder
}
