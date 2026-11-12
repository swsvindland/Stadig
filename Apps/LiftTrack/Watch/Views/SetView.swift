import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore
import WatchKit

/// One loaded set, as the design's face: the exercise and where the set sits, the set as one big
/// "70 × 7" (the crown on the load, snapped to loads the gym can make, or on the reps), and the band
/// at the foot that Double Tap presses: Just right for a rated set, Done or Log reps otherwise. The
/// band's other half opens Easy and Missed. The set's note, the hint and the crown's toggle are below.
struct SetView: View {
    @Environment(WatchModel.self) private var model
    let item: Int
    let set: Int
    /// The band: logs the set Just right (or, unrated, as it is).
    let done: (SetDraft) -> Void
    /// Easy or Missed instead.
    let rate: (SetDraft) -> Void

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
            let draft = SetDraft(
                item: item, set: set, loadKg: exercise.loadBasis == .none ? nil : loadKg, reps: reps,
                seconds: timedSeconds(exercise, liveSet: liveSet, planned: liveItem.plan.seconds))
            let rated = Self.isRated(liveSet.prescription.kind) && draft.seconds == nil
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    NoticeRow()
                    Text(exercise.name)
                        .font(.system(size: Self.small ? 12 : 14, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        SetDots(index: set, sets: liveItem.sets)
                        if let kind = Self.kindWord(liveSet.prescription.kind) {
                            Text(kind).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    values(exercise: exercise, liveSet: liveSet, plannedSeconds: liveSet.prescription.seconds ?? liveItem.plan.seconds)
                        .padding(.top, Self.small ? 0 : 4)
                    if let note = liveSet.note {
                        Text(note)
                            .font(.footnote)
                            .padding(.top, 4)
                    }
                    Text(WatchFormat.hint(liveSet.prescription))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            // The band stays at the foot of the face, whatever the screen's size; the rest scrolls above it.
            .safeAreaInset(edge: .bottom, spacing: 4) {
                ActionBand(title: bandTitle(liveSet.prescription.kind, timed: draft.seconds != nil)) {
                    done(draft)
                } trailing: {
                    if rated {
                        Button {
                            rate(draft)
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(WatchInk.onAccent.opacity(0.16), in: .circle)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Easy or missed")
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .onAppear { prepare(exercise: exercise, prescription: liveSet.prescription) }
        }
    }

    /// The smallest Watches (40 and 41 mm), where the set and the band only fit one screen smaller.
    private static let small = WKInterfaceDevice.current().screenBounds.width < 180
    /// The big numbers' size.
    private static let numberSize: CGFloat = small ? 38 : 54

    /// Sets that are rated: everything but warm-ups and rep-outs, which log as done.
    private static func isRated(_ kind: SetKind) -> Bool { kind != .warmup && kind != .repOut }

    private func bandTitle(_ kind: SetKind, timed: Bool) -> String {
        if timed || kind == .warmup { return "Done" }
        return kind == .repOut ? "Log reps" : SetRating.orange.label
    }

    /// A word beside the dots for sets that aren't plain work.
    private static func kindWord(_ kind: SetKind) -> String? {
        switch kind {
        case .warmup: "Warm-up"
        case .repOut: "Rep-out"
        case .findingWeight: "Finding weight"
        case .deload: "Deload"
        case .working: nil
        }
    }

    // MARK: Values

    /// The set as one big "70 × 7": each number over a line and its unit, the one the crown moves
    /// underlined in the accent. A tap on either gives it the crown.
    private func values(exercise: Exercise, liveSet: LiveSet, plannedSeconds: Int?) -> some View {
        let hasLoad = exercise.loadBasis != .none
        let seconds = timedSeconds(exercise, liveSet: liveSet, planned: plannedSeconds)
        let load = WatchFormat.loadParts(loadKg, unit: model.unit, basis: exercise.loadBasis)
        return HStack(alignment: .top, spacing: 6) {
            if hasLoad {
                number(load.value, unit: load.unit, selected: editing == .load && !loads.isEmpty)
                    .onTapGesture { select(.load) }
                    .accessibilityLabel("Weight")
                    .accessibilityValue(WatchFormat.load(loadKg, unit: model.unit, basis: exercise.loadBasis))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAdjustableAction { direction in
                        select(.load)
                        nudge(direction == .increment ? 1 : -1)
                    }
                // A carry's load is held for its seconds, not multiplied by them.
                Text(seconds == nil ? "×" : "for")
                    .font(.system(size: seconds == nil ? 26 : 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, seconds == nil ? 14 : 22)
                    .accessibilityHidden(true)
            }
            if let seconds {
                number(seconds < 60 ? "\(seconds)" : WatchFormat.clock(seconds), unit: seconds < 60 ? "seconds" : "minutes", selected: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("For \(WatchFormat.duration(seconds))")
            } else {
                number("\(reps)", unit: liveSet.prescription.kind == .repOut ? "or more" : "reps", selected: editing == .reps)
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
        .digitalCrownRotation(
            $crown, from: 0, through: crownUpperBound, by: 1, sensitivity: .medium,
            isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { apply() }
    }

    private func number(_ value: String, unit: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: Self.small ? 2 : 4) {
            // A fixed height, so a long load shrunk to fit keeps its line and unit level with the reps'.
            Text(value)
                .font(.system(size: Self.numberSize, weight: .bold))
                .monospacedDigit()
                .tracking(-2)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(height: Self.numberSize + 2, alignment: .bottom)
            Capsule()
                .fill(selected ? Color.accentColor : .clear)
                .frame(height: 3)
            Text(unit)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(.rect)
        // One element, the number and its unit together, for the label and actions put on it.
        .accessibilityElement(children: .ignore)
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
