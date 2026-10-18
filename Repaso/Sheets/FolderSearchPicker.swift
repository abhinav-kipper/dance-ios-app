import SwiftUI
import SwiftData
import RepasoCore

/// Picks one folder: search by name (matches show their path), or make one. When nothing matches, the first row
/// creates a folder with the typed name on Home.
struct FolderSearchPicker: View {
    let selected: Folder?
    let onPick: (Folder) -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]
    @State private var query = ""
    @FocusState private var searching: Bool

    private struct Row: Identifiable {
        let folder: Folder
        let path: String
        var id: UUID { folder.id }
    }

    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Every folder in tree order, or the ones whose name matches the search.
    private var rows: [Row] {
        func path(_ f: Folder) -> String { (f.ancestors.map(\.name) + [f.name]).joined(separator: " › ") }
        let all = folders.map { Row(folder: $0, path: path($0)) }
        guard !cleanQuery.isEmpty else {
            return all.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        let q = cleanQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return all.filter { $0.folder.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
            .sorted { $0.folder.name.count < $1.folder.name.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a folder")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 28)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search folders", text: $query)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($searching)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if let first = rows.first { pick(first.folder) } else { createFromQuery() } }
                    .accessibilityIdentifier("folderSearch")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .controlGlass(in: Capsule())
            ScrollView {
                VStack(spacing: 2) {
                    if !cleanQuery.isEmpty && !rows.contains(where: { $0.folder.name.caseInsensitiveCompare(cleanQuery) == .orderedSame }) {
                        Button(action: createFromQuery) {
                            Label("Create “\(cleanQuery)”", systemImage: "folder.badge.plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.rose)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if cleanQuery.isEmpty {
                        NewFolderRow(suggestedParent: selected) { pick($0) }
                    }
                    ForEach(rows) { row in folderRow(row) }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet(detents: [.large])
    }

    private func folderRow(_ row: Row) -> some View {
        let isSelected = row.folder.id == selected?.id
        return Button { pick(row.folder) } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "folder")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.rose)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.folder.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if !row.folder.ancestors.isEmpty {
                        Text(row.path)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.path)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pick(_ folder: Folder) {
        onPick(folder)
        dismiss()
    }

    private func createFromQuery() {
        guard !cleanQuery.isEmpty else { return }
        env.perform { pick(try env.library(ctx).createFolder(named: cleanQuery, in: nil)) }
    }
}
