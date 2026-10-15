import SwiftUI
import SwiftData
import RepasoCore

/// Folder card: 2×2 poster mosaic (dashed outline when empty), name, recursive clip count.
/// `compact` is the 3-column subfolder variant.
struct FolderCard: View {
    let folder: Folder
    var compact = false
    @Binding var isEditingName: Bool
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var ctx
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let mosaic = FolderContents.mosaic(for: folder)
        let count = FolderContents.clipCount(in: folder)
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            mosaicView(mosaic)
                .frame(height: compact ? 80 : 112)
            if isEditingName {
                TextField("Folder name", text: $draft)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focused)
                    .submitLabel(.done)
                    .accessibilityLabel("Folder name")
                    .onAppear {
                        draft = folder.name == LibraryService.defaultFolderName ? "" : folder.name
                        focused = true
                    }
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            } else {
                Text(folder.name)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Text(count == 1 ? "1 clip" : "\(count) clips")
                .font(.system(size: compact ? 12 : 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass(radius: compact ? 18 : Theme.Radius.folderCard)
        .accessibilityElement(children: isEditingName ? .contain : .combine)
    }

    @ViewBuilder
    private func mosaicView(_ requests: [ThumbnailRequest]) -> some View {
        if requests.isEmpty {
            RoundedRectangle(cornerRadius: Theme.Radius.mosaic, style: .continuous)
                .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .overlay(Image(systemName: "folder").foregroundStyle(.white.opacity(0.35)))
        } else {
            let cells = (0..<4).map { $0 < requests.count ? requests[$0] : nil }
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    PosterView(request: cells[0], cornerRadius: 0)
                    PosterView(request: cells[1], cornerRadius: 0)
                }
                GridRow {
                    PosterView(request: cells[2], cornerRadius: 0)
                    PosterView(request: cells[3], cornerRadius: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.mosaic, style: .continuous))
        }
    }

    private func commit() {
        guard isEditingName else { return }
        isEditingName = false
        env.perform { try env.library(ctx).renameFolder(folder, to: draft) }
    }
}
