public enum ClipSort: String, CaseIterable, Sendable {
    case manual, name, dateAdded, recentlyPlayed

    public var title: String {
        switch self {
        case .manual: "Manual"
        case .name: "Name"
        case .dateAdded: "Date added"
        case .recentlyPlayed: "Recently played"
        }
    }
}
