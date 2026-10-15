import SwiftUI
import SwiftData
import PhotosUI
import RepasoCore

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(filter: #Predicate<Original> { $0.folder == nil }) private var unsorted: [Original]
    @Query(filter: #Predicate<Clip> { $0.isFavorite }) private var favorites: [Clip]
    @Query private var allClips: [Clip]
    @Query private var allFolders: [Folder]
    @State private var path: [Route] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var showImport = false
    @State private var editingFolderID: UUID?
    @State private var deletingFolder: Folder?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if folders.isEmpty && unsorted.isEmpty {
                        emptyState
                    } else {
                        pinnedTiles
                        if !folders.isEmpty {
                            Text("Folders").sectionLabelStyle()
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(folders) { folder in
                                    folderCell(folder)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 12)
                .padding(.bottom, 140)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                FloatingPill(title: "Import videos", systemImage: "square.and.arrow.down") { showPicker = true }
            }
            .photosPicker(isPresented: $showPicker, selection: $picks, matching: .videos, preferredItemEncoding: .current)
            .onChange(of: picks) { _, new in
                guard !new.isEmpty else { return }
                env.importer.start(new, into: nil, context: ctx, env: env)
                picks = []
                showImport = true
            }
            .sheet(isPresented: $showImport) { ImportSheet() }
            .sheet(item: $deletingFolder) { DeleteFolderSheet(folder: $0) }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .folder(let id): FolderView(folderID: id, path: $path)
                case .unsorted: FolderView(folderID: nil, path: $path)
                case .favorites: FavoritesView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toastHost(env)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repaso")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: newFolder) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .controlGlass(in: Circle())
            .accessibilityLabel("New folder")
            .padding(.top, 6)
        }
    }

    private var subtitle: String {
        let clips = allClips.count == 1 ? "1 clip" : "\(allClips.count) clips"
        let foldersText = allFolders.count == 1 ? "1 folder" : "\(allFolders.count) folders"
        return "\(clips) in \(foldersText)"
    }

    private var pinnedTiles: some View {
        HStack(spacing: 14) {
            if !unsorted.isEmpty {
                NavigationLink(value: Route.unsorted) {
                    tile(icon: "tray", iconColor: Theme.textPrimary, title: "Unsorted",
                         detail: "\(unsorted.count) new", dot: true)
                }
                .buttonStyle(PressableButtonStyle())
            }
            NavigationLink(value: Route.favorites) {
                tile(icon: "star.fill", iconColor: Theme.rose, title: "Favorites",
                     detail: favorites.count == 1 ? "1 clip" : "\(favorites.count) clips", dot: false)
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private func tile(icon: String, iconColor: Color, title: String, detail: String, dot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                Spacer()
                if dot {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.listCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func folderCell(_ folder: Folder) -> some View {
        let editing = Binding(
            get: { editingFolderID == folder.id },
            set: { if !$0 { editingFolderID = nil } })
        // Not wrapped in a link while editing: a disabled link would disable the name field too.
        Group {
            if editingFolderID == folder.id {
                FolderCard(folder: folder, isEditingName: editing)
            } else {
                NavigationLink(value: Route.folder(folder.id)) {
                    FolderCard(folder: folder, isEditingName: editing)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { editingFolderID = folder.id }
            Button("Move up", systemImage: "arrow.up") {
                env.perform { try env.library(ctx).reorderFolder(folder, by: -1) }
            }
            Button("Move down", systemImage: "arrow.down") {
                env.perform { try env.library(ctx).reorderFolder(folder, by: 1) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(folder) }
        }
        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("Import your first class video")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pick videos from Photos, cut the moves you want to practice, and file them in folders.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardGlass(radius: Theme.Radius.folderCard)
        .padding(.top, 40)
    }

    // MARK: Actions

    private func newFolder() {
        env.perform {
            var created: Folder?
            try withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring) {
                created = try env.library(ctx).createFolder(named: "", in: nil)
            }
            editingFolderID = created?.id
        }
    }

    private func requestDelete(_ folder: Folder) {
        if folder.children.isEmpty && folder.originals.isEmpty && folder.looseClips.isEmpty {
            env.perform { try env.library(ctx).deleteFolder(folder, mode: .deleteContents) }
        } else {
            deletingFolder = folder
        }
    }
}
