public enum LibraryError: Error, Equatable {
    case invalidMoveTarget
    /// A clip needs a name.
    case emptyName
    /// Finish needs a folder for every clip.
    case missingFolder
    /// Only a recording still in the guide or Unsorted can be finished or deleted that way.
    case notPending
    /// An own-file export named a clip that isn't on that recording.
    case unknownClip
}
