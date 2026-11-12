#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Rest counting down on the Lock Screen, in StandBy and in the Dynamic Island, so the phone can stay
/// in a pocket between sets: the countdown as the hero, the set that comes next beside it, and the
/// session's progress as the ruler. The activity carries when the rest ends but not when it began, so
/// the ruler is the session's, not the rest draining.
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
                Ruler(value: context.state.progress, color: Ink.Island.accent, height: 8, divisions: 0, track: Ink.Island.track)
                    .frame(width: 30)
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

/// The rest left, counting down by itself.
struct RestCountdown: View {
    let end: Date
    let size: CGFloat

    var body: some View {
        // A timer's text is laid out for its widest value, so it gets a width of its own.
        Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
            .numeral(size, weight: .heavy, tightness: 0.05)
            .frame(width: size * 2.3, alignment: .leading)
    }
}

/// The Lock Screen's banner, which StandBy draws full screen: resting, the countdown with the next
/// set beside it; between rests, the exercise and the set to do.
struct SessionLockScreen: View {
    let title: String
    let state: SessionActivityAttributes.ContentState

    private var set: SetLine { SetLine(state.detail) }
    private var percent: Int { Int((min(1, max(0, state.progress)) * 100).rounded()) }

    /// "Rest · Barbell Bench Press", "Up now · Set 2 of 3", or "Up now" when only finishing is left.
    private var eyebrow: String {
        if state.restEndsAt != nil { return "Rest · \(state.exercise)" }
        return set.label.isEmpty ? "Up now" : "Up now · \(set.label)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow)
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
                Ruler(value: state.progress, height: 10)
                HStack {
                    Text("Session")
                    Spacer()
                    Text("\(percent)% done")
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

/// The Dynamic Island held open: the countdown huge beside the exercise, the session's ruler, and
/// the set that's next.
struct IslandSession: View {
    let state: SessionActivityAttributes.ContentState

    private var set: SetLine { SetLine(state.detail) }

    private var line: String {
        let parts = state.restEndsAt == nil ? [set.label] : ["Next · \(set.label)", set.target]
        return parts.compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if let end = state.restEndsAt {
                    RestCountdown(end: end, size: 52)
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
            Ruler(value: state.progress, color: Ink.Island.accent, height: 10, track: Ink.Island.track)
            Text(line)
                .font(.caption.weight(.medium))
                .foregroundStyle(Ink.Island.text2)
                .lineLimit(1)
            if let message = state.message {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Ink.Island.accent)
                    .lineLimit(1)
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
