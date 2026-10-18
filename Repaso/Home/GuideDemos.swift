import SwiftUI

/// Looping animated miniatures of the app's screens for the onboarding guide: a finger taps and drags, a curved arrow
/// shows where it goes. Each demo is drawn from a time `t` in 0...1, so it loops and can be shown still.

// MARK: Timing

/// Eased progress of `t` through the span `a...b` (0 before, 1 after).
private func seg(_ t: Double, _ a: Double, _ b: Double) -> Double {
    guard b > a else { return t >= b ? 1 : 0 }
    let x = min(max((t - a) / (b - a), 0), 1)
    return x * x * (3 - 2 * x)
}

private func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
}

/// A tap lasting a short moment around `at`: 0...1 down, back to 0.
private func tap(_ t: Double, at: Double) -> Double {
    let d = abs(t - at)
    return d < 0.035 ? 1 - d / 0.035 : 0
}

/// Drives a demo: loops every `duration` seconds, or holds `still` under Reduce Motion.
struct DemoClock<Content: View>: View {
    let duration: Double
    var still = 0.98
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let s = context.date.timeIntervalSinceReferenceDate
            content(reduceMotion ? still : s.truncatingRemainder(dividingBy: duration) / duration)
        }
    }
}

// MARK: Pieces

/// A small phone screen the demos draw into (200 × 400 points).
struct DemoScreen<Content: View>: View {
    @ViewBuilder let content: () -> Content
    static var size: CGSize { CGSize(width: 200, height: 400) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg
            content()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}

/// The finger: a soft disc that presses down (`press` 0...1) with a ripple.
struct DemoFinger: View {
    let at: CGPoint
    var press: Double = 0
    var opacity: Double = 1

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.5 * press), lineWidth: 2)
                .frame(width: 30 + 30 * press, height: 30 + 30 * press)
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                .scaleEffect(1 - 0.18 * press)
        }
        .position(at)
        .opacity(opacity)
    }
}

/// A curved arrow from `from` to `to`, drawn up to `progress`.
struct DemoArrow: View {
    let from: CGPoint
    let to: CGPoint
    var bend: CGFloat = 40
    var progress: Double = 1

    var body: some View {
        let mid = CGPoint(x: (from.x + to.x) / 2 + bend, y: (from.y + to.y) / 2 - bend / 2)
        ZStack {
            Path { p in
                p.move(to: from)
                p.addQuadCurve(to: to, control: mid)
            }
            .trim(from: 0, to: progress)
            .stroke(Theme.rose, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            if progress > 0.95 {
                let angle = atan2(to.y - mid.y, to.x - mid.x)
                Path { p in
                    p.move(to: CGPoint(x: to.x - 11 * cos(angle - 0.5), y: to.y - 11 * sin(angle - 0.5)))
                    p.addLine(to: to)
                    p.addLine(to: CGPoint(x: to.x - 11 * cos(angle + 0.5), y: to.y - 11 * sin(angle + 0.5)))
                }
                .stroke(Theme.rose, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Colour blocks standing in for video frames.
private let swatches: [Color] = [
    Color(red: 0.20, green: 0.27, blue: 0.40), Color(red: 0.36, green: 0.18, blue: 0.27),
    Color(red: 0.16, green: 0.32, blue: 0.25), Color(red: 0.36, green: 0.31, blue: 0.16),
    Color(red: 0.26, green: 0.22, blue: 0.40), Color(red: 0.40, green: 0.24, blue: 0.18),
]

private func block(_ i: Int, _ w: CGFloat, _ h: CGFloat, radius: CGFloat = 8) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(swatches[i % swatches.count])
        .overlay(Image(systemName: "figure.dance").font(.system(size: min(w, h) * 0.35)).foregroundStyle(.white.opacity(0.35)))
        .frame(width: w, height: h)
}

private func pill(_ text: String, _ color: Color, fg: Color = Theme.onAccent, w: CGFloat, h: CGFloat = 30) -> some View {
    Text(text)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(fg)
        .frame(width: w, height: h)
        .background(color, in: Capsule())
}

// MARK: Demos

/// Tap Import, pick videos.
struct ImportDemo: View {
    var body: some View {
        DemoClock(duration: 4.2) { t in
            DemoScreen {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Repaso").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(0..<4, id: \.self) { block($0, 84, 74, radius: 12) }
                    }
                }
                .padding(16)
                .padding(.top, 10)
                pill("Import", Theme.accent, w: 110, h: 34).position(x: 100, y: 368)
                    .scaleEffect(1 - 0.06 * tap(t, at: 0.36))
                // The Photos picker
                let up = seg(t, 0.42, 0.56)
                VStack(spacing: 8) {
                    Capsule().fill(.white.opacity(0.3)).frame(width: 30, height: 4)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 6), count: 3), spacing: 6) {
                        ForEach(0..<6, id: \.self) { i in
                            block(i + 2, 52, 52, radius: 6).overlay(alignment: .topTrailing) {
                                let picked = (i == 0 && t > 0.66) || (i == 4 && t > 0.8)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.accent)
                                    .padding(3)
                                    .opacity(picked ? 1 : 0)
                                    .scaleEffect(picked ? 1 : 0.4)
                            }
                        }
                    }
                }
                .padding(.top, 10)
                .frame(width: 200, height: 220, alignment: .top)
                .background(Color(white: 0.13), in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                .offset(y: 400 - 220 * up)
                DemoArrow(from: CGPoint(x: 160, y: 250), to: CGPoint(x: 112, y: 350), bend: 30,
                          progress: seg(t, 0.06, 0.3))
                    .opacity(1 - seg(t, 0.4, 0.45))
                DemoFinger(at: fingerPath(t), press: max(tap(t, at: 0.36), tap(t, at: 0.66), tap(t, at: 0.8)),
                           opacity: t < 0.95 ? 1 : 0)
            }
        }
    }

    private func fingerPath(_ t: Double) -> CGPoint {
        let start = CGPoint(x: 160, y: 250), pillAt = CGPoint(x: 100, y: 368)
        let first = CGPoint(x: 41, y: 214), second = CGPoint(x: 99, y: 272)
        if t < 0.36 { return lerp(start, pillAt, seg(t, 0.06, 0.32)) }
        if t < 0.66 { return lerp(pillAt, first, seg(t, 0.5, 0.62)) }
        return lerp(first, second, seg(t, 0.68, 0.77))
    }
}

/// Mark start, Mark end, name the move.
struct CutDemo: View {
    var body: some View {
        DemoClock(duration: 5.5) { t in
            let recording = t > 0.28 && t < 0.6
            let name = "Backazouk"
            let typed = Int((Double(name.count) * seg(t, 0.7, 0.85)).rounded())
            DemoScreen {
                block(1, 200, 210, radius: 0)
                Text("00:04.2 / 00:52.4")
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .position(x: 100, y: 226)
                // Strip
                HStack(spacing: 2) {
                    ForEach(0..<8, id: \.self) { block($0, 30, 30, radius: 4) }
                }
                .offset(x: -60 * seg(t, 0.3, 0.58))
                .position(x: 140, y: 258)
                .mask(Rectangle().frame(width: 150, height: 36).position(x: 115, y: 258))
                RoundedRectangle(cornerRadius: 4).fill(Theme.rose.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.rose, lineWidth: 2))
                    .frame(width: 4 + 60 * seg(t, 0.3, 0.58), height: 34)
                    .position(x: 112 - 30 * seg(t, 0.3, 0.58), y: 258)
                    .opacity(t > 0.28 && t < 0.97 ? 1 : 0)
                Rectangle().fill(.white).frame(width: 2, height: 42).position(x: 114, y: 258)
                Circle().fill(.white.opacity(0.12)).frame(width: 30, height: 30)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(.white))
                    .position(x: 24, y: 258)
                pill(recording ? "Mark end" : "Mark start", recording ? Theme.rose : Theme.accent, w: 168, h: 36)
                    .position(x: 100, y: 312)
                    .scaleEffect(1 - 0.05 * max(tap(t, at: 0.27), tap(t, at: 0.6)))
                // Name card
                let card = seg(t, 0.62, 0.7) - seg(t, 0.92, 0.98)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    Text(String(name.prefix(typed)) + (typed < name.count ? "|" : ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rose, lineWidth: 1))
                    pill("Save clip", Theme.accent, w: 164, h: 30)
                        .scaleEffect(1 - 0.05 * tap(t, at: 0.9))
                }
                .padding(14)
                .frame(width: 192)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .position(x: 100, y: 420 - 125 * card)
                DemoArrow(from: CGPoint(x: 168, y: 150), to: CGPoint(x: 148, y: 300), bend: 26,
                          progress: seg(t, 0.04, 0.24))
                    .opacity(1 - seg(t, 0.28, 0.32))
                DemoFinger(at: finger(t), press: max(tap(t, at: 0.27), tap(t, at: 0.6), tap(t, at: 0.9)),
                           opacity: t < 0.96 ? 1 : 0)
            }
        }
    }

    private func finger(_ t: Double) -> CGPoint {
        let start = CGPoint(x: 168, y: 150), mark = CGPoint(x: 140, y: 314), save = CGPoint(x: 100, y: 365)
        if t < 0.27 { return lerp(start, mark, seg(t, 0.04, 0.24)) }
        if t < 0.62 { return mark }
        return lerp(mark, save, seg(t, 0.84, 0.88))
    }
}

/// A folder for each clip; the next clip follows.
struct FileDemo: View {
    var body: some View {
        DemoClock(duration: 4.2) { t in
            let picked = t > 0.28
            let followed = t > 0.42
            let done = seg(t, 0.74, 0.82)
            DemoScreen {
                Text("Folders").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .position(x: 52, y: 44)
                ForEach(0..<2, id: \.self) { row in
                    let set = row == 0 ? picked : followed
                    HStack(spacing: 8) {
                        block(row + 3, 40, 32, radius: 6)
                        Text(row == 0 ? "Backazouk" : "Tilted turn")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        pill(set ? "Turns" : "Choose", set ? Theme.rose : Theme.roseTint,
                             fg: set ? Theme.onAccent : Theme.rose, w: 58, h: 24)
                            .scaleEffect(set ? 1 + 0.12 * (1 - seg(t, row == 0 ? 0.28 : 0.42, row == 0 ? 0.36 : 0.5)) : 1)
                    }
                    .padding(8)
                    .frame(width: 184)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .position(x: 100, y: 100 + CGFloat(row) * 58)
                }
                pill("Finish", Theme.accent, w: 168, h: 36).position(x: 100, y: 360)
                    .scaleEffect(1 - 0.05 * tap(t, at: 0.7))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(0.4 + 0.6 * done)
                    .opacity(done)
                    .position(x: 100, y: 240)
                DemoArrow(from: CGPoint(x: 166, y: 102), to: CGPoint(x: 166, y: 156), bend: 22, progress: seg(t, 0.34, 0.44))
                    .opacity(t > 0.3 && t < 0.62 ? 1 : 0)
                DemoFinger(at: finger(t), press: max(tap(t, at: 0.27), tap(t, at: 0.7)), opacity: t < 0.9 ? 1 : 0)
            }
        }
    }

    private func finger(_ t: Double) -> CGPoint {
        let start = CGPoint(x: 110, y: 250), chip = CGPoint(x: 162, y: 100), finish = CGPoint(x: 120, y: 362)
        if t < 0.27 { return lerp(start, chip, seg(t, 0.05, 0.24)) }
        return lerp(chip, finish, seg(t, 0.5, 0.67))
    }
}

/// Tap a side for a frame, swipe up for the next clip.
struct PractiseDemo: View {
    var body: some View {
        DemoClock(duration: 4.6) { t in
            let swipe = seg(t, 0.58, 0.78)
            DemoScreen {
                block(0, 200, 400, radius: 0).offset(y: -400 * swipe)
                block(4, 200, 400, radius: 0).offset(y: 400 - 400 * swipe)
                // Frame-step marks
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(0.8 * max(tap(t, at: 0.18), 0))
                    .position(x: 172, y: 180)
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(0.8 * tap(t, at: 0.38))
                    .position(x: 28, y: 180)
                Text(t > 0.38 ? "0:04.20" : t > 0.18 ? "0:04.24" : "0:04.20")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(.black.opacity(0.45), in: Capsule())
                    .position(x: 100, y: 40)
                    .opacity(t > 0.15 && t < 0.55 ? 1 : 0)
                DemoArrow(from: CGPoint(x: 100, y: 330), to: CGPoint(x: 100, y: 150), bend: 24, progress: seg(t, 0.5, 0.62))
                    .opacity(t > 0.48 && t < 0.86 ? 1 : 0)
                DemoFinger(at: finger(t), press: max(tap(t, at: 0.18), tap(t, at: 0.38), t > 0.55 && t < 0.78 ? 0.6 : 0),
                           opacity: t < 0.88 ? 1 : 0)
            }
        }
    }

    private func finger(_ t: Double) -> CGPoint {
        let right = CGPoint(x: 172, y: 210), left = CGPoint(x: 28, y: 210)
        let low = CGPoint(x: 100, y: 330), high = CGPoint(x: 100, y: 150)
        if t < 0.18 { return lerp(CGPoint(x: 120, y: 300), right, seg(t, 0.02, 0.15)) }
        if t < 0.38 { return lerp(right, left, seg(t, 0.24, 0.35)) }
        if t < 0.55 { return lerp(left, low, seg(t, 0.42, 0.53)) }
        return lerp(low, high, seg(t, 0.58, 0.78))
    }
}

/// Hold a card, drag it to its new place.
struct ArrangeDemo: View {
    private let names = ["Backazouk", "Tilted turn", "Pasitos", "Chassé"]
    private let slots = [CGPoint(x: 56, y: 130), CGPoint(x: 144, y: 130), CGPoint(x: 56, y: 230), CGPoint(x: 144, y: 230)]

    var body: some View {
        DemoClock(duration: 4.4) { t in
            let lift = seg(t, 0.14, 0.2) - seg(t, 0.66, 0.72)
            let moved = seg(t, 0.36, 0.48)
            DemoScreen {
                Text("Turns").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .position(x: 44, y: 44)
                pill("Done", Theme.accent, w: 54, h: 24).position(x: 166, y: 44)
                // B, C, D slide back a slot as the first card passes them.
                ForEach(1..<4, id: \.self) { i in
                    card(i).position(lerp(slots[i], slots[i - 1], moved))
                        .rotationEffect(.degrees(sin((t * 40) + Double(i)) * 1.2))
                }
                card(0)
                    .scaleEffect(1 + 0.08 * lift)
                    .shadow(color: .black.opacity(0.6 * lift), radius: 12, y: 6)
                    .position(dragged(t))
                DemoArrow(from: slots[0], to: slots[3], bend: -30, progress: seg(t, 0.2, 0.62))
                    .opacity(t > 0.18 && t < 0.7 ? 0.9 : 0)
                DemoFinger(at: dragged(t), press: lift > 0.5 ? 0.7 : 0, opacity: t < 0.85 ? 1 : 0)
            }
        }
    }

    private func dragged(_ t: Double) -> CGPoint {
        if t < 0.2 { return lerp(CGPoint(x: 100, y: 330), slots[0], seg(t, 0.02, 0.13)) }
        return lerp(slots[0], slots[3], seg(t, 0.22, 0.62))
    }

    private func card(_ i: Int) -> some View {
        block(i, 80, 90, radius: 14)
            .overlay(alignment: .bottomLeading) {
                Text(names[i]).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).padding(6)
            }
    }
}
