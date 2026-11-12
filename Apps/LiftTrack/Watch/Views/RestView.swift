import ExerciseLibrary
import HealthBridge
import LiftEngine
import SwiftUI
import SystemCore
import WatchKit

/// The rest between sets, as the design's face: a level of the accent filling the screen toward
/// go, the countdown huge, heart rate small, the next set, and Go now (Double Tap). Below: what the
/// last rating changed, the drill for the rest, a quarter-minute less or more, and the next set in
/// full. Heart rate may end an accessory's rest early (the model watches for that).
struct RestView: View {
    @Environment(WatchModel.self) private var model

    /// The smallest Watches (40 and 41 mm), where the countdown is set smaller to leave the next set
    /// above the band.
    private static let small = WKInterfaceDevice.current().screenBounds.width < 180

    var body: some View {
        if let live = model.live, let rest = live.rest {
            ScrollView {
                VStack(spacing: 8) {
                    VStack(spacing: Self.small ? 2 : 4) {
                        heartRate(rest)
                        countdown(rest)
                        nextSet
                    }
                    .padding(.bottom, 6)
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
                    if rest.plan.heartRateGuided {
                        Text("Ends early once your heart rate settles, after \(WatchFormat.clock(rest.plan.minimum)).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    upNext
                }
            }
            // Go now stays at the foot of the face; the rest's other choices scroll above it.
            .safeAreaInset(edge: .bottom, spacing: 4) {
                ActionBand(title: "Go now") { model.endRest() }
                    .accessibilityLabel("Skip rest")
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .background { level(rest) }
            .navigationTitle("Rest")
        }
    }

    /// The accent rising from the foot of the screen as the rest runs out: full is go.
    private func level(_ rest: RestState) -> some View {
        TimelineView(.periodic(from: rest.started, by: 1)) { context in
            let total = max(1, rest.endsAt.timeIntervalSince(rest.started))
            let elapsed = min(total, max(0, context.date.timeIntervalSince(rest.started)))
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.34))
                    .frame(height: geometry.size.height * elapsed / total)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(.linear(duration: 1), value: elapsed)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func countdown(_ rest: RestState) -> some View {
        TimelineView(.periodic(from: rest.started, by: 1)) { context in
            let remaining = max(0, rest.endsAt.timeIntervalSince(context.date))
            Text(timerInterval: rest.started...max(rest.started, rest.endsAt), countsDown: true)
                .font(.system(size: Self.small ? 50 : 76, weight: .bold))
                .monospacedDigit()
                .tracking(-3)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rest")
                .accessibilityValue("\(WatchFormat.clock(Int(remaining.rounded(.up)))) left")
        }
    }

    /// "Next 80 kg × 8", under the countdown.
    @ViewBuilder private var nextSet: some View {
        if let live = model.live, let (item, set) = model.position {
            let exercise = model.exercise(item)
            let liveItem = live.items[item]
            Text(
                "Next \(WatchFormat.prescription(liveItem.sets[set].prescription, exercise: exercise, unit: model.unit, plannedSeconds: liveItem.plan.seconds))"
            )
            .font(.system(size: 15, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
        }
    }

    /// Heart rate, small, in the corner of the face.
    @ViewBuilder private func heartRate(_ rest: RestState) -> some View {
        HStack(spacing: 4) {
            if let bpm = model.workout.heartRate {
                let zone = model.zones.zone(for: bpm)
                Image(systemName: "heart.fill").foregroundStyle(HeartRateZones.tint(for: zone))
                Text("\(Int(bpm.rounded()))").monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 15, weight: .semibold))
        .frame(minHeight: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.workout.heartRate.map { "Heart rate \(Int($0.rounded())), zone \(model.zones.zone(for: $0))" } ?? "")
        .accessibilityHidden(model.workout.heartRate == nil)
    }

    @ViewBuilder private var upNext: some View {
        if let live = model.live, let (item, set) = model.position {
            let exercise = model.exercise(item)
            let liveItem = live.items[item]
            VStack(spacing: 2) {
                Text("Up next").font(.caption2).foregroundStyle(.secondary)
                Text(exercise.name).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                Text(
                    WatchFormat.prescription(
                        liveItem.sets[set].prescription, exercise: exercise, unit: model.unit,
                        plannedSeconds: liveItem.plan.seconds)
                )
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
