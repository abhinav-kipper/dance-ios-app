import SwiftUI
import SwiftData
import RepasoCore

/// Title, note (140 max), instructors and class/event for a video ("Edit details…").
struct VideoInfoSheet: View {
    let original: Original
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var instructors = ""
    @State private var event = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Video details")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Title") {
                        TextField("Video title", text: $title)
                            .submitLabel(.done)
                    }
                    field("Note") {
                        TextField("What to remember", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .onChange(of: note) { _, new in
                                if new.count > LibraryService.noteLimit { note = String(new.prefix(LibraryService.noteLimit)) }
                            }
                            .accessibilityLabel("Note")
                    }
                    Text("\(note.count)/\(LibraryService.noteLimit)")
                        .font(Theme.mono(12))
                        .foregroundStyle(note.count >= LibraryService.noteLimit ? Theme.rose : Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, -8)
                    field("Instructor(s)") {
                        TextField("Who taught it", text: $instructors)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                    field("Class or event") {
                        TextField("Where it was", text: $event)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            PrimarySheetButton(title: saved ? "Saved" : "Save", action: save)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet(detents: [.large])
        .onAppear {
            title = original.title
            note = original.note ?? ""
            instructors = original.instructors.joined(separator: ", ")
            event = original.event ?? ""
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
        env.perform {
            try env.library(ctx).updateDetails(original, title: title, note: note,
                                               instructors: TagText.instructors(from: instructors), event: event)
        }
        withAnimation(Theme.spring) { saved = true }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            dismiss()
        }
    }
}
