import SwiftUI
import RepasoCore

/// Opens the Player on `items[index]`.
/// Opens the cutter on a video; with `focusClipID`, that clip starts selected (Trim…).
struct CutRequest: Identifiable {
    let id = UUID()
    let original: Original
    var focusClipID: UUID?
}

struct PlayerRequest: Identifiable {
    let id = UUID()
    let items: [PlaybackItem]
    let index: Int
    let title: String

    init(items: [PlaybackItem], index: Int, title: String) {
        self.items = items
        self.index = index
        self.title = title
    }

    init(queue: [Clip], index: Int, title: String) {
        self.init(items: queue.map(PlaybackItem.clip), index: index, title: title)
    }
}

/// Every sheet a library screen can present.
enum LibrarySheet: Identifiable {
    case move(MoveSubject)
    case info(Clip)
    case videoInfo(Original)
    case deleteOriginal(Original)
    case deleteFolder(Folder)
    case share(Clip)
    case link(LinkSubject)

    var id: String {
        switch self {
        case .move(let s): "move-\(s.id)"
        case .info(let c): "info-\(c.id)"
        case .videoInfo(let o): "vinfo-\(o.id)"
        case .deleteOriginal(let o): "delo-\(o.id)"
        case .deleteFolder(let f): "delf-\(f.id)"
        case .share(let c): "share-\(c.id)"
        case .link(let s): "link-\(s.id)"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .move(let subject): MoveSheet(subject: subject)
        case .info(let clip): ClipInfoSheet(clip: clip)
        case .videoInfo(let original): VideoInfoSheet(original: original)
        case .deleteOriginal(let original): DeleteOriginalSheet(original: original)
        case .deleteFolder(let folder): DeleteFolderSheet(folder: folder)
        case .share(let clip): ShareSheet(clip: clip)
        case .link(let subject): LinkSheet(subject: subject)
        }
    }
}

/// Lists rise 14pt and fade in, staggered 45ms per row (fade only under Reduce Motion).
struct RiseIn: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring.delay(Double(min(index, 12)) * 0.045)) {
                    shown = true
                }
            }
    }
}

extension View {
    func riseIn(_ index: Int) -> some View { modifier(RiseIn(index: index)) }
}

/// Glass chip used for Sort and Hide learned.
struct Chip: View {
    let title: String
    let systemImage: String
    var isOn = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isOn ? Theme.accent : .clear, in: Capsule())
            .controlGlass(in: Capsule())
            .frame(minHeight: 44)
    }
}
