import SwiftUI
import SwiftData
import RepasoCore

/// Searches the whole library: clips and folders, by name, note, teacher and folder.
struct SearchView: View {
    @Binding var path: [Route]
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var allClips: [Clip]
    @Query private var allFolders: [Folder]
    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    @State private var sheet: LibrarySheet?
    @State private var player: PlayerRequest?
    @State private var deletingClip: Clip?
    @State private var cutting: CutRequest?

    private var results: LibrarySearch.Results {
        LibrarySearch.results(for: query, clips: allClips, folders: allFolders)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                backButton
                searchField
                resultsContent(results)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 60)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { fieldFocused = true }
        .sheet(item: $sheet) { $0.content }
        .fullScreenCover(item: $player) { PlayerView(request: $0) }
        .fullScreenCover(item: $cutting) { CutView(recording: $0.recording, focusClipID: $0.focusClipID) }
        .clipDeleteDialog($deletingClip)
        .toastHost(env)
    }

    @ViewBuilder
    private func resultsContent(_ results: LibrarySearch.Results) -> some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyView()
        } else if results.isEmpty {
            hint("No results")
        } else {
            if !results.clips.isEmpty { clipSection(results.clips) }
            if !results.folders.isEmpty { folderSection(results.folders) }
        }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                Text("Home").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.rose)
            .frame(minHeight: 44)
            .contentShape([.interaction, .accessibility], Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to Home")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Search", text: $query)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textPrimary)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("search-field")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .controlGlass(in: Capsule())
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 8)
    }

    // MARK: Sections

    private func clipSection(_ clips: [Clip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clips").sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(clips) { clip in
                    ClipRow(clip: clip, actions: actions(queue: clips))
                        .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 4)
            .cardGlass(radius: Theme.Radius.listCard)
        }
    }

    private func folderSection(_ folders: [Folder]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders").sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(folders) { folder in
                    Button { open(folder) } label: { folderRow(folder) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(folder.name)")
                }
            }
            .padding(.vertical, 4)
            .cardGlass(radius: Theme.Radius.listCard)
        }
    }

    private func folderRow(_ folder: Folder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.rose)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !folder.ancestors.isEmpty {
                    Text(folder.ancestors.map(\.name).joined(separator: " › "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    // MARK: Actions

    /// Opens the folder on top of the search, so Back returns to the results.
    private func open(_ folder: Folder) {
        path.append(contentsOf: (folder.ancestors + [folder]).map { Route.folder($0.id) })
    }

    private func actions(queue: [Clip]) -> ClipActions {
        ClipActions(
            play: { clip in
                player = PlayerRequest(queue: queue, index: queue.firstIndex { $0.id == clip.id } ?? 0, title: "Search")
            },
            info: { sheet = .info($0) },
            delete: { deletingClip = $0 },
            share: { sheet = .share($0) },
            link: { sheet = .link($0) },
            trim: { clip in
                guard let recording = clip.recording else { return }
                cutting = CutRequest(recording: recording, focusClipID: clip.id)
            })
    }
}
