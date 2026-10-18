import SwiftUI
import RepasoCore

/// The guide's last step: a folder for each clip, then Finish.
struct FileStep: View {
    let model: ImportGuideModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The clip whose folder is being chosen.
    @State private var choosing: Clip?
    @State private var pulses: [UUID: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("File them")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Pick a folder for each clip.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.gutter)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { i, clip in
                        row(clip).riseIn(i)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
            }
            finishButton
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
        }
        .padding(.top, 76)
        .sheet(item: $choosing) { clip in
            FolderSearchPicker(selected: model.folderChoices[clip.id]) { folder in
                model.setFolder(folder, for: clip.id)
                if !reduceMotion { pulses[clip.id, default: 0] += 1 }
            }
        }
    }

    private func row(_ clip: Clip) -> some View {
        let folder = model.folderChoices[clip.id]
        return HStack(spacing: 12) {
            PosterView(request: clip.thumbnailRequest, cornerRadius: 12)
                .frame(width: 72, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(clip.coversWholeRecording ? "Full video · \(TimeFormat.duration(clip.length))"
                     : TimeFormat.duration(clip.length))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button { choosing = clip } label: {
                Label(folder?.name ?? "Choose", systemImage: folder == nil ? "folder.badge.plus" : "folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(folder == nil ? Theme.rose : Theme.onAccent)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(folder == nil ? Theme.roseTint : Theme.rose, in: Capsule())
                    .frame(maxWidth: 150, alignment: .trailing)
                    .keyframeAnimator(initialValue: 1.0, trigger: pulses[clip.id, default: 0]) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.12, duration: 0.15)
                        SpringKeyframe(1.0, duration: 0.3)
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .frame(minHeight: 44)
            .accessibilityLabel(folder.map { "Folder for \(clip.name): \($0.name)" } ?? "Choose a folder for \(clip.name)")
        }
        .padding(10)
        .cardGlass(radius: Theme.Radius.listCard)
    }

    private var finishButton: some View {
        VStack(spacing: 10) {
            if let progress = model.exportProgress {
                VStack(spacing: 6) {
                    ProgressView(value: progress).tint(Theme.accent)
                    Text("Saving clips as their own videos…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .transition(.opacity)
            }
            Button {
                Task {
                    do { try await model.finish() } catch {
                        env.showToast("Couldn't save the clips. Nothing was filed.", seconds: 3)
                    }
                }
            } label: {
                Text("Finish")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.accent.opacity(model.canFinish ? 1 : 0.35), in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!model.canFinish)
            .accessibilityHint(model.canFinish ? "" : "Choose a folder for every clip first")
        }
        .animation(Theme.motion(reduceMotion), value: model.exportProgress != nil)
    }
}
