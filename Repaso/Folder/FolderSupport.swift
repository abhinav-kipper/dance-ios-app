import SwiftUI
import RepasoCore

/// Opens the cutter on a clip's recording with that clip selected (Trim…).
struct CutRequest: Identifiable {
    let id = UUID()
    let recording: Recording
    var focusClipID: UUID?
}

/// Opens the Player on `items[index]`; swiping moves through `items`.
struct PlayerRequest: Identifiable {
    let id = UUID()
    let items: [Clip]
    let index: Int
    let title: String

    init(queue: [Clip], index: Int, title: String) {
        self.items = queue
        self.index = index
        self.title = title
    }
}

/// Every sheet a library screen can present.
enum LibrarySheet: Identifiable {
    case move(MoveSubject)
    case info(Clip)
    case deleteFolder(Folder)
    case share(Clip)
    case link(Clip)

    var id: String {
        switch self {
        case .move(let s): "move-\(s.id)"
        case .info(let c): "info-\(c.id)"
        case .deleteFolder(let f): "delf-\(f.id)"
        case .share(let c): "share-\(c.id)"
        case .link(let c): "link-\(c.id)"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .move(let subject): MoveSheet(subject: subject)
        case .info(let clip): ClipInfoSheet(clip: clip)
        case .deleteFolder(let folder): DeleteFolderSheet(folder: folder)
        case .share(let clip): ShareSheet(clip: clip)
        case .link(let clip): LinkSheet(clip: clip)
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
