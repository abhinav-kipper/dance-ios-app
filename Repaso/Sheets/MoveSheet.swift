import SwiftUI
import SwiftData
import RepasoCore

/// What Move is for: a folder (clips use Folders…).
enum MoveSubject: Identifiable {
    case folder(Folder)

    var id: UUID {
        switch self {
        case .folder(let f): f.id
        }
    }

    var title: String { "Move folder" }

    /// Label for the top row (no parent).
    var rootLabel: String { "Home" }

    /// A new folder may go inside `folder` (a folder can't be created inside the one being moved).
    func canContain(_ folder: Folder?) -> Bool {
        guard let folder else { return false }
        if case .folder(let moving) = self { return folder.id != moving.id && !folder.isDescendant(of: moving) }
        return true
    }

    var currentFolder: Folder? {
        switch self {
        case .folder(let f): f.parent
        }
    }
}

/// Folder tree picker: 22pt indent per level, current location disabled, success state, then a toast with Undo.
struct MoveSheet: View {
    let subject: MoveSubject
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.sortIndex) private var roots: [Folder]
    @State private var selection: Target?
    @State private var expanded: Set<UUID> = []
    @State private var movedTo: String?

    private enum Target: Hashable {
        case root
        case folder(UUID)
    }

    private struct Row: Identifiable {
        let folder: Folder
        let depth: Int
        var id: UUID { folder.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let movedTo {
                success(movedTo)
            } else {
                Text(subject.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 28)
                ScrollView {
                    VStack(spacing: 2) {
                        NewFolderRow(suggestedParent: subject.canContain(targetFolder) ? targetFolder : nil) { created in
                            withAnimation(Theme.spring) {
                                created.ancestors.forEach { expanded.insert($0.id) }
                                selection = .folder(created.id)
                            }
                        }
                        rootRow
                        ForEach(rows) { row in folderRow(row) }
                    }
                }
                PrimarySheetButton(title: buttonTitle, isEnabled: selection != nil, action: move)
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet()
        .onAppear { expanded = Set(roots.map(\.id)) }
    }

    // MARK: Tree

    private var rows: [Row] {
        var out: [Row] = []
        func walk(_ folders: [Folder], depth: Int) {
            for f in folders {
                out.append(Row(folder: f, depth: depth))
                if expanded.contains(f.id) { walk(FolderContents.subfolders(of: f), depth: depth + 1) }
            }
        }
        walk(roots, depth: 0)
        return out
    }

    private var rootRow: some View {
        let isCurrent = subject.currentFolder == nil
        return rowButton(target: .root, icon: subject.rootLabel == "Home" ? "house" : "tray",
                         name: subject.rootLabel, depth: 0, hasChildren: false, folderID: nil,
                         isCurrent: isCurrent, isDisabled: isCurrent)
    }

    private func folderRow(_ row: Row) -> some View {
        let f = row.folder
        let isCurrent = subject.currentFolder?.id == f.id
        var disabled = isCurrent
        if case .folder(let moving) = subject, moving.id == f.id || f.isDescendant(of: moving) { disabled = true }
        return rowButton(target: .folder(f.id), icon: "folder", name: f.name, depth: row.depth + 1,
                         hasChildren: !f.children.isEmpty, folderID: f.id, isCurrent: isCurrent, isDisabled: disabled)
    }

    private func rowButton(target: Target, icon: String, name: String, depth: Int, hasChildren: Bool,
                           folderID: UUID?, isCurrent: Bool, isDisabled: Bool) -> some View {
        let selected = selection == target
        return HStack(spacing: 10) {
            if hasChildren, let folderID {
                Button {
                    withAnimation(Theme.spring) {
                        if expanded.contains(folderID) { expanded.remove(folderID) } else { expanded.insert(folderID) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(expanded.contains(folderID) ? 90 : 0))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded.contains(folderID) ? "Collapse \(name)" : "Expand \(name)")
            } else {
                Color.clear.frame(width: 28, height: 44)
            }
            Button {
                selection = target
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "\(icon).fill" : icon)
                        .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                    Text(name)
                        .font(.system(size: 15, weight: selected ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if isCurrent {
                        Text("Current").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    } else if selected {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled && !isCurrent ? 0.35 : 1)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.leading, CGFloat(max(0, depth - 1)) * 22)
        .padding(.horizontal, 8)
        .background(selected ? Theme.accentTint : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Moving

    private var targetFolder: Folder? {
        guard case .folder(let id) = selection else { return nil }
        return findFolder(id)
    }

    private var targetName: String {
        selection == .root ? subject.rootLabel : (targetFolder?.name ?? "")
    }

    private var buttonTitle: String {
        selection == nil ? "Choose a folder" : "Move to \(targetName)"
    }

    private func findFolder(_ id: UUID) -> Folder? {
        try? ctx.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })).first
    }

    private func move() {
        let destination = targetFolder
        let previous = subject.currentFolder
        let name = targetName
        let lib = env.library(ctx)
        do {
            try apply(lib, to: destination)
        } catch {
            env.showToast(error as? LibraryError == .invalidMoveTarget ? "Can't move a folder into itself" : "Couldn't save",
                          seconds: 2.2)
            return
        }
        withAnimation(Theme.spring) { movedTo = name }
        let subject = subject
        let env = env
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
            env.showToast("Moved to \(name)") {
                env.perform { try Self.apply(subject, lib, to: previous) }
            }
        }
    }

    private func apply(_ lib: LibraryService, to folder: Folder?) throws {
        try Self.apply(subject, lib, to: folder)
    }

    private static func apply(_ subject: MoveSubject, _ lib: LibraryService, to folder: Folder?) throws {
        switch subject {
        case .folder(let f): try lib.moveFolder(f, to: folder)
        }
    }

    private func success(_ name: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: movedTo)
            Text("Moved to \(name)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
