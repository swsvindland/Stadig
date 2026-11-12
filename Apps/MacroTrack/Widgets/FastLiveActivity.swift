#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// The running fast on the Lock Screen and in the Dynamic Island: the time since it began counts on
/// by itself as the hero, and the ruler fills toward the goal.
struct FastLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastActivityAttributes.self) { context in
            FastLockScreen(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Ink.ground)
                .activitySystemActionForegroundColor(Ink.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.isStale ? "Fasting" : context.state.phase)
                        .eyebrow()
                        .foregroundStyle(Ink.Island.accent)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Goal \(context.state.goalEnd.formatted(date: .omitted, time: .shortened))")
                        .eyebrow()
                        .foregroundStyle(Ink.Island.text3)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandFast(state: context.state, stale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(Ink.Island.accent)
            } compactTrailing: {
                Text(context.state.start, style: .timer)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.Island.accent)
                    .frame(width: 60, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(Ink.Island.accent)
            }
            .widgetURL(URL(string: "macrotrack://fast"))
            .keylineTint(Ink.Island.accent)
        }
    }
}

/// The ruler toward the goal, filling by itself between updates: the system's timer bar, made as
/// tall as a ruler and cut into tenths.
struct FastRuler: View {
    let start: Date
    let end: Date
    var color: Color = .accentColor
    var track: Color = Ink.track
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(track)
                ProgressView(timerInterval: start...max(start, end), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(color)
                // The bar is a few points tall; stretched, its track and rounded ends fall outside the mask.
                .scaleEffect(x: 1.04, y: height / 2, anchor: .center)
            }
            .mask { TickedOutline(size: geometry.size, divisions: 10) }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private struct FastLockScreen: View {
    let state: FastActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(stale ? "Fasting" : "Fasting · \(state.phase)", systemImage: state.symbol)
                    .eyebrow()
                    .foregroundStyle(.tint)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text("Goal \(state.goalEnd.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .eyebrow()
                    .foregroundStyle(Ink.text3)
            }
            Text(state.start, style: .timer)
                .numeral(52, weight: .heavy, tightness: 0.05)
            FastRuler(start: state.start, end: state.goalEnd)
            FastNextLine(state: state, stale: stale)
                .eyebrow(size: 10)
                .foregroundStyle(Ink.text3)
        }
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

/// The Dynamic Island held open: the time huge, the ruler toward the goal, the next phase.
private struct IslandFast: View {
    let state: FastActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.start, style: .timer)
                .numeral(44, weight: .heavy, tightness: 0.05)
            FastRuler(start: state.start, end: state.goalEnd, color: Ink.Island.accent, track: Ink.Island.track, height: 10)
            FastNextLine(state: state, stale: stale)
                .font(.caption.weight(.medium))
                .foregroundStyle(Ink.Island.text2)
        }
        .foregroundStyle(Ink.Island.text)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

/// When the next phase begins, while it's still ahead.
private struct FastNextLine: View {
    let state: FastActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        if let next = state.nextPhase, let at = state.nextPhaseAt, !stale {
            Text("\(next) from \(at.formatted(date: .omitted, time: .shortened))")
        }
    }
}
#endif
