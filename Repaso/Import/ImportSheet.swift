import SwiftUI
import SwiftData
import RepasoCore

struct ImportSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var allOriginals: [Original]
    @FocusState private var focus: TagField?
    /// The video whose own name and tags are open for editing.
    @State private var editingID: UUID?

    private enum TagField: Hashable {
        case instructors, event
        case title(UUID), ownInstructors(UUID), ownEvent(UUID)
    }

    private var importer: ImportCoordinator { env.importer }

    var body: some View {
        @Bindable var importer = importer
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(importer.items.count == 1 ? "Importing 1 video to \(importer.destinationName)"
                     : "Importing \(importer.items.count) videos to \(importer.destinationName)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(importer.overallProgress * 100))%")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.top, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(importer.items) { item in
                        VStack(spacing: 8) {
                            row(item)
                            if editingID == item.id { ownFields(item) }
                        }
                        .animation(Theme.spring, value: editingID)
                    }
                    tagFields(instructors: $importer.instructorsText, event: $importer.eventText)
                        .padding(.top, 8)
                    photosSection
                        .padding(.top, 8)
                        .animation(Theme.spring, value: importer.photosPromptCount)
                        .animation(Theme.spring, value: importer.photosResult)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            if !importer.isRunning, let route = importer.finishedRoute {
                Button {
                    env.pendingRoute = route
                    dismiss()
                } label: {
                    Label("Go to \(importer.destinationName)", systemImage: "arrow.right.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PressableButtonStyle())
            }
            PrimarySheetButton(title: importer.isRunning ? "Hide" : "Done") { dismiss() }
                .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet()
        .onChange(of: focus) { old, _ in
            if old != nil { importer.applyTags(context: ctx, env: env) }
        }
        .onDisappear { importer.applyTags(context: ctx, env: env) }
    }

    private func row(_ item: ImportCoordinator.Item) -> some View {
        HStack(spacing: 12) {
            PosterView(request: item.poster, cornerRadius: 8)
                .frame(width: 46, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(detail(item))
                    .font(.system(size: 12))
                    .foregroundStyle(item.state.isFailure ? Theme.rose : Theme.textSecondary)
                if let own = ownLine(item) {
                    Text(own)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .lineLimit(1)
                }
            }
            Spacer()
            if importer.items.count > 1 {
                Button {
                    withAnimation(Theme.spring) { editingID = editingID == item.id ? nil : item.id }
                    importer.applyTags(context: ctx, env: env)
                } label: {
                    Image(systemName: editingID == item.id ? "chevron.up" : "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .frame(width: 44, height: 44)
                        .background(Theme.roseTint, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(editingID == item.id ? "Done with \(item.name)" : "Name and tag \(item.name)")
            }
            switch item.state {
            case .failed:
                Button {
                    importer.retry(item.id, context: ctx, env: env)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .frame(width: 44, height: 44)
                        .background(Theme.roseTint, in: Circle())
                }
                .accessibilityLabel("Retry import")
            case .copying(let p):
                ProgressRing(progress: p, done: false)
            case .waiting:
                ProgressRing(progress: 0, done: false)
            case .done:
                ProgressRing(progress: 1, done: true)
            }
        }
        .padding(10)
        .cardGlass(radius: 18)
    }

    private func detail(_ item: ImportCoordinator.Item) -> String {
        if case .failed(let message) = item.state { return message }
        var parts: [String] = []
        if let d = item.duration { parts.append(TimeFormat.duration(d)) }
        if let s = item.size { parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)) }
        return parts.isEmpty ? "Waiting…" : parts.joined(separator: " · ")
    }

    /// "Kike & Nahir · Berlin": what this video gets instead of the shared tags.
    private func ownLine(_ item: ImportCoordinator.Item) -> String? {
        let tags = [TagText.instructors(from: item.ownInstructors).joined(separator: " & "),
                    item.ownEvent.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }
        return tags.isEmpty ? nil : tags.joined(separator: " · ")
    }

    // MARK: Per-video fields

    /// One video's own name and tags; empty fields show (and keep) the shared value.
    private func ownFields(_ item: ImportCoordinator.Item) -> some View {
        let instructors = own(item.id, \.ownInstructors)
        return VStack(alignment: .leading, spacing: 12) {
            tagField("Name", prompt: item.name, text: own(item.id, \.ownTitle), field: .title(item.id), capitalization: .sentences)
            tagField("Instructor(s)", prompt: sharedPrompt(importer.instructorsText, fallback: "Who taught it"),
                     text: instructors, field: .ownInstructors(item.id))
            if focus == .ownInstructors(item.id) {
                suggestionChips(TagSuggestions.instructors(
                    for: TagText.lastToken(of: instructors.wrappedValue),
                    excluding: TagText.instructors(from: instructors.wrappedValue),
                    in: allOriginals)) { name in
                    instructors.wrappedValue = TagText.completing(instructors.wrappedValue, with: name)
                }
            }
            tagField("Class or event", prompt: sharedPrompt(importer.eventText, fallback: "Where it was"),
                     text: own(item.id, \.ownEvent), field: .ownEvent(item.id))
        }
        .padding(12)
        .background(Theme.roseTint.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func sharedPrompt(_ shared: String, fallback: String) -> String {
        let trimmed = shared.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallback : "Same as all: \(trimmed)"
    }

    private func own(_ id: UUID, _ key: WritableKeyPath<ImportCoordinator.Item, String>) -> Binding<String> {
        Binding(get: { importer.items.first { $0.id == id }?[keyPath: key] ?? "" },
                set: { value in importer.update(id) { $0[keyPath: key] = value } })
    }

    // MARK: Tags

    private func tagFields(instructors: Binding<String>, event: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if importer.items.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("For all videos").sectionLabelStyle()
                    Text("Tap ✎ on a video to give it its own name, teacher or class.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if let line = importer.recordedLine {
                Label(line, systemImage: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            tagField("Instructor(s)", prompt: "Who taught it", text: instructors, field: .instructors)
            if focus == .instructors {
                suggestionChips(TagSuggestions.instructors(
                    for: TagText.lastToken(of: instructors.wrappedValue),
                    excluding: TagText.instructors(from: instructors.wrappedValue),
                    in: allOriginals)) { name in
                    instructors.wrappedValue = TagText.completing(instructors.wrappedValue, with: name)
                }
            }
            tagField("Class or event", prompt: "Where it was", text: event, field: .event)
            if focus == .event {
                suggestionChips(TagSuggestions.events(for: event.wrappedValue, in: allOriginals)) { value in
                    event.wrappedValue = value
                    focus = nil
                }
            }
        }
        .animation(Theme.spring, value: focus)
    }

    private func tagField(_ label: String, prompt: String, text: Binding<String>, field: TagField,
                          capitalization: TextInputAutocapitalization = .words) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            TextField(prompt, text: text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focus, equals: field)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .controlGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(label)
                .onSubmit { focus = nil }
        }
    }

    @ViewBuilder
    private func suggestionChips(_ values: [String], pick: @escaping (String) -> Void) -> some View {
        if !values.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        Button { pick(value) } label: {
                            Text(value)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.rose)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Theme.roseTint, in: Capsule())
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("Use \(value)")
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Delete from Photos

    @ViewBuilder
    private var photosSection: some View {
        if let result = importer.photosResult {
            Text(result)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .offset(y: 14)))
        } else if let count = importer.photosPromptCount {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .frame(width: 36, height: 36)
                        .background(Theme.roseTint, in: Circle())
                    Text(PhotosCleanupText.prompt(count: count))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(PhotosCleanupText.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    Button { importer.keepInPhotos() } label: {
                        Text("Keep")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    Button {
                        Task { await importer.deleteFromPhotos() }
                    } label: {
                        Text("Delete")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.rose, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(importer.isDeletingFromPhotos)
                }
            }
            .padding(14)
            .background(Theme.roseTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.rose.opacity(0.35), lineWidth: 1))
            .transition(.opacity.combined(with: .offset(y: 14)))
        }
    }
}

private extension ImportCoordinator.Item.State {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
