import SwiftUI
import RepasoCore

/// The whole video as a strip that scrolls under a fixed playhead in the middle, like Photos: scroll to move through
/// the video (momentum included), pinch to zoom, tap a spot to bring it to the playhead. Clip ranges, the recording
/// range and the trim handles ride on the strip.
struct Filmstrip: View {
    @Bindable var model: CutModel
    let clips: [Clip]
    let onTrimEnd: (Clip, ClosedRange<Double>) -> Void

    private let height: CGFloat = 56
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var width: CGFloat = 0
    /// A finger (or its momentum) is moving the strip: the video follows the strip.
    @State private var userScrolling = false
    @State private var pinchBase: Double?
    private var selected: Clip? { clips.first { $0.id == model.selectedID } }

    private var pps: Double { CutStrip.pointsPerSecond(visible: model.visibleSeconds, width: width) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                strip
                playhead
            }
            .frame(height: height + 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                width = new
                scrollAfterLayout()
            }
            labels
        }
    }

    // MARK: Strip

    private var strip: some View {
        let pps = pps
        let contentWidth = CutStrip.contentWidth(duration: model.duration, pointsPerSecond: pps, visibleWidth: width)
        return ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .leading) {
                tiles(pps: pps)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.leading, width / 2)
                ForEach(clips.filter { $0.id != model.selectedID }) { clip in
                    range(from: x(clip.start), to: x(clip.end),
                          fill: Theme.accent.opacity(0.22), border: Theme.accent.opacity(0.6), lineWidth: 2)
                }
                if let start = model.session.markStart {
                    range(from: x(min(start, model.time)), to: x(max(start, model.time)),
                          fill: Theme.rose.opacity(0.28), border: Theme.rose, lineWidth: 3)
                }
                if let selected {
                    let r = model.draftRange ?? selected.start...selected.end
                    range(from: x(r.lowerBound), to: x(r.upperBound),
                          fill: Theme.accent.opacity(0.10), border: Theme.accent, lineWidth: 3)
                    handle(at: x(r.lowerBound), isStart: true, clip: selected, range: r)
                    handle(at: x(r.upperBound), isStart: false, clip: selected, range: r)
                }
            }
            .frame(width: max(contentWidth, width), height: height, alignment: .leading)
            .contentShape(Rectangle())
            .coordinateSpace(.named("strip"))
            .onTapGesture(coordinateSpace: .named("strip")) { location in
                model.seek(time(atContentX: location.x))   // the strip follows the new time to the playhead
            }
        }
        .scrollPosition($position)
        .scrollDisabled(model.draftRange != nil)   // trimming: the handle moves, not the strip
        .onScrollPhaseChange { _, phase in
            guard pinchBase == nil else { return }
            switch phase {
            case .tracking, .interacting, .decelerating:
                if !userScrolling {
                    userScrolling = true
                    model.beginScrub()
                }
            case .idle, .animating:
                if userScrolling {
                    userScrolling = false
                    model.seek(model.time)   // settle on the exact frame
                    model.endScrub()
                }
            }
        }
        .onScrollGeometryChange(for: Double.self) { $0.contentOffset.x } action: { _, x in
            guard userScrolling, pinchBase == nil else { return }
            model.seek(CutStrip.time(forOffset: x, pointsPerSecond: pps, duration: model.duration), precise: false)
        }
        .onChange(of: model.time) { _, _ in
            if !userScrolling && pinchBase == nil { scrollToTime() }
        }
        .onChange(of: model.visibleSeconds) { _, _ in scrollAfterLayout() }
        .simultaneousGesture(pinch)
    }

    private func tiles(pps: Double) -> some View {
        let span = CutStrip.tileSpan(pointsPerSecond: pps)
        let count = CutStrip.tileCount(duration: model.duration, span: span)
        let tileWidth = span * pps
        let lastWidth = max(1, (model.duration - span * Double(max(0, count - 1))) * pps)
        return LazyHStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                StripTile(model: model, span: span, index: i)
                    .frame(width: i == count - 1 ? lastWidth : tileWidth, height: height)
            }
        }
        .frame(height: height)
    }

    /// Pinch the strip to see more or less of the video at once; the time under the playhead stays put.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBase == nil { pinchBase = model.visibleSeconds }
                guard let base = pinchBase, value.magnification > 0 else { return }
                model.visibleSeconds = CutStrip.clampVisible(base / value.magnification, duration: model.duration)
            }
            .onEnded { _ in
                pinchBase = nil
                scrollAfterLayout()
            }
    }

    // MARK: Positions

    /// Content x of time `t` (the strip is padded by half its width on each side).
    private func x(_ t: Double) -> CGFloat {
        let v = CGFloat(Double(width) / 2 + t * pps)
        return v.isFinite ? v : 0   // never hand a non-finite position to layout
    }

    private func time(atContentX x: CGFloat) -> Double {
        CutStrip.time(forOffset: Double(x - width / 2), pointsPerSecond: pps, duration: model.duration)
    }

    private func scrollToTime() {
        let x = CutStrip.offset(for: model.time, pointsPerSecond: pps, duration: model.duration)
        guard x.isFinite else { return }
        position.scrollTo(x: x)
    }

    /// After a zoom or resize the strip's width changes; scroll once the new width is laid out.
    private func scrollAfterLayout() {
        Task { @MainActor in scrollToTime() }
    }

    // MARK: Layers

    private var playhead: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Theme.textPrimary)
            .frame(width: 3, height: height + 12)
            .shadow(color: .white.opacity(0.6), radius: 4)
            .frame(width: 44)
            .contentShape(.accessibility, Rectangle())   // a 44pt target for VoiceOver, though the line is 3pt
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playhead")
            .accessibilityValue("\(TimeFormat.precise(model.time)) of \(TimeFormat.precise(model.duration))")
            .accessibilityHint("Swipe up or down to move one second")
            .accessibilityAdjustableAction { direction in
                model.seek(model.time + (direction == .increment ? 1 : -1))
            }
    }

    private var labels: some View {
        let half = model.visibleSeconds / 2
        return HStack {
            Text(TimeFormat.range(max(0, model.time - half)))
            Spacer()
            Text(selected == nil ? "Scroll to move · pinch to zoom" : "Drag the handles to trim")
            Spacer()
            Text(TimeFormat.range(min(model.duration, model.time + half)))
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
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

    private func handle(at x: CGFloat, isStart: Bool, clip: Clip, range: ClosedRange<Double>) -> some View {
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
                        model.beginScrub()
                        let t = time(atContentX: value.location.x)
                        let current = model.draftRange ?? range
                        let next = isStart ? CutSession.trimStart(current, to: t)
                                           : CutSession.trimEnd(current, to: t, duration: model.duration)
                        model.draftRange = next
                        model.seek(isStart ? next.lowerBound : next.upperBound, precise: false)
                    }
                    .onEnded { _ in
                        if let r = model.draftRange { onTrimEnd(clip, r) }
                        model.draftRange = nil
                        model.endScrub()
                        scrollToTime()
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
}

/// One thumbnail of the strip, loaded when it scrolls into view.
private struct StripTile: View {
    let model: CutModel
    let span: Double
    let index: Int
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .overlay {
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            }
            .clipped()
            .task(id: "\(span)-\(index)") { image = await model.tileImage(span: span, index: index) }
    }
}
