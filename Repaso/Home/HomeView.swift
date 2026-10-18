import SwiftUI
import SwiftData
import PhotosUI
import RepasoCore

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(filter: #Predicate<Recording> { $0.isPending }) private var pending: [Recording]
    @Query(filter: #Predicate<Clip> { $0.isFavorite }) private var favorites: [Clip]
    @Query private var allFolders: [Folder]
    @State private var path: [Route] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var editingFolderID: UUID?
    @State private var deletingFolder: Folder?
    /// Card order while a folder is being dragged; committed when the drag ends.
    @State private var liveOrder: [UUID]?
    @State private var settleCounts: [UUID: Int] = [:]
    @State private var showGuide = false
    /// Arrange mode: press-and-hold drags folders to reorder them instead of opening their menu.
    @State private var arranging = false
    /// The how-to guide opens by itself once, on first launch (never during UI tests).
    @AppStorage("guideSeen") private var guideSeen = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                libraryContent
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 12)
                .padding(.bottom, 140)
            }
            .scrollDismissesKeyboard(.interactively)
            .dragTarget(env.drag) { $0.kind == .folder }   // catcher: dropping between cards keeps the live order
            .background(Theme.bg.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                FloatingPill(title: "Import videos", systemImage: "square.and.arrow.down") { showPicker = true }
            }
            .photosPicker(isPresented: $showPicker, selection: $picks, matching: .importableVideos,
                         preferredItemEncoding: .current, photoLibrary: .shared())
            .onChange(of: picks) { _, new in
                guard !new.isEmpty else { return }
                env.startImport(new, from: nil, context: ctx)
                picks = []
            }
            .sheet(item: $deletingFolder) { DeleteFolderSheet(folder: $0) }
            .fullScreenCover(isPresented: $showGuide) { GuideView() }
            .fullScreenCover(item: Binding(get: { env.guide }, set: { env.guide = $0 })) { ImportGuideView(model: $0) }
            .onAppear {
                guard !guideSeen, !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
                guideSeen = true
                showGuide = true
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .folder(let id): FolderView(folderID: id, path: $path)
                case .unsorted: UnsortedView()
                case .favorites: FavoritesView()
                case .search: SearchView(path: $path)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toastHost(env)
            .onChange(of: reduceMotion, initial: true) { _, on in env.previews.setReduceMotion(on) }
            .onChange(of: env.pendingRoute) { _, route in
                guard let route else { return }
                path = route
                env.pendingRoute = nil
            }
            .onChange(of: env.drag.active) { old, new in
                if new?.kind == .folder, liveOrder == nil { liveOrder = folders.map(\.id) }
                if new == nil, let old, old.kind == .folder { commitOrder(placed: old.id) }
            }
        }
    }

    private var draggingFolderID: UUID? {
        env.drag.active?.kind == .folder ? env.drag.active?.id : nil
    }

    private var displayedFolders: [Folder] {
        guard let liveOrder else { return folders }
        let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return liveOrder.compactMap { byID[$0] } + folders.filter { !liveOrder.contains($0.id) }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repaso")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(Theme.textPrimary)
                if draggingFolderID != nil || arranging {
                    Text(draggingFolderID != nil ? "Drop to place" : "Hold a folder, then drag it")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .transition(.opacity)
                }
            }
            Spacer()
            if arranging {
                Button {
                    withAnimation(Theme.spring) { arranging = false }
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(Theme.rose, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Done arranging")
                .padding(.top, 6)
            } else {
            Button { showGuide = true } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .controlGlass(in: Circle())
            .accessibilityLabel("How to use Repaso")
            .padding(.top, 6)
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
    }


    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if folders.isEmpty && pending.isEmpty {
                emptyState
            } else {
                searchPill
                pinnedTiles
                if !folders.isEmpty { folderGrid }
            }
        }
    }

    private var folderGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Folders").sectionLabelStyle()
                Spacer()
                if folders.count > 1 && !arranging {
                    Button {
                        withAnimation(Theme.spring) { arranging = true }
                    } label: {
                        Label("Arrange", systemImage: "hand.draw")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.rose)
                            .frame(minHeight: 44)
                            .contentShape([.interaction, .accessibility], Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Arrange folders")
                    .transition(.opacity)
                }
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(displayedFolders) { folder in
                    folderCell(folder)
                }
            }
        }
    }

    /// Opens the search screen.
    private var searchPill: some View {
        Button { path.append(.search) } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                Text("Search clips, teachers, folders")
                Spacer(minLength: 0)
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .controlGlass(in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Search")
    }

    private var pinnedTiles: some View {
        HStack(spacing: 14) {
            if !pending.isEmpty {
                NavigationLink(value: Route.unsorted) {
                    tile(icon: "tray", iconColor: Theme.rose, title: "Unsorted · \(pending.count)",
                         detail: pending.count == 1 ? "1 video to go through" : "\(pending.count) to go through", dot: true)
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
                    Circle().fill(Theme.rose).frame(width: 8, height: 8)
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
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.listCard, style: .continuous))   // the whole tile taps
        .controlGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.listCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func folderCell(_ folder: Folder) -> some View {
        let editing = Binding(
            get: { editingFolderID == folder.id },
            set: { if !$0 { editingFolderID = nil } })
        let isPlaceholder = draggingFolderID == folder.id
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
        .opacity(isPlaceholder ? 0 : 1)
        .overlay {
            if isPlaceholder {
                RoundedRectangle(cornerRadius: Theme.Radius.folderCard, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: settleCounts[folder.id, default: 0]) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(1.08)   // instant jump; a zero-length segment gives the next spring a NaN velocity
                CubicKeyframe(0.96, duration: 0.29)
                CubicKeyframe(1, duration: 0.36)
            }
        }
        .jiggle((arranging || draggingFolderID != nil) && !isPlaceholder)
        .dragSource(DragRef(kind: .folder, id: folder.id), drag: env.drag, origin: nil, enabled: arranging) {
            FolderLiftPreview(name: folder.name, clipCount: FolderContents.clipCount(in: folder), reduceMotion: reduceMotion)
        }
        .dragTarget(env.drag, isTargeted: { if $0 { reorder(onto: folder.id) } }) { $0.kind == .folder }
        .modifier(MenuUnlessArranging(isArranging: arranging) {
            Button("Rename", systemImage: "pencil") { editingFolderID = folder.id }
            Button("Arrange folders", systemImage: "hand.draw") { withAnimation(Theme.spring) { arranging = true } }
            Button("Move up", systemImage: "arrow.up") {
                env.perform { try env.library(ctx).reorderFolder(folder, by: -1) }
            }
            Button("Move down", systemImage: "arrow.down") {
                env.perform { try env.library(ctx).reorderFolder(folder, by: 1) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(folder) }
        })
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

    /// Live reorder: the dragged card takes the hovered card's slot.
    private func reorder(onto id: UUID) {
        guard let dragged = draggingFolderID, dragged != id else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring) {
            liveOrder = FolderOrder.moving(dragged, onto: id, in: liveOrder ?? folders.map(\.id))
        }
    }

    private func commitOrder(placed id: UUID) {
        let ordered = displayedFolders
        env.perform { try env.library(ctx).setFolderOrder(ordered) }
        liveOrder = nil
        if !reduceMotion { settleCounts[id, default: 0] += 1 }
    }

    private func requestDelete(_ folder: Folder) {
        if folder.children.isEmpty && folder.clips.isEmpty {
            env.perform { try env.library(ctx).deleteFolder(folder, mode: .deleteContents) }
        } else {
            deletingFolder = folder
        }
    }
}
