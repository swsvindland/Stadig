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
        if let live = model.live {
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

/// What the session came to, once it's saved and on its way to the phone.
struct SummaryView: View {
    @Environment(WatchModel.self) private var model
    let summary: SessionSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(summary.title)
                    .font(.title3.weight(.semibold))
                Text("\(summary.minutes) min · ^[\(summary.workSets) set](inflect: true) · ^[\(summary.exercises) exercise](inflect: true)")
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
                Text("Sent to Lift Track on your iPhone.")
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
}
