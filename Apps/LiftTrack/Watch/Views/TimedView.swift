import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// Mobility, warm-up moves, stretches and unloaded holds: a countdown when the item is timed, a
/// count when it isn't, then Done. Nothing here is rated.
struct TimedView: View {
    @Environment(WatchModel.self) private var model
    let item: Int
    let set: Int

    var body: some View {
        if let live = model.live, live.items.indices.contains(item), live.items[item].sets.indices.contains(set) {
            let liveItem = live.items[item]
            let exercise = model.exercise(item)
            let prescription = liveItem.sets[set].prescription
            ScrollView {
                VStack(spacing: 6) {
                    NoticeRow()
                    Text("\(liveItem.plan.block.label) · \(WatchFormat.setPosition(set, in: liveItem.sets))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(exercise.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if let seconds = prescription.seconds ?? liveItem.plan.seconds {
                        countdown(seconds: seconds)
                    } else {
                        Text(exercise.unilateral ? "\(prescription.targetReps) each side" : "\(prescription.targetReps) reps")
                            .font(.title2.weight(.semibold).monospacedDigit())
                        doneButton(primary: true)
                    }
                    if !exercise.cue.isEmpty {
                        Text(exercise.cue)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private func countdown(seconds: Int) -> some View {
        if let timer = model.timer(for: item, set: set) {
            let ends = timer.started.addingTimeInterval(TimeInterval(seconds))
            TimelineView(.periodic(from: timer.started, by: 1)) { context in
                let remaining = max(0, ends.timeIntervalSince(context.date))
                VStack(spacing: 6) {
                    if remaining > 0 {
                        Text(timerInterval: timer.started...ends, countsDown: true)
                            .font(.system(size: 44, weight: .bold).monospacedDigit())
                            .tracking(-1.5)
                            .multilineTextAlignment(.center)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 36, weight: .bold))
                            .frame(height: 52)
                    }
                    // The time left as a fill on a track, as the phone's rulers draw it: no rings.
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * remaining / Double(max(seconds, 1)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WatchInk.track, in: .capsule)
                            .animation(.linear(duration: 1), value: remaining)
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time left")
                .accessibilityValue(WatchFormat.clock(Int(remaining.rounded(.up))))
            }
            doneButton(primary: true)
        } else {
            Text(WatchFormat.duration(seconds))
                .font(.title2.weight(.semibold).monospacedDigit())
            Button {
                model.startTimer(item: item, set: set)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .handGestureShortcut(.primaryAction)
            doneButton(primary: false)
        }
    }

    @ViewBuilder private func doneButton(primary: Bool) -> some View {
        let button = Button {
            model.finishTimed(item: item, set: set)
        } label: {
            Label("Done", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        }
        if primary {
            button.buttonStyle(.glassProminent).handGestureShortcut(.primaryAction)
        } else {
            button.buttonStyle(.glass)
        }
    }
}
