import SwiftUI
import SwiftData
import RepasoCore

/// "Folders…": a folder tree with checkboxes, ticked wherever the clip shows. One place for moving it and for showing
/// it in more folders (like a song in playlists): it lives in the first ticked folder and also appears in the rest.
struct LinkSheet: View {
    let clip: Clip
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
                Text("Folders")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Tick every folder this clip should show in.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 28)
            ScrollView {
                VStack(spacing: 2) {
                    NewFolderRow { created in
                        withAnimation(Theme.spring) { _ = selected.insert(created.id) }
                    }
                    ForEach(rows) { row in folderRow(row) }
                }
            }
            PrimarySheetButton(title: "Save", action: save)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet()
        .onAppear {
            selected = Set((clip.linkedFolders + [clip.folder].compactMap { $0 }).map(\.id))
            expanded = Set(roots.map(\.id))
            // Open the path down to every ticked folder and the home.
            for folder in clip.linkedFolders + [clip.folder].compactMap({ $0 }) {
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
        let ticked = selected.contains(f.id)
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
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(f.name)
            .accessibilityValue(ticked ? "Shown here" : "Not here")
        }
        .padding(.leading, CGFloat(row.depth) * 22)
        .padding(.horizontal, 8)
    }

    private func save() {
        let all = (try? ctx.fetch(FetchDescriptor<Folder>())) ?? []
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Tree order, so "the first ticked folder" is the one highest in the list.
        let chosen = rows.map(\.folder).filter { selected.contains($0.id) }
            + selected.subtracting(rows.map(\.folder.id)).compactMap { byID[$0] }
        let before = (clip.folder.map { [$0] } ?? []) + clip.linkedFolders
        let beforeIDs = Set(before.map(\.id))
        dismiss()
        guard Set(chosen.map(\.id)) != beforeIDs else { return }
        let lib = env.library(ctx)
        let clip = clip
        env.perform { try lib.place(clip, in: chosen) }
        let env = env
        env.showToast(Self.summary(clip)) {
            env.perform { try lib.place(clip, in: before) }
        }
    }

    /// "In Turns" or "In Turns and 2 more". With nothing ticked a clip stays where it lives.
    private static func summary(_ clip: Clip) -> String {
        let home = clip.folder?.name ?? ""
        let others = clip.linkedFolders.count
        return others > 0 ? "In \(home) and \(others) more" : "In \(home)"
    }
}

/// Small 🔗 badge for a clip that shows in this folder through a link.
struct LinkBadge: View {
    let home: String

    var body: some View {
        Label("Linked", systemImage: "link")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.rose)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.roseTint, in: Capsule())
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Linked here; home is \(home)")
    }
}
