import SwiftUI
import ExerciseLibrary
import HealthBridge
import LiftEngine
import SystemCore

/// The rest between sets: a countdown ring, live heart rate, what the last rating changed, and
/// what's next. Heart rate may end an accessory's rest early (the model watches for that).
struct RestView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        if let live = model.live, let rest = live.rest {
            ScrollView {
                VStack(spacing: 8) {
                    ring(rest)
                    heartRate(rest)
                    if let message = live.message {
                        Text(message)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let filler = rest.filler {
                        Label("Use the rest: \(model.catalog[filler]?.name ?? filler)", systemImage: "figure.flexibility")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("15 s", systemImage: "minus") { model.extendRest(by: -15) }
                            .accessibilityLabel("15 seconds less")
                        Button("15 s", systemImage: "plus") { model.extendRest(by: 15) }
                            .accessibilityLabel("15 seconds more")
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
                    .buttonStyle(.glass)
                    Button {
                        model.endRest()
                    } label: {
                        Label("Skip Rest", systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .handGestureShortcut(.primaryAction)
                    upNext
                }
            }
            .navigationTitle("Rest")
        }
    }

    private func ring(_ rest: RestState) -> some View {
        TimelineView(.periodic(from: rest.started, by: 1)) { context in
            let total = max(1, rest.endsAt.timeIntervalSince(rest.started))
            let remaining = max(0, rest.endsAt.timeIntervalSince(context.date))
            ZStack {
                Circle()
                    .stroke(.tint.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: remaining / total)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                Text(timerInterval: rest.started...max(rest.started, rest.endsAt), countsDown: true)
                    .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .padding(12)
            }
            .frame(width: 110, height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest")
            .accessibilityValue("\(WatchFormat.clock(Int(remaining.rounded(.up)))) left")
        }
    }

    @ViewBuilder private func heartRate(_ rest: RestState) -> some View {
        if let bpm = model.workout.heartRate {
            let zone = model.zones.zone(for: bpm)
            Label {
                Text("\(Int(bpm.rounded())) bpm").monospacedDigit()
            } icon: {
                Image(systemName: "heart.fill").foregroundStyle(HeartRateZones.tint(for: zone))
            }
            .font(.headline)
            .accessibilityLabel("Heart rate \(Int(bpm.rounded())), zone \(zone)")
        }
        if rest.plan.heartRateGuided {
            Text("Ends early once your heart rate settles, after \(WatchFormat.clock(rest.plan.minimum)).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var upNext: some View {
        if let live = model.live, let (item, set) = model.position {
            let exercise = model.exercise(item)
            let liveItem = live.items[item]
            VStack(spacing: 2) {
                Text("Up next").font(.caption2).foregroundStyle(.secondary)
                Text(exercise.name).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                Text(WatchFormat.prescription(liveItem.sets[set].prescription, exercise: exercise, unit: model.unit,
                                              plannedSeconds: liveItem.plan.seconds))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
