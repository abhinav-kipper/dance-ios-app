import SwiftUI
import SwiftData
import RepasoCore

/// "New folder" row at the top of folder pickers (Move, Add to folders): asks for a name and creates the folder
/// on Home, or inside `suggestedParent` when one is chosen, then hands it back so the picker can select it.
struct NewFolderRow: View {
    var suggestedParent: Folder?
    let onCreate: (Folder) -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @State private var asking = false
    @State private var name = ""

    var body: some View {
        Button {
            name = ""
            asking = true
        } label: {
            HStack(spacing: 10) {
                Color.clear.frame(width: 28, height: 44)   // lines up with the tree's chevron column
                Image(systemName: "folder.badge.plus")
                Text("New folder")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .alert("New folder", isPresented: $asking) {
            TextField("Name", text: $name)
            if let parent = suggestedParent {
                Button("Create in \(parent.name)") { create(in: parent) }
                Button("Create on Home") { create(in: nil) }
            } else {
                Button("Create") { create(in: nil) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(suggestedParent.map { "Inside \($0.name), or on Home." } ?? "It goes on Home.")
        }
    }

    private func create(in parent: Folder?) {
        env.perform {
            let folder = try env.library(ctx).createFolder(named: name, in: parent)
            onCreate(folder)
        }
    }
}
