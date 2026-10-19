#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Rest counting down on the Lock Screen and in the Dynamic Island, so the phone can stay in a
/// pocket between sets.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(title: context.attributes.title, state: context.state)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.restEndsAt == nil ? "Next" : "Rest", systemImage: "figure.strengthtraining.traditional")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = context.state.restEndsAt {
                        Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                            .font(.title3.monospacedDigit())
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exercise).font(.headline).lineLimit(1)
                        Text(context.state.detail).font(.subheadline).foregroundStyle(.secondary)
                        if let message = context.state.message { Text(message).font(.caption).foregroundStyle(.tint) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
            } compactTrailing: {
                if let end = context.state.restEndsAt {
                    Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                        .monospacedDigit()
                        .frame(width: 44)
                } else {
                    Text(context.state.detail.components(separatedBy: " · ").first ?? "").font(.caption2)
                }
            } minimal: {
                Image(systemName: context.state.restEndsAt == nil ? "figure.strengthtraining.traditional" : "timer")
            }
            .widgetURL(URL(string: "lifttrack://session"))
        }
    }
}

private struct LockScreenView: View {
    let title: String
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(state.exercise).font(.headline).lineLimit(1)
                Text(state.detail).font(.subheadline)
                if let message = state.message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                ProgressView(value: state.progress).tint(.white)
            }
            Spacer()
            if let end = state.restEndsAt {
                VStack(spacing: 0) {
                    Text("Rest").font(.caption).foregroundStyle(.secondary)
                    Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(width: 96)
                }
            }
        }
        .foregroundStyle(.white)
    }
}
#endif
