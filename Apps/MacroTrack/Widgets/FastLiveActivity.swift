#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// The running fast on the Lock Screen and in the Dynamic Island: the time since it began counts on
/// by itself, and the bar fills toward the goal.
struct FastLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastActivityAttributes.self) { context in
            FastLockScreen(state: context.state, stale: context.isStale)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.isStale ? "Fasting" : context.state.phase, systemImage: context.state.symbol).font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.start, style: .timer).font(.title3.monospacedDigit()).frame(width: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(timerInterval: context.state.start...max(context.state.start, context.state.goalEnd), countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(.teal)
                        FastNextLine(state: context.state, stale: context.isStale)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(.teal)
            } compactTrailing: {
                Text(context.state.start, style: .timer).monospacedDigit().frame(width: 56)
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(.teal)
            }
            .widgetURL(URL(string: "macrotrack://fast"))
        }
    }
}

private struct FastLockScreen: View {
    let state: FastActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(stale ? "Fasting" : state.phase, systemImage: state.symbol).font(.headline)
                Spacer()
                Text(state.start, style: .timer).font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            ProgressView(timerInterval: state.start...max(state.start, state.goalEnd), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.teal)
            HStack {
                FastNextLine(state: state, stale: stale)
                Spacer()
                Text("Goal \(state.goalEnd.formatted(.dateTime.weekday(.abbreviated).hour().minute()))").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }
}

/// When the next phase begins, while it's still ahead.
private struct FastNextLine: View {
    let state: FastActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        if let next = state.nextPhase, let at = state.nextPhaseAt, !stale {
            Text("\(next) from \(at.formatted(date: .omitted, time: .shortened))").font(.caption)
        }
    }
}
#endif
