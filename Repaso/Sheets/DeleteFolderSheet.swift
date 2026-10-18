import SwiftUI
import SwiftData
import RepasoCore

/// Asks whether to delete a folder's contents or move them up one level (Orphans for a top-level folder's clips).
struct DeleteFolderSheet: View {
    let folder: Folder
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let parentName = folder.parent?.name ?? "Home"
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.rose)
                .frame(width: 64, height: 64)
                .background(Theme.roseTint, in: Circle())
                .padding(.top, 28)
            Text("Delete “\(folder.name)”?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if !detail(parentName).isEmpty {
                Text(detail(parentName))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            PrimarySheetButton(title: "Delete with contents", role: .destructive) { delete(.deleteContents) }
            if !folder.isOrphans {
                PrimarySheetButton(title: "Keep contents") { delete(.moveContentsUp) }
            }
            Button("Cancel") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet(detents: [.medium])
    }

    /// What "Move contents up" does here. A top-level folder's clips have nowhere above them, so they go to Orphans.
    private func detail(_ parentName: String) -> String {
        if folder.isOrphans { return "" }
        if folder.parent == nil {
            return folder.clips.isEmpty ? "Kept contents move to Home." : "Kept clips move to \(LibraryService.orphansName)."
        }
        return "Kept contents move to \(parentName)."
    }

    private func delete(_ mode: FolderDeleteMode) {
        env.perform { try env.library(ctx).deleteFolder(folder, mode: mode) }
        dismiss()
    }
}
