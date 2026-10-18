import SwiftUI
import SwiftData
import PhotosUI
import RepasoCore

/// A folder: its subfolders, then its clips as preview cards.
struct FolderView: View {
    let folderID: UUID
    @Binding var path: [Route]

    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var matches: [Folder]
    @AppStorage private var sortRaw: String
    @AppStorage private var hideLearned: Bool

    @State private var sheet: LibrarySheet?
    @State private var player: PlayerRequest?
    @State private var cutting: CutRequest?
    /// Arrange mode: press-and-hold drags clips and folders (to reorder, or a clip onto a folder) instead of
    /// opening their menu.
    @State private var arranging = false
    @State private var clipArrange = ArrangeSession()
    @State private var folderArrange = ArrangeSession()
    @State private var deletingClip: Clip?
    @State private var picks: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var editingFolderID: UUID?
    @State private var absorbCounts: [UUID: Int] = [:]
    @State private var dropSuccess = 0

    init(folderID: UUID, path: Binding<[Route]>) {
        self.folderID = folderID
        _path = path
        let id = folderID
        _matches = Query(filter: #Predicate<Folder> { $0.id == id })
        let key = folderID.uuidString
        _sortRaw = AppStorage(wrappedValue: ClipSort.manual.rawValue, "sort.\(key)")
        _hideLearned = AppStorage(wrappedValue: false, "hideLearned.\(key)")
    }

    private var folder: Folder? { matches.first }
    private var sort: ClipSort { ClipSort(rawValue: sortRaw) ?? .manual }
    private var title: String { folder?.name ?? "" }

    private var clips: [Clip] {
        folder.map { FolderContents.folderClips(in: $0, sort: sort, hideLearned: hideLearned) } ?? []
    }

    private var subfolders: [Folder] {
        folder.map(FolderContents.subfolders(of:)) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !subfolders.isEmpty { subfolderSection }
                if !clips.isEmpty || subfolders.isEmpty { chips }   // they act on what's below, so they sit above it
                clipsSection
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 140)
            .coordinateSpace(.named(ArrangeSession.space))
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollDisabled(clipArrange.isActive || folderArrange.isActive)   // a card is up: the finger moves it
        .onScrollPhaseChange { _, phase in
            env.previews.setScrolling(fast: phase == .decelerating || phase == .animating)
        }
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            FloatingPill(title: "Import", systemImage: "square.and.arrow.down") { showPicker = true }
        }
        .sensoryFeedback(.success, trigger: dropSuccess)
        .toolbar(.hidden, for: .navigationBar)
        .photosPicker(isPresented: $showPicker, selection: $picks, matching: .importableVideos,
                         preferredItemEncoding: .current, photoLibrary: .shared())
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            env.startImport(new, from: folder, context: ctx)
            picks = []
        }
        .onChange(of: clips.isEmpty && subfolders.count < 2) { _, nothing in if nothing { arranging = false } }
        .onChange(of: matches.isEmpty) { _, gone in
            if gone { dismiss() }   // folder deleted while open
        }
        .sheet(item: $sheet) { $0.content }
        .fullScreenCover(item: $player) { PlayerView(request: $0) }
        .fullScreenCover(item: $cutting) { CutView(recording: $0.recording, focusClipID: $0.focusClipID) }
        .clipDeleteDialog($deletingClip)
        .toastHost(env)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tap goes back one level; press and hold lists every level above (like Safari's back button).
            Menu {
                Button("Home", systemImage: "house") { path.removeAll() }
                let chain = folder?.ancestors ?? []
                ForEach(Array(chain.enumerated()), id: \.element.id) { i, ancestor in
                    Button(ancestor.name, systemImage: "folder") {
                        path = chain.prefix(i + 1).map { Route.folder($0.id) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Text(folder?.parent?.name ?? "Home").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.rose)
                .frame(minHeight: 44)
                .contentShape([.interaction, .accessibility], Rectangle())
            } primaryAction: {
                if !path.isEmpty { path.removeLast() } else { dismiss() }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(folder?.parent?.name ?? "Home")")
            .accessibilityHint("Press and hold to jump to Home or a folder above")

            if let folder, !folder.ancestors.isEmpty {
                Text((["Home"] + folder.ancestors.map(\.name) + [folder.name]).joined(separator: " › "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var chips: some View {
        HStack(spacing: 10) {
            if !clips.isEmpty {
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
            // With no subfolders yet, a chip makes the first one instead of a big empty card.
            if subfolders.isEmpty {
                Button(action: newSubfolder) {
                    Chip(title: "Folder", systemImage: "plus")
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("New subfolder")
            }
        }
    }

    /// "Arrange" in a section header, like Home's; "Done" while arranging.
    private var arrangeToggle: some View {
        Button {
            if !arranging { sortRaw = ClipSort.manual.rawValue }   // the order being arranged is the manual one
            withAnimation(Theme.spring) { arranging.toggle() }
        } label: {
            if arranging {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Theme.rose, in: Capsule())
                    .frame(minHeight: 44)
            } else {
                Label("Arrange", systemImage: "hand.draw")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.rose)
                    .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .contentShape([.interaction, .accessibility], Rectangle())
        .accessibilityLabel(arranging ? "Done arranging" : "Arrange clips and folders")
    }

    private var subfolderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(clipArrange.isActive ? "Drop on a folder" : "Folders")
                    .sectionLabelStyle(clipArrange.isActive ? Theme.rose : Theme.textSecondary)
                    .animation(.easeOut(duration: 0.2), value: clipArrange.isActive)
                Spacer()
                if clips.isEmpty && subfolders.count > 1 { arrangeToggle }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(folderArrange.arranged(subfolders)) { sub in
                    let editing = Binding(
                        get: { editingFolderID == sub.id },
                        set: { if !$0 { editingFolderID = nil } })
                    Group {
                        if editingFolderID == sub.id || arranging {
                            dropCard(sub, editing: editing)
                        } else {
                            NavigationLink(value: Route.folder(sub.id)) {
                                dropCard(sub, editing: editing)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    .zIndex(clipArrange.hoveredTarget == sub.id ? 1 : 0)
                    .arrangeTarget(sub.id, in: clipArrange)
                    .jiggle(arranging && folderArrange.dragging != sub.id)
                    .arrangeItem(sub.id, in: folderArrange, items: subfolders.map(\.id), enabled: arranging) { outcome in
                        guard case .reordered(let ids) = outcome else { return }
                        let byID = Dictionary(subfolders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        env.perform { try env.library(ctx).setFolderOrder(ids.compactMap { byID[$0] }) }
                    }
                    .modifier(MenuUnlessArranging(isArranging: arranging) {
                        Button("Rename", systemImage: "pencil") { editingFolderID = sub.id }
                        Button("Move", systemImage: "folder") { sheet = .move(.folder(sub)) }
                        Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(sub) }
                    })
                }
                if !arranging {
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
            .animation(Theme.motion(reduceMotion), value: folderArrange.order)
        }
    }

    @ViewBuilder
    private var clipsSection: some View {
        if !clips.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Clips").sectionLabelStyle()
                    Spacer()
                    if clips.count > 1 || subfolders.count > 1 || arranging { arrangeToggle }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(clipArrange.arranged(clips).enumerated()), id: \.element.id) { i, clip in
                        let linked = linkedHome(of: clip)
                        ClipCard(clip: clip, actions: clipActions, isArranging: arranging && linked == nil,
                                 isLifted: clipArrange.dragging == clip.id, linkedHome: linked)
                            .arrangeItem(clip.id, in: clipArrange, items: homeClipIDs, enabled: arranging && linked == nil) {
                                finishClipArrange($0)
                            }
                            .riseIn(i)
                            .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.6).combined(with: .opacity)))
                    }
                }
                .animation(Theme.spring, value: clips.map(\.id))
                .animation(Theme.motion(reduceMotion), value: clipArrange.order)
            }
        } else if subfolders.isEmpty {
            Text("No clips yet")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
        }
    }

    // MARK: Actions

    private var clipActions: ClipActions {
        ClipActions(
            play: { clip in
                let queue = clips
                let all = queue.contains { $0.id == clip.id } ? queue : [clip] + queue
                player = PlayerRequest(queue: all, index: all.firstIndex { $0.id == clip.id } ?? 0, title: title)
            },
            info: { sheet = .info($0) },
            delete: { deletingClip = $0 },
            share: { sheet = .share($0) },
            link: { sheet = .link($0) },
            unlink: { unlink($0) },
            folderName: folder?.name,
            trim: { clip in
                guard let recording = clip.recording else { return }
                cutting = CutRequest(recording: recording, focusClipID: clip.id)
            })
    }

    // MARK: Links

    /// Home folder name when `clip` shows here only through a link.
    private func linkedHome(of clip: Clip) -> String? {
        guard let folder, FolderContents.isLinked(clip, in: folder) else { return nil }
        return clip.folder?.name
    }

    private func unlink(_ clip: Clip) {
        guard let folder else { return }
        let lib = env.library(ctx)
        env.perform { try withAnimation(Theme.spring) { try lib.unlink(clip, from: folder) } }
        let env = env
        env.showToast("Removed from \(folder.name)") {
            env.perform { try lib.setLinks(clip, to: clip.linkedFolders + [folder]) }
        }
    }

    private func newSubfolder() {
        guard let folder else { return }
        env.perform {
            var created: Folder?
            try withAnimation(Theme.spring) { created = try env.library(ctx).createFolder(named: "", in: folder) }
            editingFolderID = created?.id
        }
    }

    // MARK: Arrange

    /// Clips that live here (linked ones keep their place at the end).
    private var homeClipIDs: [UUID] { clips.filter { linkedHome(of: $0) == nil }.map(\.id) }

    private func dropCard(_ sub: Folder, editing: Binding<Bool>) -> some View {
        SubfolderDropCard(folder: sub, isEditingName: editing, isClipDragActive: clipArrange.isActive,
                          isHovered: clipArrange.hoveredTarget == sub.id, absorbCount: absorbCounts[sub.id, default: 0])
    }

    /// The end of a clip drag: a new order, or the clip filed in the folder it was let go over.
    private func finishClipArrange(_ outcome: ArrangeSession.Outcome) {
        guard let folder else { return }
        let lib = env.library(ctx)
        switch outcome {
        case .reordered(let ids):
            let byID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            env.perform { try lib.setClipOrder(ids.compactMap { byID[$0] }, in: folder) }
        case .dropped(let clipID, let targetID):
            guard let clip = clips.first(where: { $0.id == clipID }),
                  let target = subfolders.first(where: { $0.id == targetID }) else { return }
            var receipt: ClipMoveReceipt?
            env.perform { receipt = try lib.dropClip(clip, on: target) }
            guard let receipt else { return }
            if !reduceMotion { absorbCounts[target.id, default: 0] += 1 }
            dropSuccess += 1
            let env = env
            env.showToast("Moved to \(target.name)") {
                env.perform { try withAnimation(Theme.spring) { try lib.undo(receipt) } }
            }
        case .none:
            break
        }
    }

    private func requestDelete(_ sub: Folder) {
        if sub.children.isEmpty && sub.clips.isEmpty {
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
    @State private var cutting: CutRequest?

    private var clips: [Clip] {
        FolderContents.sortClips(favorites.filter(\.isFiled), by: ClipSort(rawValue: sortRaw) ?? .manual)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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
                    Text("No favorites yet")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { i, clip in
                            ClipCard(clip: clip, actions: actions)
                                .riseIn(i)
                        }
                    }
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
        .fullScreenCover(item: $cutting) { CutView(recording: $0.recording, focusClipID: $0.focusClipID) }
        .clipDeleteDialog($deletingClip)
        .toastHost(env)
    }

    private var actions: ClipActions {
        ClipActions(
            play: { clip in
                player = PlayerRequest(queue: clips, index: clips.firstIndex { $0.id == clip.id } ?? 0, title: "Favorites")
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
