import SwiftUI
import SwiftData
import RepasoCore

/// The import guide's card for naming a clip: the name (required) and who taught it (optional), each with
/// suggestion chips from clips already made. Slides up over the video.
struct NameCard: View {
    let title: String
    var initialName = ""
    let instructors: [String]
    var saveTitle = "Save clip"
    let onSave: (String, [String]) -> Void
    let onCancel: () -> Void

    @Query(sort: \Clip.addedAt, order: .reverse) private var allClips: [Clip]
    @State private var name = ""
    @State private var teachers = ""
    @FocusState private var focus: Field?

    private enum Field { case name, teachers }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            field("Name", text: $name, prompt: "Backazouk", field: .name, identifier: "clipName")
                .submitLabel(.done)
                .onSubmit(save)
            chips(TagSuggestions.names(for: name, in: allClips).filter { $0 != cleanName }) { name = $0 }

            field("Instructors (optional)", text: $teachers, prompt: "Ataca & Alemana", field: .teachers,
                  identifier: "clipInstructors")
                .submitLabel(.done)
                .onSubmit(save)
            chips(TagSuggestions.instructors(for: TagText.lastToken(of: teachers),
                                             excluding: TagText.instructors(from: teachers), in: allClips)) {
                teachers = TagText.completing(teachers, with: $0)
            }

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white.opacity(0.1), in: Capsule())
                    .buttonStyle(PressableButtonStyle())
                Button(action: save) {
                    Text(saveTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.accent.opacity(cleanName.isEmpty ? 0.35 : 1), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(cleanName.isEmpty)
                .accessibilityIdentifier("saveClip")
            }
        }
        .padding(20)
        .background(Theme.sheetFill, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .padding(.horizontal, 10)
        .onAppear {
            name = initialName
            teachers = instructors.isEmpty ? "" : instructors.joined(separator: ", ")
            focus = .name
        }
    }

    private func save() {
        guard !cleanName.isEmpty else { return }
        onSave(cleanName, TagText.instructors(from: teachers))
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, field: Field, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(Theme.textSecondary.opacity(0.6)))
                .font(.system(size: 17))
                .foregroundStyle(Theme.textPrimary)
                .focused($focus, equals: field)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.leading, 14)
                .padding(.trailing, text.wrappedValue.isEmpty ? 14 : 44)
                .frame(height: 48)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(focus == field ? Theme.rose : .clear, lineWidth: 1.5)
                }
                .accessibilityIdentifier(identifier)
                .overlay(alignment: .trailing) {
                    if !text.wrappedValue.isEmpty && focus == field {
                        Button { text.wrappedValue = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear \(label)")
                    }
                }
        }
    }

    @ViewBuilder
    private func chips(_ values: [String], pick: @escaping (String) -> Void) -> some View {
        if !values.isEmpty {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button(value) { pick(value) }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Theme.roseTint, in: Capsule())
                        .buttonStyle(PressableButtonStyle())
                        .frame(minHeight: 44)
                }
            }
            .transition(.opacity)
        }
    }
}
