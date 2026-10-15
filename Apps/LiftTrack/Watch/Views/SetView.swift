import SwiftUI
import ExerciseLibrary
import LiftEngine
import SystemCore

/// One loaded set: what to do, the crown on the load (snapped to loads the gym can make) or the
/// reps, and Done.
struct SetView: View {
    @Environment(WatchModel.self) private var model
    let item: Int
    let set: Int
    let done: (SetDraft) -> Void

    private enum Field { case load, reps }

    @State private var loadKg: Double?
    @State private var reps = 0
    /// Loads near the current one, in kg; the crown moves through them by index.
    @State private var loads: [Double] = []
    @State private var crown = 0.0
    @State private var editing = Field.load
    @State private var prepared = false
    @FocusState private var crownFocused: Bool

    var body: some View {
        if let live = model.live, live.items.indices.contains(item), live.items[item].sets.indices.contains(set) {
            let liveItem = live.items[item]
            let liveSet = liveItem.sets[set]
            let exercise = model.exercise(item)
            ScrollView {
                VStack(spacing: 4) {
                    NoticeRow()
                    Text("\(liveItem.plan.block.label) · \(WatchFormat.setPosition(set, in: liveItem.sets))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(exercise.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    values(exercise: exercise, liveSet: liveSet, plannedSeconds: liveSet.prescription.seconds ?? liveItem.plan.seconds)
                    Button {
                        done(SetDraft(item: item, set: set, loadKg: exercise.loadBasis == .none ? nil : loadKg, reps: reps,
                                      seconds: timedSeconds(exercise, liveSet: liveSet, planned: liveItem.plan.seconds)))
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .handGestureShortcut(.primaryAction)
                    if let note = liveSet.note {
                        Text(note)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    Text(WatchFormat.hint(liveSet.prescription))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    // The toggle between weight and reps, and a reminder of what the crown does.
                    if exercise.loadBasis != .none, !exercise.timed {
                        Button {
                            select(editing == .load ? .reps : .load)
                        } label: {
                            Label(editing == .load ? "Crown: weight" : "Crown: reps", systemImage: "digitalcrown.arrow.clockwise")
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(editing == .load ? "Crown adjusts weight. Switch to reps." : "Crown adjusts reps. Switch to weight.")
                    }
                }
            }
            .onAppear { prepare(exercise: exercise, prescription: liveSet.prescription) }
        }
    }

    // MARK: Values

    private func values(exercise: Exercise, liveSet: LiveSet, plannedSeconds: Int?) -> some View {
        let hasLoad = exercise.loadBasis != .none
        let seconds = timedSeconds(exercise, liveSet: liveSet, planned: plannedSeconds)
        return VStack(spacing: 4) {
            if hasLoad {
                Text(WatchFormat.load(loadKg, unit: model.unit, basis: exercise.loadBasis))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .overlay { selection(editing == .load) }
                    .contentShape(.capsule)
                    .onTapGesture { select(.load) }
                    .accessibilityLabel("Weight")
                    .accessibilityValue(WatchFormat.load(loadKg, unit: model.unit, basis: exercise.loadBasis))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAdjustableAction { direction in
                        select(.load)
                        nudge(direction == .increment ? 1 : -1)
                    }
            }
            if let seconds {
                Text("for \(WatchFormat.duration(seconds))")
                    .font(.headline)
            } else {
                Text(hasLoad ? "× \(reps) reps" : "\(reps) reps")
                    .font(hasLoad ? .headline.monospacedDigit() : .title2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .overlay { selection(editing == .reps) }
                    .contentShape(.capsule)
                    .onTapGesture { select(.reps) }
                    .accessibilityLabel("Reps")
                    .accessibilityValue("\(reps)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAdjustableAction { direction in
                        select(.reps)
                        nudge(direction == .increment ? 1 : -1)
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($crown, from: 0, through: crownUpperBound, by: 1, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { apply() }
    }

    private func selection(_ selected: Bool) -> some View {
        Capsule()
            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            .accessibilityHidden(true)
    }

    private var crownUpperBound: Double {
        editing == .load ? Double(max(loads.count - 1, 1)) : 60
    }

    /// Seconds for a timed set that still takes a load (a carry); nil for counted sets.
    private func timedSeconds(_ exercise: Exercise, liveSet: LiveSet, planned: Int?) -> Int? {
        exercise.timed ? liveSet.prescription.seconds ?? planned : nil
    }

    // MARK: Crown

    private var increments: GymIncrements? { model.increments(for: model.exercise(item)) }

    private func prepare(exercise: Exercise, prescription: SetPrescription) {
        crownFocused = true
        guard !prepared else { return }
        prepared = true
        reps = prescription.targetReps
        loadKg = model.startingLoad(item: item, set: set)
        if exercise.loadBasis != .none, let increments {
            loads = increments.around(loadKg)
            editing = .load
            crown = Double(nearest(loadKg ?? 0, in: loads))
        } else {
            editing = .reps
            crown = Double(reps)
        }
    }

    private func select(_ field: Field) {
        guard field != editing, field == .reps || !loads.isEmpty else { return }
        editing = field
        crown = field == .load ? Double(nearest(loadKg ?? 0, in: loads)) : Double(reps)
        crownFocused = true
    }

    /// One step up or down, for VoiceOver's adjustable action.
    private func nudge(_ delta: Int) {
        crown = max(0, min(crownUpperBound, crown.rounded() + Double(delta)))
    }

    private func apply() {
        switch editing {
        case .load:
            guard !loads.isEmpty else { return }
            let index = max(0, min(loads.count - 1, Int(crown.rounded())))
            guard loads[index] != loadKg else { return }
            loadKg = loads[index]
            // At either end of the list, re-centre it so the crown never runs out of loads.
            if index == loads.count - 1 || (index == 0 && loads[0] > 0) { recentre() }
        case .reps:
            reps = max(0, min(60, Int(crown.rounded())))
        }
    }

    private func recentre() {
        guard let increments, let loadKg else { return }
        let list = increments.around(loadKg)
        guard list != loads else { return }
        loads = list
        crown = Double(nearest(loadKg, in: list))
    }

    private func nearest(_ kg: Double, in list: [Double]) -> Int {
        list.indices.min { abs(list[$0] - kg) < abs(list[$1] - kg) } ?? 0
    }
}
