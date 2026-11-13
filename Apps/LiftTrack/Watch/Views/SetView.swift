import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// One loaded set, as the design's face: the exercise and where the set sits, the set as one big
/// "70 × 7" over the crown's scale (the crown on the load, snapped to loads the gym can make, or, a
/// tap on the reps away, on the reps), and the band across the foot that Double Tap presses: Just
/// right for a rated set, Done or Log reps otherwise. A swipe up or down on a rated set opens Easy and
/// Missed. Straight after a rest that ran out on its own, the face is in the accent for a moment
/// (`GoFace`), with the set's note or what it asks for.
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
            // The face is the whole screen, its band on the foot, its top line beside the time.
            GeometryReader { screen in
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(exercise.name)
                                .faceEyebrow(Color.accentColor)
                                .faceTopLine()
                                .accessibilityAddTraits(.isHeader)
                            HStack(spacing: 7) {
                                SetDots(index: set, sets: liveItem.sets)
                                if let kind = Self.kindWord(liveSet.prescription.kind) {
                                    Text(kind).faceFont(11, weight: .semibold).foregroundStyle(WatchInk.text3).lineLimit(1)
                                }
                            }
                        }
                        Spacer(minLength: 2)
                        values(exercise: exercise, liveSet: liveSet, plannedSeconds: liveSet.prescription.seconds ?? liveItem.plan.seconds)
                            .padding(.bottom, WatchFace.small ? 8 : 12)
                    }
                    .padding(.horizontal, WatchFace.margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    ActionBand(title: bandTitle(liveSet.prescription.kind, timed: draft.seconds != nil)) { done(draft) }
                        .accessibilityHint(rated ? "Swipe up or down for Easy or Missed." : "")
                }
                .frame(width: screen.size.width, height: screen.size.height)
                .background(alignment: .topLeading) {
                    // Beside the crown, while it moves a number.
                    if crownFocused, draft.seconds == nil {
                        CrownScale(value: crown, height: 62 * WatchFace.scale)
                            .position(x: screen.size.width - 7.5, y: screen.size.height * 0.285)
                    }
                }
            }
            .ignoresSafeArea()
            .contentShape(.rect)
            // Not just right: a swipe either way opens the three ratings.
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { drag in
                    guard rated, model.go == nil, abs(drag.translation.height) > 30,
                        abs(drag.translation.height) > abs(drag.translation.width) * 1.5
                    else { return }
                    rate(draft)
                },
                including: rated ? .all : .subviews
            )
            .accessibilityAction(named: "Easy or Missed") { if rated { rate(draft) } }
            .overlay {
                if let go = model.go {
                    GoFace(item: item, set: set, go: go, loadKg: draft.loadKg, reps: reps)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.go)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { prepare(exercise: exercise, prescription: liveSet.prescription) }
        }
    }

    /// The big numbers' size, at the design's 45 mm (they scale with the screen).
    private static let numberSize: CGFloat = 70

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
        let repOut = liveSet.prescription.kind == .repOut
        let count = seconds.map { $0 < 60 ? "\($0)" : WatchFormat.clock($0) } ?? "\(reps)\(repOut ? "+" : "")"
        // Both numbers at one size, as large as the face allows: beside them, the margins, the "×"
        // and the crown's scale.
        let points = WatchFace.numeralSize(
            Self.numberSize, fitting: (hasLoad ? [load.value] : []) + [count],
            besides: WatchFace.margin * 2 + (hasLoad ? 14 + 20 * WatchFace.scale : 0) + 10)
        return HStack(alignment: .top, spacing: 7) {
            if hasLoad {
                number(load.value, unit: load.unit, points: points, selected: editing == .load && !loads.isEmpty)
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
                    .font(.system(size: (seconds == nil ? 30 : 15) * points / Self.numberSize, weight: .semibold))
                    .foregroundStyle(WatchInk.text3)
                    .frame(height: points * 0.9)
                    .accessibilityHidden(true)
            }
            if let seconds {
                number(count, unit: seconds < 60 ? "seconds" : "minutes", points: points, selected: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("For \(WatchFormat.duration(seconds))")
            } else {
                number("\(reps)", unit: repOut ? "or more" : "reps", points: points, selected: editing == .reps, plus: repOut)
                    .frame(minWidth: 44 * WatchFace.scale, alignment: .leading)
                    .onTapGesture { select(.reps) }
                    .accessibilityLabel(repOut ? "Reps, or more" : "Reps")
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

    private func number(_ value: String, unit: String, points: CGFloat, selected: Bool, plus: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            BigNumber(value: value, points: points, plus: plus)
            Capsule()
                .fill(selected ? Color.accentColor : .clear)
                .frame(height: 3)
            Text(unit)
                .faceFont(13, weight: .semibold)
                .foregroundStyle(selected ? Color.accentColor : WatchInk.text3)
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
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
