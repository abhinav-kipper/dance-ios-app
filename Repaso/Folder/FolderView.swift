import SwiftUI
import SwiftData
import PhotosUI
import RepasoCore

/// A folder (or Unsorted when `folderID == nil`): subfolders, originals with their clips, loose clips.
struct FolderView: View {
    let folderID: UUID?
    @Binding var path: [Route]

    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var matches: [Folder]
    @Query(filter: #Predicate<Original> { $0.folder == nil }) private var unsortedOriginals: [Original]
    @AppStorage private var sortRaw: String
    @AppStorage private var hideLearned: Bool

    @State private var sheet: LibrarySheet?
    @State private var player: PlayerRequest?
    @State private var cutting: Original?
    @State private var deletingClip: Clip?
    @State private var picks: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var showImport = false
    @State private var editingFolderID: UUID?
    @State private var hoveredFolderID: UUID?
    @State private var springTask: Task<Void, Never>?
    @State private var absorbCounts: [UUID: Int] = [:]
    @State private var dropSuccess = 0
    @State private var springLoads = 0

    init(folderID: UUID?, path: Binding<[Route]>) {
        self.folderID = folderID
        _path = path
        let id = folderID ?? UUID()
        _matches = Query(filter: #Predicate<Folder> { $0.id == id })
        let key = folderID?.uuidString ?? "unsorted"
        _sortRaw = AppStorage(wrappedValue: ClipSort.manual.rawValue, "sort.\(key)")
        _hideLearned = AppStorage(wrappedValue: false, "hideLearned.\(key)")
    }

    private var folder: Folder? { matches.first }
    private var sort: ClipSort { ClipSort(rawValue: sortRaw) ?? .manual }
    private var title: String { folder?.name ?? "Unsorted" }

    private var originals: [Original] {
        if let folder { return FolderContents.originals(in: folder, sort: sort) }
        return FolderContents.sortOriginals(unsortedOriginals, by: sort)
    }

    private var looseClips: [Clip] {
        guard let folder else { return [] }
        return FolderContents.looseClips(in: folder, sort: sort, hideLearned: hideLearned)
    }

    private var subfolders: [Folder] {
        folder.map(FolderContents.subfolders(of:)) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                chips
                if folder != nil { subfolderSection }
                originalsSection
                if !looseClips.isEmpty { looseSection }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollPhaseChange { _, phase in
            env.previews.setScrolling(fast: phase == .decelerating || phase == .animating)
        }
        // Catcher: a clip carried in from another screen (spring-loading) can be dropped anywhere here.
        .dragTarget(env.drag) { ref in
            guard let folder, env.drag.origin != folder.id else { return false }
            return drop(ref, on: folder)
        }
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            FloatingPill(title: "Import", systemImage: "square.and.arrow.down") { showPicker = true }
        }
        .overlay(alignment: .top) { dropBanner }
        .animation(Theme.spring, value: showDropBanner)
        .sensoryFeedback(.success, trigger: dropSuccess)
        .sensoryFeedback(.impact(weight: .light), trigger: springLoads)
        .onChange(of: env.drag.active) { _, active in
            if active == nil {
                springTask?.cancel()
                hoveredFolderID = nil
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .photosPicker(isPresented: $showPicker, selection: $picks, matching: .videos,
                         preferredItemEncoding: .current, photoLibrary: .shared())
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            env.importer.start(new, into: folder, context: ctx, env: env)
            picks = []
            showImport = true
        }
        .onChange(of: matches.isEmpty) { _, gone in
            if gone && folderID != nil { dismiss() }   // folder deleted while open
        }
        .sheet(isPresented: $showImport) { ImportSheet() }
        .sheet(item: $sheet) { $0.content }
        .fullScreenCover(item: $player) { PlayerView(request: $0) }
        .fullScreenCover(item: $cutting) { CutView(original: $0) }
        .confirmationDialog("Delete this clip?", isPresented: deleteClipBinding, titleVisibility: .visible, presenting: deletingClip) { clip in
            Button("Delete “\(clip.name)”", role: .destructive) {
                env.perform { try env.library(ctx).deleteClip(clip) }
            }
        } message: { _ in
            Text("The video stays in your library.")
        }
        .toastHost(env)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if !path.isEmpty { path.removeLast() } else { dismiss() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Text(folder?.parent?.name ?? "Home").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
                .contentShape([.interaction, .accessibility], Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(folder?.parent?.name ?? "Home")")

            if let folder, !folder.ancestors.isEmpty {
                Text((["Home"] + folder.ancestors.map(\.name) + [folder.name]).joined(separator: " › "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(summary)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var summary: String {
        let clipCount = folder.map(FolderContents.clipCount(in:)) ?? unsortedOriginals.reduce(0) { $0 + $1.clips.count }
        var parts = [clipCount == 1 ? "1 clip" : "\(clipCount) clips",
                     originals.count == 1 ? "1 original" : "\(originals.count) originals"]
        if folder != nil { parts.append(subfolders.count == 1 ? "1 folder" : "\(subfolders.count) folders") }
        return parts.joined(separator: " · ")
    }

    private var chips: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(ClipSort.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
            } label: {
                Chip(title: "Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort, \(sort.title)")
            Button {
                withAnimation(Theme.spring) { hideLearned.toggle() }
            } label: {
                Chip(title: "Hide learned", systemImage: "checkmark", isOn: hideLearned)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityAddTraits(hideLearned ? .isSelected : [])
        }
    }

    private var subfolderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if isClipDragActive {
                    Text("Drop on a folder").sectionLabelStyle(Theme.accent)
                } else {
                    Text("Folders").sectionLabelStyle()
                }
            }
            .animation(.easeOut(duration: 0.2), value: isClipDragActive)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(subfolders) { sub in
                    let editing = Binding(
                        get: { editingFolderID == sub.id },
                        set: { if !$0 { editingFolderID = nil } })
                    Group {
                        if editingFolderID == sub.id {
                            dropCard(sub, editing: editing)
                        } else {
                            NavigationLink(value: Route.folder(sub.id)) {
                                dropCard(sub, editing: editing)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    .zIndex(hoveredFolderID == sub.id ? 1 : 0)
                    .dragTarget(env.drag, isTargeted: { hover(sub, $0) }) { ref in
                        hoveredFolderID = nil
                        return drop(ref, on: sub)
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { editingFolderID = sub.id }
                        Button("Move", systemImage: "folder") { sheet = .move(.folder(sub)) }
                        Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(sub) }
                    }
                }
                Button(action: newSubfolder) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textSecondary))
                        .frame(minHeight: 132)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("New subfolder")
            }
        }
    }

    @ViewBuilder
    private var originalsSection: some View {
        if !originals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Originals").sectionLabelStyle()
                ForEach(Array(originals.enumerated()), id: \.element.id) { i, original in
                    OriginalCard(
                        original: original,
                        clips: FolderContents.clips(of: original, sort: sort, hideLearned: hideLearned),
                        actions: clipActions,
                        onPlay: { playOriginal(original) },
                        onCut: { cutting = original },
                        onMove: { sheet = .move(.original(original)) },
                        onDelete: { sheet = .deleteOriginal(original) },
                        isDraggable: folder != nil,
                        dragOrigin: folderID)
                    .riseIn(i)
                }
            }
        } else if folder == nil || (subfolders.isEmpty && looseClips.isEmpty) {
            Text("No videos here yet. Tap Import to add some.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
        }
    }

    private var looseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loose clips").sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(Array(looseClips.enumerated()), id: \.element.id) { i, clip in
                    ClipRow(clip: clip, context: .loose, actions: clipActions, isDraggable: true, dragOrigin: folderID)
                        .padding(.horizontal, 12)
                        .riseIn(i)
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .padding(.vertical, 4)
            .cardGlass(radius: Theme.Radius.listCard)
            .animation(Theme.spring, value: looseClips.map(\.id))
        }
    }

    // MARK: Actions

    private var clipActions: ClipActions {
        ClipActions(
            play: { clip in
                let queue = FolderContents.playQueue(originals: originals, loose: looseClips, sort: sort, hideLearned: hideLearned)
                let all = queue.contains { $0.id == clip.id } ? queue : [clip] + queue
                player = PlayerRequest(queue: all, index: all.firstIndex { $0.id == clip.id } ?? 0, title: title)
            },
            move: { sheet = .move(.clip($0)) },
            info: { sheet = .info($0) },
            delete: { deletingClip = $0 },
            share: { sheet = .share($0) })
    }

    /// Plays the whole video; swiping moves between this folder's videos.
    private func playOriginal(_ original: Original) {
        let items = originals.map(PlaybackItem.original)
        player = PlayerRequest(items: items, index: originals.firstIndex { $0.id == original.id } ?? 0, title: title)
    }

        private var deleteClipBinding: Binding<Bool> {
        Binding(get: { deletingClip != nil }, set: { if !$0 { deletingClip = nil } })
    }

    private func newSubfolder() {
        guard let folder else { return }
        env.perform {
            var created: Folder?
            try withAnimation(Theme.spring) { created = try env.library(ctx).createFolder(named: "", in: folder) }
            editingFolderID = created?.id
        }
    }

    // MARK: Drag and drop

    private var isClipDragActive: Bool { env.drag.active?.kind == .clip }

    /// A clip dragged in from another folder screen can be dropped anywhere on this one.
    private var showDropBanner: Bool {
        guard let folder, isClipDragActive else { return false }
        return env.drag.origin != folder.id
    }

    @ViewBuilder
    private var dropBanner: some View {
        if showDropBanner, let folder {
            Label("Drop to file in \(folder.name)", systemImage: "arrow.down.to.line")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Theme.accent, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private func dropCard(_ sub: Folder, editing: Binding<Bool>) -> some View {
        SubfolderDropCard(folder: sub, isEditingName: editing, isClipDragActive: isClipDragActive,
                          isHovered: hoveredFolderID == sub.id, absorbCount: absorbCounts[sub.id, default: 0])
    }

    /// Hover starts the 0.9s spring-load: if still hovered, the folder opens with the drag in hand.
    private func hover(_ sub: Folder, _ isTargeted: Bool) {
        guard isClipDragActive else { return }
        springTask?.cancel()
        guard isTargeted else {
            if hoveredFolderID == sub.id { hoveredFolderID = nil }
            return
        }
        hoveredFolderID = sub.id
        springTask = Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled, hoveredFolderID == sub.id else { return }
            hoveredFolderID = nil
            springLoads += 1
            path.append(.folder(sub.id))
        }
    }

    private func drop(_ ref: DragRef, on target: Folder) -> Bool {
        springTask?.cancel()
        guard ref.kind == .clip, let clip = fetchClip(ref.id) else { return false }
        let lib = env.library(ctx)
        var receipt: ClipMoveReceipt?
        env.perform { receipt = try withAnimation(Theme.spring) { try lib.dropClip(clip, on: target) } }
        guard let receipt else { return false }
        if !reduceMotion { absorbCounts[target.id, default: 0] += 1 }
        dropSuccess += 1
        let env = env
        env.showToast("Moved to \(target.name)") {
            env.perform { try withAnimation(Theme.spring) { try lib.undo(receipt) } }
        }
        return true
    }

    private func fetchClip(_ id: UUID) -> Clip? {
        try? ctx.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.id == id })).first
    }

    private func requestDelete(_ sub: Folder) {
        if sub.children.isEmpty && sub.originals.isEmpty && sub.looseClips.isEmpty {
            env.perform { try env.library(ctx).deleteFolder(sub, mode: .deleteContents) }
        } else {
            sheet = .deleteFolder(sub)
        }
    }
}

/// All favorite clips, as one flat list.
struct FavoritesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Clip> { $0.isFavorite }) private var favorites: [Clip]
    @AppStorage("sort.favorites") private var sortRaw = ClipSort.manual.rawValue
    @State private var sheet: LibrarySheet?
    @State private var player: PlayerRequest?
    @State private var deletingClip: Clip?

    private var clips: [Clip] {
        FolderContents.sortClips(favorites.filter { $0.original != nil }, by: ClipSort(rawValue: sortRaw) ?? .manual)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        Text("Home").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .contentShape([.interaction, .accessibility], Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Home")
                Text("Favorites")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Menu {
                    Picker("Sort", selection: $sortRaw) {
                        ForEach(ClipSort.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    Chip(title: "Sort", systemImage: "arrow.up.arrow.down")
                }
                if clips.isEmpty {
                    Text("Tap the star on a clip to add it here.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { i, clip in
                            ClipRow(clip: clip, context: .loose, actions: actions)
                                .padding(.horizontal, 12)
                                .riseIn(i)
                        }
                    }
                    .padding(.vertical, 4)
                    .cardGlass(radius: Theme.Radius.listCard)
                    .animation(Theme.spring, value: clips.map(\.id))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 60)
        }
        .onScrollPhaseChange { _, phase in
            env.previews.setScrolling(fast: phase == .decelerating || phase == .animating)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { $0.content }
        .fullScreenCover(item: $player) { PlayerView(request: $0) }
        .confirmationDialog("Delete this clip?", isPresented: Binding(get: { deletingClip != nil }, set: { if !$0 { deletingClip = nil } }),
                            titleVisibility: .visible, presenting: deletingClip) { clip in
            Button("Delete “\(clip.name)”", role: .destructive) {
                env.perform { try env.library(ctx).deleteClip(clip) }
            }
        }
        .toastHost(env)
    }

    private var actions: ClipActions {
        ClipActions(
            play: { clip in
                player = PlayerRequest(queue: clips, index: clips.firstIndex { $0.id == clip.id } ?? 0, title: "Favorites")
            },
            move: { sheet = .move(.clip($0)) },
            info: { sheet = .info($0) },
            delete: { deletingClip = $0 },
            share: { sheet = .share($0) })
    }
}
