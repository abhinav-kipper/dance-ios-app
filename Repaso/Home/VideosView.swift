import SwiftUI
import SwiftData
import RepasoCore

/// Every full video you've imported, newest first: watch one, cut more clips from it, edit, move or delete it.
/// Videos with clips stay out of folders (their clips live there); this is where they're kept.
struct VideosView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Original]
    @State private var sheet: LibrarySheet?
    @State private var player: PlayerRequest?
    @State private var cutting: CutRequest?

    private var videos: [Original] { FolderContents.allVideos(all) }

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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full videos")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("The videos your clips come from. Cut more, or keep only the clips to save space.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                }
                if videos.isEmpty {
                    Text("No full videos. Import some from Home.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { i, original in
                        OriginalCard(
                            original: original,
                            clips: [],
                            actions: noClipActions,
                            onPlay: { play(original) },
                            onCut: { cutting = CutRequest(original: original) },
                            onMove: { sheet = .move(.original(original)) },
                            onDelete: { sheet = .deleteOriginal(original) },
                            onLink: { sheet = .link(.original(original)) },
                            onEdit: { sheet = .videoInfo(original) },
                            showsLocation: true)
                        .riseIn(i)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 60)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { $0.content }
        .fullScreenCover(item: $player) { PlayerView(request: $0) }
        .fullScreenCover(item: $cutting) { CutView(original: $0.original, focusClipID: $0.focusClipID) }
        .toastHost(env)
    }

    /// Swiping in the Player moves between the full videos.
    private func play(_ original: Original) {
        player = PlayerRequest(items: videos.map(PlaybackItem.original),
                               index: videos.firstIndex { $0.id == original.id } ?? 0, title: "Full videos")
    }

    /// The cards here list no clips, so these are never called.
    private var noClipActions: ClipActions {
        ClipActions(play: { _ in }, move: { _ in }, info: { _ in }, delete: { _ in }, share: { _ in })
    }
}
