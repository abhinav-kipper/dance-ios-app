import SwiftUI
import SwiftData
import RepasoCore

/// What "Add to folders…" is for: a clip or a whole video.
enum LinkSubject: Identifiable {
    case clip(Clip)
    case original(Original)

    var id: UUID {
        switch self {
        case .clip(let c): c.id
        case .original(let o): o.id
        }
    }

    var title: String {
        switch self {
        case .clip: "Add clip to folders"
        case .original: "Add video to folders"
        }
    }

    /// Where it lives; shown checked and fixed.
    var home: Folder? {
        switch self {
        case .clip(let c): c.effectiveFolder
        case .original(let o): o.folder
        }
    }

    var linked: [Folder] {
        switch self {
        case .clip(let c): c.linkedFolders
        case .original(let o): o.linkedFolders
        }
    }
}

/// Folder tree with checkboxes: the item also shows in every ticked folder (like adding a song to playlists).
struct LinkSheet: View {
    let subject: LinkSubject
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.sortIndex) private var roots: [Folder]
    @State private var selected: Set<UUID> = []
    @State private var expanded: Set<UUID> = []

    private struct Row: Identifiable {
        let folder: Folder
        let depth: Int
        var id: UUID { folder.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("It stays in its home folder and also shows in the ones you tick.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 28)
            if roots.isEmpty {
                Text("Make a folder on Home first.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(rows) { row in folderRow(row) }
                }
            }
            PrimarySheetButton(title: "Save", action: save)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet()
        .onAppear {
            selected = Set(subject.linked.map(\.id))
            expanded = Set(roots.map(\.id))
            // Open the path down to every ticked folder and the home.
            for folder in subject.linked + [subject.home].compactMap({ $0 }) {
                folder.ancestors.forEach { expanded.insert($0.id) }
            }
        }
    }

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

    private func folderRow(_ row: Row) -> some View {
        let f = row.folder
        let isHome = subject.home?.id == f.id
        let ticked = isHome || selected.contains(f.id)
        return HStack(spacing: 10) {
            if !f.children.isEmpty {
                Button {
                    withAnimation(Theme.spring) {
                        if expanded.contains(f.id) { expanded.remove(f.id) } else { expanded.insert(f.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(expanded.contains(f.id) ? 90 : 0))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded.contains(f.id) ? "Collapse \(f.name)" : "Expand \(f.name)")
            } else {
                Color.clear.frame(width: 28, height: 44)
            }
            Button {
                if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(ticked ? Theme.accent : Theme.textSecondary)
                    Text(f.name)
                        .font(.system(size: 15, weight: ticked ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if isHome {
                        Text("Home").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isHome)
            .accessibilityLabel(f.name)
            .accessibilityValue(isHome ? "Home folder" : (ticked ? "Added" : "Not added"))
        }
        .padding(.leading, CGFloat(row.depth) * 22)
        .padding(.horizontal, 8)
    }

    private func save() {
        let folders = try? ctx.fetch(FetchDescriptor<Folder>())
        let chosen = (folders ?? []).filter { selected.contains($0.id) }
        let before = subject.linked
        let lib = env.library(ctx)
        env.perform {
            switch subject {
            case .clip(let c): try lib.setLinks(c, to: chosen)
            case .original(let o): try lib.setLinks(o, to: chosen)
            }
        }
        dismiss()
        let count = subject.linked.count
        guard count != before.count || Set(before.map(\.id)) != Set(subject.linked.map(\.id)) else { return }
        let subject = subject
        let env = env
        env.showToast(count == 0 ? "Only in its home folder" : (count == 1 ? "Also in 1 folder" : "Also in \(count) folders")) {
            env.perform {
                switch subject {
                case .clip(let c): try lib.setLinks(c, to: before)
                case .original(let o): try lib.setLinks(o, to: before)
                }
            }
        }
    }
}

/// Small 🔗 badge for a video or clip that shows in this folder through a link.
struct LinkBadge: View {
    let home: String

    var body: some View {
        Label("Linked", systemImage: "link")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.accentTint, in: Capsule())
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Linked here; home is \(home)")
    }
}
