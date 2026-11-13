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

/// What the session came to, once it's saved and on its way to the phone, as the design's last face:
/// its name and minutes, Strength as the phone last published it (the score big, how far it moved
/// this month, Your shape beside it, a ruler and the points to the next level), and at the foot what
/// moved (each lift whose estimated one-rep max it raised, before and after). Scrolled on: the other
/// lifts that moved, the work sets against the plan's with how they were rated, conditioning, heart
/// rate, where it went, and Done. Before the phone has sent scores (someone new, or an older phone)
/// the work sets lead instead. The Watch can't score the session itself (it hasn't the whole
/// history), so the score is the phone's, and moves once the phone has the session and sends it again.
struct SummaryView: View {
    @Environment(WatchModel.self) private var model
    let summary: SessionSummary

    var body: some View {
        let scores = model.context?.scores
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let scores, let strength = scores.strength {
                    // The first screen is the design's face: the top line, Strength, and what moved at its foot.
                    VStack(alignment: .leading, spacing: 0) {
                        title
                        strengthBlock(strength, scores: scores)
                            .padding(.top, 9)
                        Spacer(minLength: 0)
                        if let first = summary.moved.first {
                            hairline.padding(.top, 12)
                            moved(first).padding(.top, 9)
                        }
                    }
                    .frame(minHeight: WatchFace.height - 16, alignment: .top)
                    ForEach(summary.moved.dropFirst(), id: \.exerciseID) { move in
                        hairline.padding(.top, 12)
                        moved(move).padding(.top, 9)
                    }
                    hairline.padding(.top, 12)
                    sets.padding(.top, 9)
                } else {
                    title
                    sets.padding(.top, 9)
                    ForEach(summary.moved, id: \.exerciseID) { move in
                        hairline.padding(.top, 12)
                        moved(move).padding(.top, 9)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if summary.conditioningMinutes > 0 {
                        Label("\(summary.conditioningMinutes) min conditioning", systemImage: "heart.circle")
                    }
                    if let bpm = summary.averageHeartRate {
                        Label("Average \(Int(bpm.rounded())) bpm", systemImage: "heart.fill")
                    }
                    Text(summary.savedOnPhone ? "Saved in Stadig Lift on your iPhone." : "Sent to Stadig Lift on your iPhone.")
                        .foregroundStyle(WatchInk.text2)
                }
                .faceFont(13)
                .padding(.top, 16)
                Button {
                    model.summary = nil
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .handGestureShortcut(.primaryAction)
                .padding(.top, 12)
            }
            .padding(.horizontal, WatchFace.margin)
            .padding(.bottom, 16)
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
        .toolbar(.hidden, for: .navigationBar)
    }

    private var title: some View {
        Text("\(summary.title) · \(summary.minutes) min")
            .faceEyebrow(WatchInk.text3)
            .faceTopLine()
            .accessibilityAddTraits(.isHeader)
    }

    private var hairline: some View {
        Rectangle().fill(WatchInk.hairline).frame(height: 1)
    }

    /// "Strength" over "58" big with "+1" beside it, Your shape at the right, then Strength on a
    /// ruler and "2 to Intermediate".
    private func strengthBlock(_ strength: Int, scores: WatchScores) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Strength").faceFont(13, weight: .semibold).foregroundStyle(Color.accentColor)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        BigNumber(value: "\(strength)", points: 66 * WatchFace.scale)
                        if let change = scores.strengthChange {
                            Text(change.short)
                                .faceFont(15, weight: .bold)
                                .monospacedDigit()
                                .foregroundStyle(Self.color(change))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
                Spacer(minLength: 0)
                ShapeGlyph(scores: scores.scores, size: 62 * WatchFace.scale)
                    .padding(.trailing, -4)
                    .padding(.bottom, 2)
            }
            WatchRuler(fraction: Double(strength) / 100)
                .padding(.top, 10)
            if let next = scores.strengthNext {
                Text(next)
                    .faceFont(13)
                    .foregroundStyle(WatchInk.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Strength \(strength)\(scores.strengthChange.map { ", \($0.spoken(calendar: .current))" } ?? "")\(scores.strengthNext.map { ". \($0)" } ?? "")"
        )
    }

    /// Up in good, down in ok (worth a look, not an alarm), steady in the second grey, as on the phone.
    private static func color(_ change: ScoreChange) -> Color {
        switch change.direction {
        case .up: WatchInk.good
        case .down: WatchInk.ok
        case .steady: WatchInk.text2
        }
    }

    /// "Work sets", "19" big with "of 19", the ruler, and "14 just right · 3 easy · 2 missed".
    private var sets: some View {
        let planned = summary.plannedSets.flatMap { $0 > 0 ? $0 : nil }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Work sets").faceFont(13, weight: .semibold).foregroundStyle(Color.accentColor)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                BigNumber(value: "\(summary.workSets)", points: 66 * WatchFace.scale)
                if let planned {
                    Text(summary.workSets >= planned ? "all done" : "of \(planned)")
                        .faceFont(15, weight: .bold)
                        .foregroundStyle(summary.workSets >= planned ? WatchInk.good : WatchInk.text2)
                }
            }
            .padding(.top, 1)
            if let planned {
                WatchRuler(fraction: Double(summary.workSets) / Double(planned))
                    .padding(.top, 10)
            }
            if !ratingsLine.isEmpty {
                Text(ratingsLine)
                    .faceFont(13)
                    .foregroundStyle(WatchInk.text2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(summary.workSets) work sets\(planned.map { " of \($0)" } ?? ""). \(ratingsLine)")
    }

    /// "14 just right · 3 easy · 2 missed", most first.
    private var ratingsLine: String {
        SetRating.allCases
            .compactMap { rating in summary.ratings[rating].flatMap { $0 > 0 ? (rating, $0) : nil } }
            .sorted { $0.1 > $1.1 }
            .map { "\($0.1) \($0.0.label.lowercased())" }
            .joined(separator: " · ")
    }

    /// "Bench Press est. 1RM" over "91 → 92.5 kg".
    private func moved(_ move: EstimateMove) -> some View {
        let unit = model.unit
        let before = WatchFormat.number(unit.fromKilograms(move.beforeKg), digits: 1)
        let after = WatchFormat.number(unit.fromKilograms(move.afterKg), digits: 1)
        let name = model.catalog[move.exerciseID]?.name ?? move.exerciseID
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(name) est. 1RM")
                .faceFont(13)
                .foregroundStyle(WatchInk.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(before)
                Text("→").fontWeight(.semibold).foregroundStyle(WatchInk.text3)
                Text(after)
                Text(unit.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(WatchInk.text2)
            }
            .font(.system(size: 21, weight: .bold).monospacedDigit())
            .tracking(-0.4)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), estimated one-rep max up from \(before) to \(after) \(unit.symbol)")
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
