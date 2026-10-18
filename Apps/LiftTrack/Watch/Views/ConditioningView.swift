import ExerciseLibrary
import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore

/// Conditioning: time against the planned minutes, and live heart rate against the target zones.
/// Done logs the minutes, the average heart rate and the minutes spent in each zone.
struct ConditioningView: View {
    @Environment(WatchModel.self) private var model
    let item: Int

    var body: some View {
        if let live = model.live, live.items.indices.contains(item) {
            let liveItem = live.items[item]
            let plan =
                liveItem.plan.conditioning
                ?? ConditioningPlan(minutes: max(1, (liveItem.plan.seconds ?? 600) / 60), zones: 2...3, style: .steady)
            ScrollView {
                VStack(spacing: 6) {
                    NoticeRow()
                    Text(model.exercise(item).name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(plan.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let timer = model.timer(for: item, set: 0) {
                        clock(plan, started: timer.started)
                        heartRate(plan)
                        Button {
                            model.finishConditioning(item: item)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .handGestureShortcut(.primaryAction)
                    } else {
                        Text(targetRange(plan))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button {
                            model.startTimer(item: item, set: 0)
                        } label: {
                            Label("Start", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .handGestureShortcut(.primaryAction)
                    }
                }
            }
        }
    }

    private func clock(_ plan: ConditioningPlan, started: Date) -> some View {
        TimelineView(.periodic(from: started, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(started))
            let target = Double(plan.minutes * 60)
            VStack(spacing: 4) {
                Text(timerInterval: started...started.addingTimeInterval(24 * 3600), countsDown: false)
                    .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(elapsed >= target ? .green : .primary)
                ProgressView(value: min(1, elapsed / target))
                    .tint(.green)
                    .accessibilityHidden(true)
                Text("of \(plan.minutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let phase = phase(plan, elapsed: elapsed) {
                    Label(
                        phase.work ? "Work · \(phase.left) s" : "Easy · \(phase.left) s",
                        systemImage: phase.work ? "flame.fill" : "wind"
                    )
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(phase.work ? .orange : .blue)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func heartRate(_ plan: ConditioningPlan) -> some View {
        if let bpm = model.workout.heartRate {
            let zone = model.zones.zone(for: bpm)
            let status: (text: String, symbol: String) =
                zone < plan.zones.lowerBound
                ? ("Pick it up", "arrow.up")
                : zone > plan.zones.upperBound
                    ? ("Ease off", "arrow.down")
                    : ("In the zone", "checkmark")
            VStack(spacing: 2) {
                Label {
                    Text("\(Int(bpm.rounded())) bpm · Zone \(zone)").monospacedDigit()
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(HeartRateZones.tint(for: zone))
                }
                .font(.headline)
                Label(status.text, systemImage: status.symbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(targetRange(plan))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// "Target 128–152 bpm".
    private func targetRange(_ plan: ConditioningPlan) -> String {
        let low = model.zones.range(zone: plan.zones.lowerBound).lowerBound
        let high = model.zones.range(zone: plan.zones.upperBound).upperBound
        return "Target \(Int(low.rounded()))–\(Int(high.rounded())) bpm"
    }

    /// Work or easy, and seconds left in it, for interval conditioning.
    private func phase(_ plan: ConditioningPlan, elapsed: TimeInterval) -> (work: Bool, left: Int)? {
        guard plan.style == .intervals, let work = plan.workSeconds, let easy = plan.restSeconds, work > 0, easy > 0 else { return nil }
        let into = Int(elapsed) % (work + easy)
        return into < work ? (true, work - into) : (false, work + easy - into)
    }
}
