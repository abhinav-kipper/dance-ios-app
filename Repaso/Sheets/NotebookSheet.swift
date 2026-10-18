import SwiftUI
import SwiftData
import RepasoCore

/// A clip's notes as a page from a practice notebook: warm paper, ruled lines, a pink margin and
/// serif ink. Type straight onto the page; it saves when you close it.
struct NotebookSheet: View {
    let clip: Clip
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var writing: Bool

    /// Line pitch of the ruling; the text's line height matches it so words sit on the lines.
    private let pitch: CGFloat = 32
    private let fontSize: CGFloat = 19

    private static let paper = Color(red: 0.965, green: 0.945, blue: 0.905)
    private static let ink = Color(red: 0.16, green: 0.15, blue: 0.22)
    private static let rule = Color(red: 0.55, green: 0.66, blue: 0.80).opacity(0.35)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            page
        }
        .background(Self.paper.ignoresSafeArea())
        .environment(\.colorScheme, .light)   // ink on paper, whatever the app's theme
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.Radius.sheet)
        .onAppear {
            text = clip.note ?? ""
            if text.isEmpty { writing = true }
        }
        .onDisappear(perform: save)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.rose)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Self.ink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Text(clip.name)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(Self.ink)
                .lineLimit(2)
            if let byline {
                Text(byline)
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(Self.ink.opacity(0.6))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    /// Ruled paper with a margin line; the note is typed right onto it.
    private var page: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                var y = pitch
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Self.rule))
                    y += pitch
                }
                context.fill(Path(CGRect(x: 40, y: 0, width: 1.5, height: size.height)),
                             with: .color(Theme.rose.opacity(0.55)))
            }
            .accessibilityHidden(true)
            if text.isEmpty && !writing {
                Text("Counts, hand placement, where the weight goes, how it should feel…")
                    .font(.system(size: fontSize, design: .serif).italic())
                    .foregroundStyle(Self.ink.opacity(0.35))
                    .padding(.leading, 52)
                    .padding(.trailing, 24)
                    .padding(.top, pitch - fontSize - 6)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: fontSize, design: .serif))
                .foregroundStyle(Self.ink)
                .lineSpacing(pitch - fontSize * 1.2)
                .scrollContentBackground(.hidden)
                .focused($writing)
                .padding(.leading, 47)
                .padding(.trailing, 20)
                .padding(.top, pitch - fontSize - 12)
                .onChange(of: text) { _, new in
                    if new.count > LibraryService.noteLimit { text = String(new.prefix(LibraryService.noteLimit)) }
                }
                .accessibilityLabel("Notes")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { writing = true }
    }

    /// "Ataca & Alemana · 10 Oct 2026"
    private var byline: String? {
        var parts: [String] = []
        if !clip.instructors.isEmpty { parts.append(clip.instructors.joined(separator: " & ")) }
        if let recorded = clip.recording?.recordedAt { parts.append(recorded.formatted(date: .abbreviated, time: .omitted)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func save() {
        guard text != (clip.note ?? "") else { return }
        let lib = env.library(ctx)
        let clip = clip
        let text = text
        env.perform { try lib.setNote(clip, text) }
    }
}
