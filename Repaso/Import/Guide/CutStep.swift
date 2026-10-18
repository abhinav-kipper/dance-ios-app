import SwiftUI
import RepasoCore

/// The guide's cutter: Mark start → Mark end, then the name card springs up for that clip.
struct CutStep: View {
    let recording: Recording
    let model: ImportGuideModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The range just marked, waiting for its name.
    @State private var marked: ClosedRange<Double>?
    @State private var saved = 0

    var body: some View {
        CutView(recording: recording, onClipMarked: { range in
            withAnimation(Theme.motion(reduceMotion)) { marked = range }
        }, onDone: model.doneCutting)
        .overlay {
            if marked != nil {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { cancel() }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let range = marked {
                NameCard(title: "Name this clip", instructors: model.lastInstructors,
                         onSave: { name, instructors in save(range, name: name, instructors: instructors) },
                         onCancel: cancel)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    private func save(_ range: ClosedRange<Double>, name: String, instructors: [String]) {
        env.perform {
            try withAnimation(Theme.motion(reduceMotion)) {
                _ = try model.saveClip(name: name, instructors: instructors, range: range)
                marked = nil
            }
        }
        saved += 1
    }

    private func cancel() {
        withAnimation(Theme.motion(reduceMotion)) { marked = nil }
    }
}
