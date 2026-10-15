import SwiftUI
import RepasoCore

/// Photos-style strip over a 40s window: clip ranges, recording range, trim handles, playhead.
struct Filmstrip: View {
    @Bindable var model: CutModel
    let clips: [Clip]
    let onTrimEnd: (Clip, ClosedRange<Double>) -> Void

    private let height: CGFloat = 56
    private var selected: Clip? { clips.first { $0.id == model.selectedID } }

    var body: some View {
        let ws = model.windowStart(selected: selected)
        let wl = CutSession.windowLength(for: model.duration)
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                let x = { (t: Double) in CGFloat(CutSession.x(for: t, windowStart: ws, windowLength: wl, width: width)) }
                let clampX = { (t: Double) in min(max(0, x(t)), width) }
                ZStack(alignment: .leading) {
                    frames
                    ForEach(clips.filter { $0.id != model.selectedID && $0.end > ws && $0.start < ws + wl }) { clip in
                        range(from: clampX(clip.start), to: clampX(clip.end),
                              fill: Theme.accent.opacity(0.22), border: Theme.accent.opacity(0.6), lineWidth: 2)
                    }
                    if let start = model.session.markStart {
                        range(from: clampX(min(start, model.time)), to: clampX(max(start, model.time)),
                              fill: Theme.rose.opacity(0.28), border: Theme.rose, lineWidth: 3)
                    }
                    if let selected {
                        let r = model.draftRange ?? selected.start...selected.end
                        range(from: x(r.lowerBound), to: x(r.upperBound),
                              fill: Theme.accent.opacity(0.10), border: Theme.accent, lineWidth: 3)
                        handle(at: x(r.lowerBound), isStart: true, clip: selected, range: r, ws: ws, wl: wl, width: width)
                        handle(at: x(r.upperBound), isStart: false, clip: selected, range: r, ws: ws, wl: wl, width: width)
                    }
                    playhead(at: x(model.time), width: width)
                }
                .frame(width: width, height: height, alignment: .leading)
                .contentShape(Rectangle())
                .coordinateSpace(.named("strip"))
                .gesture(scrub(ws: ws, wl: wl, width: width))
            }
            .frame(height: height)
            .task(id: Int((ws * 10).rounded())) { await model.loadFrames(windowStart: ws) }

            HStack {
                Text(TimeFormat.range(ws))
                Spacer()
                Text(selected == nil ? "Drag to scrub" : "Drag the handles to trim")
                Spacer()
                Text(TimeFormat.range(ws + wl))
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Layers

    private var frames: some View {
        HStack(spacing: 0) {
            ForEach(0..<CutModel.frameCount, id: \.self) { i in
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .overlay {
                        if let image = model.frames[i] {
                            Image(decorative: image, scale: 1).resizable().scaledToFill()
                        }
                    }
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private func range(from left: CGFloat, to right: CGFloat, fill: Color, border: Color, lineWidth: CGFloat) -> some View {
        let w = max(2, right - left)
        return ZStack {
            Rectangle().fill(fill)
            VStack {
                Rectangle().fill(border).frame(height: lineWidth)
                Spacer()
                Rectangle().fill(border).frame(height: lineWidth)
            }
        }
        .frame(width: w, height: height)
        .offset(x: left)
        .allowsHitTesting(false)
    }

    private func playhead(at x: CGFloat, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Theme.textPrimary)
            .frame(width: 3, height: height + 12)
            .shadow(color: .white.opacity(0.6), radius: 4)
            .offset(x: x - 1.5)
            .opacity(x < -2 || x > width + 2 ? 0 : 1)
            .allowsHitTesting(false)
    }

    private func handle(at x: CGFloat, isStart: Bool, clip: Clip, range: ClosedRange<Double>,
                        ws: Double, wl: Double, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Theme.accent)
            .frame(width: 16, height: height)
            .overlay(
                Image(systemName: isStart ? "chevron.left" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.onAccent))
            .frame(width: 44, height: height)   // generous hit area
            .contentShape(Rectangle())
            .offset(x: x - 22)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
                    .onChanged { value in
                        if model.frozenWindowStart == nil {
                            model.frozenWindowStart = ws
                            model.beginScrub()
                        }
                        let t = CutSession.time(forX: value.location.x, windowStart: ws, windowLength: wl, width: width)
                        let current = model.draftRange ?? range
                        let next = isStart ? CutSession.trimStart(current, to: t)
                                           : CutSession.trimEnd(current, to: t, duration: model.duration)
                        model.draftRange = next
                        model.seek(isStart ? next.lowerBound : next.upperBound, precise: false)
                    }
                    .onEnded { _ in
                        if let r = model.draftRange { onTrimEnd(clip, r) }
                        model.draftRange = nil
                        model.frozenWindowStart = nil
                        model.endScrub()
                    })
            .accessibilityElement()
            .accessibilityLabel(isStart ? "Clip start" : "Clip end")
            .accessibilityValue(TimeFormat.precise(isStart ? range.lowerBound : range.upperBound))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.1 : -0.1
                let next = isStart ? CutSession.trimStart(range, to: range.lowerBound + step)
                                   : CutSession.trimEnd(range, to: range.upperBound + step, duration: model.duration)
                onTrimEnd(clip, next)
            }
    }

    private func scrub(ws: Double, wl: Double, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
            .onChanged { value in
                if model.frozenWindowStart == nil {
                    model.frozenWindowStart = ws
                    model.beginScrub()
                }
                let t = CutSession.time(forX: value.location.x, windowStart: ws, windowLength: wl, width: width)
                model.seek(t, precise: false)
            }
            .onEnded { value in
                let t = CutSession.time(forX: value.location.x, windowStart: ws, windowLength: wl, width: width)
                model.seek(t)
                model.frozenWindowStart = nil
                model.endScrub()
            }
    }
}
