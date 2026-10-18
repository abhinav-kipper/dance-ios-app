import SwiftUI
import SwiftData
import RepasoCore

/// Videos still to go through the import guide, in the order they were picked. Tap one to carry on where it was
/// left; press and hold to delete it.
struct UnsortedView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Recording> { $0.isPending }, sort: \Recording.sortIndex) private var pending: [Recording]
    @State private var deleting: Recording?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

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
                Text("Unsorted")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(pending.enumerated()), id: \.element.id) { i, recording in
                        card(recording).riseIn(i)
                    }
                }
                .animation(Theme.spring, value: pending.map(\.id))
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 60)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: pending.isEmpty) { _, empty in if empty { dismiss() } }
        .confirmationDialog("Delete this video?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { recording in
            Button(Self.deleteTitle(recording), role: .destructive) {
                env.perform { try withAnimation(Theme.spring) { try env.library(ctx).deletePending(recording) } }
            }
        }
        .toastHost(env)
    }

    /// "Delete video", or "Delete video and 2 clips".
    private static func deleteTitle(_ recording: Recording) -> String {
        switch recording.clips.count {
        case 0: "Delete video"
        case 1: "Delete video and 1 clip"
        case let n: "Delete video and \(n) clips"
        }
    }

    private func card(_ recording: Recording) -> some View {
        let title = ImportCoordinator.title(recordedAt: recording.recordedAt)
        let made = recording.clips.count
        return Button { env.resume(recording, context: ctx) } label: {
            VStack(alignment: .leading, spacing: 8) {
                PosterView(request: recording.thumbnailRequest, cornerRadius: 18)
                    .aspectRatio(3 / 4, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(made == 0 ? TimeFormat.duration(recording.duration)
                     : (made == 1 ? "1 clip so far" : "\(made) clips so far"))
                    .font(.system(size: 13, weight: made == 0 ? .regular : .semibold))
                    .foregroundStyle(made == 0 ? Theme.textSecondary : Theme.rose)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(made == 0 ? title : "\(title), \(made == 1 ? "1 clip so far" : "\(made) clips so far")")
        .accessibilityHint("Carries on importing this video")
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = recording }
        }
    }
}
