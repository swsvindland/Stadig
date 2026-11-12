import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The quick feedback that feeds the Fatigue Budget, then save.
struct FinishView: View {
    @Environment(WatchModel.self) private var model
    @State private var energy = 3
    @State private var soreness = 1
    @State private var joints: Set<Joint> = []

    private static let jointChoices: [Joint] = [.shoulder, .elbow, .wrist, .lowerBack, .hip, .knee]
    private static let energyLabels = [1: "Drained", 2: "Low", 3: "OK", 4: "Good", 5: "Great"]
    private static let sorenessLabels = [0: "None", 1: "A little", 2: "Sore", 3: "Very sore"]

    var body: some View {
        if let ending = model.endingOnPhone {
            WaitingForPhone(ending: ending)
        } else if let live = model.live {
            let logged = live.items.contains { !$0.loggedSets.isEmpty }
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.isComplete ? "All done" : "Ending early")
                            .font(.headline)
                        Text("\(live.plan.title) · \(Int(Date().timeIntervalSince(live.startedAt) / 60)) min")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                if logged {
                    Section("How do you feel?") {
                        Picker("Energy", selection: $energy) {
                            ForEach(1...5, id: \.self) { Text("\($0) · \(Self.energyLabels[$0] ?? "")").tag($0) }
                        }
                        Picker("Soreness coming in", selection: $soreness) {
                            ForEach(0...3, id: \.self) { Text(Self.sorenessLabels[$0] ?? "").tag($0) }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Section("Any joint pain?") {
                        ForEach(Self.jointChoices) { joint in
                            Toggle(
                                joint.label,
                                isOn: Binding {
                                    joints.contains(joint)
                                } set: { on in
                                    if on { joints.insert(joint) } else { joints.remove(joint) }
                                })
                        }
                    }
                }
                Section {
                    if logged {
                        Button {
                            model.finish(
                                feedback: SessionFeedback(
                                    soreness: soreness, jointPain: Self.jointChoices.filter(joints.contains),
                                    energy: energy))
                        } label: {
                            Label("Save Session", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .handGestureShortcut(.primaryAction)
                        Button("Save Without Feedback") { model.finish(feedback: nil) }
                            .buttonStyle(.glass)
                    } else {
                        Text("Nothing logged yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Close Without Saving", role: .destructive) { model.discard() }
                            .buttonStyle(.glass)
                    }
                    if !live.isComplete {
                        Button("Keep Going", systemImage: "arrow.uturn.backward") { model.keepGoing() }
                            .buttonStyle(.glass)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Finish")
        }
    }
}

/// What the session came to, once it's saved and on its way to the phone: its name and minutes, what
/// moved (each lift whose estimated one-rep max it raised, before and after), then the sets and their
/// ratings, conditioning and heart rate.
struct SummaryView: View {
    @Environment(WatchModel.self) private var model
    let summary: SessionSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(summary.title) · \(summary.minutes) min")
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if summary.moved.isEmpty {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(WatchInk.good)
                } else {
                    Text("What moved")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    ForEach(summary.moved, id: \.exerciseID) { move in
                        moved(move)
                    }
                    Divider()
                }
                Text("^[\(summary.workSets) set](inflect: true) · ^[\(summary.exercises) exercise](inflect: true)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(SetRating.allCases) { rating in
                    if let count = summary.ratings[rating], count > 0 {
                        Label("\(count) \(rating.label)", systemImage: rating.symbol)
                            .foregroundStyle(rating.tint)
                            .font(.footnote)
                    }
                }
                if summary.conditioningMinutes > 0 {
                    Label("\(summary.conditioningMinutes) min conditioning", systemImage: "heart.circle")
                        .font(.footnote)
                }
                if let bpm = summary.averageHeartRate {
                    Label("Average \(Int(bpm.rounded())) bpm", systemImage: "heart.fill")
                        .font(.footnote)
                }
                Text(summary.savedOnPhone ? "Saved in Stadig Lift on your iPhone." : "Sent to Stadig Lift on your iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    model.summary = nil
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .handGestureShortcut(.primaryAction)
            }
        }
        .navigationTitle("Summary")
    }

    /// "Bench Press est. 1RM" over "91 → 92.5 kg".
    private func moved(_ move: EstimateMove) -> some View {
        let unit = model.unit
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(model.catalog[move.exerciseID]?.name ?? move.exerciseID) est. 1RM")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(WatchFormat.number(unit.fromKilograms(move.beforeKg), digits: 1))
                    .foregroundStyle(.secondary)
                Text("→").foregroundStyle(.secondary)
                Text(WatchFormat.number(unit.fromKilograms(move.afterKg), digits: 1))
                Text(unit.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 22, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(model.catalog[move.exerciseID]?.name ?? move.exerciseID), estimated one-rep max up from \(WatchFormat.number(unit.fromKilograms(move.beforeKg), digits: 1)) to \(WatchFormat.number(unit.fromKilograms(move.afterKg), digits: 1)) \(unit.symbol)"
        )
    }
}

/// Ending a session the iPhone runs: the phone saves it (or throws it away) and says so, and the
/// summary follows. Should the phone never answer, the session can be left to it.
struct WaitingForPhone: View {
    @Environment(WatchModel.self) private var model
    let ending: MirrorMessage

    private var discarding: Bool {
        if case .discardFromWatch = ending { true } else { false }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ProgressView()
                Text(discarding ? "Discarding on your iPhone" : "Saving on your iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Keep your iPhone nearby.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Leave It to iPhone", systemImage: "iphone") { model.stopCompanion() }
                    .buttonStyle(.glass)
                    .accessibilityHint("Stops heart rate here. Finish the session on your iPhone.")
            }
        }
        .navigationTitle("Finish")
    }
}
