import SwiftUI
import SwiftData
import RepasoCore

/// Name + note (140 max) for a clip.
struct ClipInfoSheet: View {
    let clip: Clip
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var note = ""
    @State private var saved = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name & note")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 28)

            field("Name") {
                TextField("Clip name", text: $name)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit(save)
            }
            field("Note") {
                TextField("What to remember", text: $note, axis: .vertical)
                    .lineLimit(3...5)
                    .onChange(of: note) { _, new in
                        if new.count > LibraryService.noteLimit { note = String(new.prefix(LibraryService.noteLimit)) }
                    }
            }
            Text("\(note.count)/\(LibraryService.noteLimit)")
                .font(Theme.mono(12))
                .foregroundStyle(note.count >= LibraryService.noteLimit ? Theme.rose : Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Spacer()
            PrimarySheetButton(title: saved ? "Saved" : "Save", action: save)
                .overlay(alignment: .leading) {
                    if saved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.onAccent)
                            .padding(.leading, 20)
                            .transition(.scale)
                    }
                }
                .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet(detents: [.medium])
        .onAppear {
            name = clip.name
            note = clip.note ?? ""
            nameFocused = true   // ready to type
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabelStyle()
            content()
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .padding(12)
                .frame(minHeight: 44)
                .cardGlass(radius: 14)
        }
    }

    private func save() {
        env.perform { try env.library(ctx).updateInfo(clip, name: name, note: note) }
        withAnimation(Theme.spring) { saved = true }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            dismiss()
        }
    }
}
