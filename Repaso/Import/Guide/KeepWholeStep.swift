import SwiftUI
import RepasoCore

/// "Keep the full video too?": keeping it names it as one more clip; deleting it leaves just the clips.
struct KeepWholeStep: View {
    let recording: Recording
    let model: ImportGuideModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var naming = false

    var body: some View {
        VStack(spacing: 22) {
            PosterView(request: recording.thumbnailRequest, cornerRadius: 28)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(model.clips.count == 1 ? "1 clip" : "\(model.clips.count) clips") made")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Theme.accent, in: Capsule())
                        .padding(12)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, Theme.gutter)
            Text("Keep the full video too?")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 10) {
                Button { withAnimation(Theme.motion(reduceMotion)) { naming = true } } label: {
                    Text("Keep it")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                Button { env.perform { try model.dropWholeVideo() } } label: {
                    Text("Delete it")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .overlay(Capsule().strokeBorder(Theme.rose, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 12)
        }
        .padding(.top, 76)
        .overlay {
            if naming {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { withAnimation(Theme.motion(reduceMotion)) { naming = false } }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if naming {
                NameCard(title: "Name the full video",
                         initialName: ImportCoordinator.title(recordedAt: recording.recordedAt),
                         instructors: model.lastInstructors, saveTitle: "Keep it",
                         onSave: { name, instructors in
                             env.perform { try model.keepWholeVideo(name: name, instructors: instructors) }
                         },
                         onCancel: { withAnimation(Theme.motion(reduceMotion)) { naming = false } })
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
