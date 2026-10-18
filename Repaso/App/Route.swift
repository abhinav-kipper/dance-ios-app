import Foundation

enum Route: Hashable {
    case folder(UUID)
    case unsorted
    case favorites
    case search
    case videos
}
