import SwiftUI
import SwiftData
import RepasoCore

/// The import guide: one video at a time through Make clips? → Cut and name → Keep the full video? → File, with
/// Continue later always at hand. Unfinished videos wait in Unsorted.
struct ImportGuideView: View {
    let model: ImportGuideModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var naming = false
    @State private var offeringPhotos = false
    @State private var checked = 0

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            content
                .id(stepKey)
                .transition(reduceMotion ? .opacity : .push(from: .trailing))
            topBar
        }
        .animation(Theme.motion(reduceMotion), value: stepKey)
        .overlay {
            if naming {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { withAnimation(Theme.motion(reduceMotion)) { naming = false } }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if naming, let recording = model.recording {
                NameCard(title: "Name it", initialName: ImportCoordinator.title(recordedAt: recording.recordedAt),
                         instructors: model.lastInstructors,
                         onSave: { name, instructors in
                             env.perform { try model.useWholeVideo(name: name, instructors: instructors) }
                             naming = false
                         },
                         onCancel: { withAnimation(Theme.motion(reduceMotion)) { naming = false } })
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: model.isClosed) { _, closed in if closed { close() } }
        .task(id: failureKey) {
            // A video that couldn't be copied is skipped, with the reason.
            guard case .failed(let message) = model.current, !message.isEmpty else { return }
            env.showToast(message, seconds: 3)
            model.skipCurrent()
        }
        .confirmationDialog(PhotosCleanupText.prompt(count: model.finishedAssetIDs.count), isPresented: $offeringPhotos,
                            titleVisibility: .visible) {
            Button("Delete from Photos", role: .destructive) {
                let ids = model.finishedAssetIDs
                let env = env
                Task {
                    let outcome = await PhotosCleaner.delete(ids)
                    env.showToast(Self.photosText(outcome), seconds: 2.5)
                }
            }
            Button("Keep in Photos", role: .cancel) {}
        } message: {
            Text(PhotosCleanupText.detail)
        }
        // However the Photos question ends (either button, or dismissed), the guide closes.
        .onChange(of: offeringPhotos) { _, showing in if !showing { dismiss() } }
        .sensoryFeedback(.success, trigger: checked)
        .toastHost(env)
    }

    // MARK: Steps

    private var stepKey: String { "\(model.position.index)-\(String(describing: model.step))-\(model.recording != nil)" }

    private var failureKey: String {
        if case .failed(let m) = model.current { return "\(model.position.index)-\(m)" }
        return ""
    }

    @ViewBuilder
    private var content: some View {
        switch model.current {
        case .copying(let progress, let poster):
            copying(progress, poster: poster)
        case .failed:
            Color.clear
        case .ready(let recording):
            switch model.step {
            case .trimChoice:
                TrimChoiceStep(recording: recording, onMakeClips: model.startCutting,
                               onUseWhole: { withAnimation(Theme.motion(reduceMotion)) { naming = true } })
                    .padding(.top, 64)
            case .cut:
                CutStep(recording: recording, model: model)
            case .keepWhole:
                KeepWholeStep(recording: recording, model: model)
            case .file:
                FileStep(model: model)
            }
        }
    }

    private func copying(_ progress: Double, poster: ThumbnailRequest?) -> some View {
        VStack(spacing: 18) {
            PosterView(request: poster, cornerRadius: 28)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 12)
            ProgressView(value: progress)
                .tint(Theme.rose)
                .padding(.horizontal, 60)
            Text("Importing…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 40)
        }
        .padding(.top, 64)
        .accessibilityElement(children: .combine)
    }

    // MARK: Bar

    private var topBar: some View {
        HStack {
            continueLater
            Spacer()
            trailingAction
        }
        .overlay { progress }   // centred on the screen, whatever sits either side
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var continueLater: some View {
        Button("Continue later") { model.continueLater() }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.rose)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .controlGlass(in: Capsule(), tint: Theme.overVideoTint)
            .frame(minHeight: 44)
            .disabled(model.isFinishing)   // Finish is filing this video; leaving now would still file it
            .opacity(model.isFinishing ? 0.4 : 1)
    }

    private var progress: some View {
        VStack(spacing: 5) {
            StepDots(steps: model.visibleSteps, current: model.step)
            if model.position.count > 1 {
                Text("Video \(model.position.index + 1) of \(model.position.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(Theme.overVideoTint), in: Capsule())   // readable over a bright video
    }

    /// The step's own action: Done in the cutter once a clip is made.
    @ViewBuilder
    private var trailingAction: some View {
        if model.step == .cut, model.recording != nil, !model.clips.isEmpty {
            Button("Done") { model.doneCutting() }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Theme.accent, in: Capsule())
                .buttonStyle(PressableButtonStyle())
                .frame(minHeight: 44)
                .transition(.scale.combined(with: .opacity))
        } else {
            Color.clear.frame(width: 1, height: 44)
        }
    }

    // MARK: Closing

    private func close() {
        if model.finishedClips > 0 {
            checked += 1
            let text = model.finishedVideos > 1
                ? "\(model.finishedClips) clips from \(model.finishedVideos) videos"
                : (model.finishedClips == 1 ? "1 clip saved" : "\(model.finishedClips) clips saved")
            if let folder = model.firstFolder, folder.modelContext != nil, !folder.isDeleted {
                let route = (folder.ancestors + [folder]).map { Route.folder($0.id) }
                let env = env
                env.showToast(text, actionTitle: "Go to", undo: { env.pendingRoute = route }, seconds: 5)
            } else {
                env.showToast(text, seconds: 3)
            }
        }
        if model.finishedAssetIDs.isEmpty { dismiss() } else { offeringPhotos = true }
    }

    private static func photosText(_ outcome: PhotosCleaner.Outcome) -> String {
        switch outcome {
        case .removed: PhotosCleanupText.removed
        case .kept: PhotosCleanupText.kept
        case .needsAccess: PhotosCleanupText.needsAccess
        case .failed: PhotosCleanupText.failed
        }
    }
}
