#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Rest counting down on the Lock Screen, in StandBy and in the Dynamic Island, so the phone can stay
/// in a pocket between sets: the countdown as the hero, the set that comes next beside it, and the
/// rest draining on the ruler (between rests, the session's progress).
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLockScreen(title: context.attributes.title, state: context.state)
                .activityBackgroundTint(Ink.ground)
                .activitySystemActionForegroundColor(Ink.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.restEndsAt == nil ? "Up now" : "Rest")
                        .eyebrow()
                        .foregroundStyle(Ink.Island.accent)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.title)
                        .eyebrow()
                        .foregroundStyle(Ink.Island.text3)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandSession(state: context.state)
                }
            } compactLeading: {
                SessionRuler(state: context.state, color: Ink.Island.accent, track: Ink.Island.track, height: 8, divisions: 0)
                    .frame(width: 34)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                Image(systemName: context.state.restEndsAt == nil ? "dumbbell.fill" : "timer")
                    .foregroundStyle(Ink.Island.accent)
            }
            .widgetURL(URL(string: "lifttrack://session"))
            .keylineTint(Ink.Island.accent)
        }
    }
}

/// The activity's set split for setting: "Set 3 of 3 · 70 kg × 7" is the label "Set 3 of 3" and the
/// target "70 kg × 7" (`LiveActivityBridge.content` joins them).
struct SetLine {
    let label: String
    let target: String?

    init(_ detail: String) {
        let parts = detail.components(separatedBy: " · ")
        label = parts.first ?? ""
        target = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : nil
    }
}

/// A target split for setting large: "70 kg × 7" is the load "70" and the reps "7" (the unit goes, as
/// the design's StandBy has it); a target without a "×" ("45 s", "12 reps") is the load alone.
struct TargetParts {
    let load: String
    let reps: String?

    init(_ target: String) {
        let sides = target.components(separatedBy: " × ")
        reps = sides.count > 1 ? sides.dropFirst().joined(separator: " × ") : nil
        let words = sides[0].split(separator: " ")
        load = reps != nil && words.count == 2 && ["kg", "lb"].contains(words[1]) ? String(words[0]) : sides[0]
    }
}

/// The rest left, counting down by itself.
struct RestCountdown: View {
    let end: Date
    let size: CGFloat
    /// The width it's given, as a share of its size: a timer's text is laid out for its widest value.
    var width: CGFloat = 2.3
    /// Whether it may shrink to that width. A timer's widest value is wider than a rest's "1:42", so
    /// where every point counts (StandBy) it keeps its size and runs past the width into the gap.
    var shrinks = true
    var tightness: CGFloat = 0.05

    var body: some View {
        Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
            .numeral(size, weight: .heavy, tightness: tightness)
            .fixedSize(horizontal: !shrinks, vertical: false)
            .frame(width: size * width, alignment: .leading)
    }
}

/// The rest draining toward its end by itself between updates (the system's timer bar, made as tall
/// as a ruler and cut into tenths), or, between rests and from an app that didn't send when the rest
/// began, the session's progress.
struct SessionRuler: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let state: SessionActivityAttributes.ContentState
    var color: Color = .accentColor
    var track: Color = Ink.track
    var height: CGFloat = 12
    var divisions = 10

    var body: some View {
        if let end = state.restEndsAt, let start = state.restStartedAt, start < end {
            GeometryReader { geometry in
                ZStack {
                    Rectangle().fill(renderingMode == .fullColor ? track : Color.primary.opacity(0.25))
                    ProgressView(timerInterval: start...end, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(color)
                    // The bar is a few points tall; stretched, its track and rounded ends fall outside the mask.
                    .scaleEffect(x: 1.04, y: height / 2, anchor: .center)
                    .widgetAccentable()
                }
                .mask { TickedOutline(size: geometry.size, divisions: height >= 8 ? divisions : 0) }
            }
            .frame(height: height)
            .accessibilityHidden(true)
        } else {
            Ruler(value: state.progress, color: color, height: height, divisions: divisions, track: track)
        }
    }
}

extension SessionActivityAttributes.ContentState {
    /// The rest's length, "2:30", when the activity says when it began.
    var restLength: String? {
        guard let end = restEndsAt, let start = restStartedAt, start < end else { return nil }
        let seconds = Int(end.timeIntervalSince(start).rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    var percentDone: Int { Int((min(1, max(0, progress)) * 100).rounded()) }

    /// Under the ruler: "Of 2:30" and "Session 45% done" while it's the rest's; "Session" and "45% done"
    /// while it's the session's.
    var rulerCaptions: (String, String) {
        if let length = restLength { return ("Of \(length)", "Session \(percentDone)% done") }
        return ("Session", "\(percentDone)% done")
    }
}

/// The Lock Screen's banner (resting, the countdown with the next set beside it; between rests, the
/// exercise and the set to do), and StandBy's full screen.
struct SessionLockScreen: View {
    @Environment(\.isActivityFullscreen) private var fullscreen
    let title: String
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        if fullscreen {
            SessionStandBy(title: title, state: state)
        } else {
            SessionBanner(title: title, state: state)
        }
    }
}

/// "Rest · Barbell Bench Press", "Up now · Set 2 of 3", or "Up now" when only finishing is left.
private func sessionEyebrow(_ state: SessionActivityAttributes.ContentState) -> String {
    if state.restEndsAt != nil { return "Rest · \(state.exercise)" }
    let label = SetLine(state.detail).label
    return label.isEmpty ? "Up now" : "Up now · \(label)"
}

struct SessionBanner: View {
    let title: String
    let state: SessionActivityAttributes.ContentState

    private var set: SetLine { SetLine(state.detail) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(sessionEyebrow(state))
                    .eyebrow()
                    .foregroundStyle(.tint)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(title).eyebrow().foregroundStyle(Ink.text3)
            }
            HStack(alignment: .bottom, spacing: 16) {
                if let end = state.restEndsAt {
                    RestCountdown(end: end, size: 58)
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(set.label.isEmpty ? "Next" : "Next · \(set.label)").eyebrow().foregroundStyle(Ink.text3)
                        if let target = set.target {
                            Text(target).numeral(26, weight: .heavy)
                        }
                        if let message = state.message {
                            Text(message).font(.footnote.weight(.medium)).foregroundStyle(Ink.text2).lineLimit(2)
                        }
                    }
                    .padding(.bottom, 4)
                } else {
                    Text(state.exercise)
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.6)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if let target = set.target {
                        Text(target).numeral(34, weight: .heavy)
                    }
                }
            }
            VStack(spacing: 6) {
                SessionRuler(state: state, height: 10)
                HStack {
                    Text(state.rulerCaptions.0)
                    Spacer()
                    Text(state.rulerCaptions.1)
                }
                .eyebrow(size: 10)
                .foregroundStyle(Ink.text3)
            }
        }
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

/// StandBy's full screen, the phone on its side on the desk between sets, as the design draws it: the
/// countdown huge, the next set beside it, and the rest's ruler tall across the foot. It's laid out
/// on the design's 844-point screen and scaled to whatever the system gives it, so it reads the same
/// whether StandBy scales the banner up or lays it out at the screen's size.
struct SessionStandBy: View {
    let title: String
    let state: SessionActivityAttributes.ContentState

    private var set: SetLine { SetLine(state.detail) }

    var body: some View {
        Color.clear
            .aspectRatio(844 / 390, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    layout(unit: geometry.size.width / 844)
                }
            }
            .accessibilityElement(children: .combine)
    }

    private func layout(unit u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(sessionEyebrow(state))
                    .eyebrow(size: 13 * u)
                    .foregroundStyle(.tint)
                    .layoutPriority(1)
                Spacer(minLength: 8 * u)
                Text(title).eyebrow(size: 13 * u).foregroundStyle(Ink.text3)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 32 * u) {
                if let end = state.restEndsAt {
                    // The design's line is 0.76 of the size, SF's 1.19: the difference comes off both ends.
                    RestCountdown(end: end, size: 232 * u, width: 1.85, shrinks: false, tightness: 0.065)
                        .padding(.leading, -8 * u)
                        .padding(.vertical, -50 * u)
                } else if let target = set.target {
                    setTarget(target, size: 160 * u)
                        .padding(.vertical, -34 * u)
                        .layoutPriority(1)
                } else {
                    Text(state.exercise).font(.system(size: 64 * u, weight: .bold)).tracking(-2 * u).lineLimit(2).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6 * u) {
                    if state.restEndsAt != nil {
                        Text(set.label.isEmpty ? "Next" : "Next · \(set.label)").eyebrow(size: 13 * u).foregroundStyle(Ink.text3)
                        if let target = set.target { setTarget(target, size: 80 * u).padding(.vertical, -12 * u) }
                        if let message = state.message {
                            Text(message)
                                .font(.system(size: 20 * u, weight: .semibold))
                                .tracking(-0.4 * u)
                                .foregroundStyle(Ink.text2)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                    } else if set.target != nil {
                        Text(state.exercise)
                            .font(.system(size: 34 * u, weight: .bold))
                            .tracking(-1.2 * u)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8 * u) {
                SessionRuler(state: state, height: 40 * u)
                HStack {
                    Text(state.rulerCaptions.0)
                    Spacer()
                    Text(state.rulerCaptions.1)
                }
                .eyebrow(size: 12 * u)
                .foregroundStyle(Ink.text3)
            }
        }
        .foregroundStyle(Ink.text)
        .padding(.top, 30 * u)
        .padding(.horizontal, 58 * u)
        .padding(.bottom, 28 * u)
    }

    /// "70 × 7+" as the design sets it: the numbers heavy and tight, the "×" lighter and grey.
    private func setTarget(_ target: String, size: CGFloat) -> some View {
        let parts = TargetParts(target)
        // Thin spaces: the design sets the "×" a few points off each number, not a word apart.
        let times = Text("\u{2009}×\u{2009}").font(.system(size: size * 0.58, weight: .semibold)).foregroundStyle(Ink.text3)
        let line = parts.reps.map { Text("\(parts.load)\(times)\($0)") } ?? Text(parts.load)
        return line.numeral(size, weight: .heavy, tightness: 0.055)
    }
}

/// The Dynamic Island held open: the countdown huge beside the exercise, the rest's ruler, and the
/// set that's next.
struct IslandSession: View {
    let state: SessionActivityAttributes.ContentState

    private var set: SetLine { SetLine(state.detail) }

    private var line: String {
        let parts = state.restEndsAt == nil ? [set.label] : ["Next · \(set.label)", set.target]
        return parts.compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if let end = state.restEndsAt {
                    RestCountdown(end: end, size: 64, width: 2.1)
                } else if let target = set.target {
                    Text(target).numeral(34, weight: .heavy)
                }
                Spacer(minLength: 0)
                Text(state.exercise)
                    .font(.headline)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            SessionRuler(state: state, color: Ink.Island.accent, track: Ink.Island.track, height: 12)
                .padding(.top, 12)
            Text(line)
                .font(.caption)
                .foregroundStyle(Ink.Island.text2)
                .lineLimit(1)
                .padding(.top, 9)
            if let message = state.message {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Ink.Island.accent)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(Ink.Island.text)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Beside the camera: the rest counting down, or which set is up.
struct IslandCompactTrailing: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        if let end = state.restEndsAt {
            Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.Island.accent)
                .frame(width: 42, alignment: .trailing)
        } else {
            Text(SetLine(state.detail).label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Ink.Island.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 60)
        }
    }
}
#endif
