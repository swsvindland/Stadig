import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// The scoreboard's set: what's in front of you at cinema scale, and the zones that log it.

/// The set at cinema scale: the exercise, which set and last time, "70 kg × 7" as large as fits,
/// the plates on a drawn bar, and the zones that log it.
struct BoardSet: View {
    @Environment(AppModel.self) private var model
    @Environment(SetDraft.self) private var draft
    let live: LiveSession
    let item: Int
    let set: Int
    let kind: FloorSet
    @State private var editing = false
    @State private var askMissed = false

    var body: some View {
        let liveItem = live.items[item]
        let liveSet = liveItem.sets[set]
        let exercise = model.catalog.resolve(liveItem.exerciseID)
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow(liveItem, exercise)).font(.headline.weight(.semibold)).textCase(.uppercase).tracking(1.4)
                .foregroundStyle(Ink.text3)
            Text(exercise.name)
                .font(.system(size: 60, weight: .heavy)).tracking(-2.4)
                .foregroundStyle(Ink.text)
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
            position(liveItem, exercise)
                .padding(.top, 8)
            Spacer(minLength: 12)
            hero(exercise)
            Spacer(minLength: 12)
            if let plates = model.boardPlates(item: liveItem, exercise: exercise, load: draft.load) {
                BoardPlates(plates: plates, scale: 1)
            }
            Spacer(minLength: 16)
            HStack(alignment: .firstTextBaseline) {
                Text(prompt(liveSet)).font(.title2.weight(.semibold)).foregroundStyle(Ink.text2)
                Spacer()
                if editable(exercise) {
                    Text("Tap the numbers to change them").font(.title3).foregroundStyle(Ink.text3)
                }
            }
            .padding(.bottom, 12)
            zones(liveSet)
        }
        .padding(.horizontal, 44)
        .padding(.top, 28)
        .padding(.bottom, 32)
        .background { keys }
        .onAppear { draft.prepare(item: item, set: set, model: model) }
        .confirmationDialog("How many did you get?", isPresented: $askMissed, titleVisibility: .visible) {
            // The dock's question, the same answers.
            let target = liveSet.prescription.targetReps
            ForEach((max(0, target - 6)..<target).reversed(), id: \.self) { n in
                Button("\(n) reps") {
                    draft.reps = n
                    log(.red)
                }
            }
        } message: {
            Text("Missed reps are just data. The next set adjusts.")
        }
    }

    // MARK: Pieces

    /// "Main lift · Chest · Exercise 1 of 6".
    private func eyebrow(_ item: LiveItem, _ exercise: Exercise) -> String {
        var parts = [item.plan.supersetGroup != nil ? "Superset" : item.plan.block.label]
        if let muscle = exercise.primaryMuscles.first, exercise.kind == .strength { parts.append(muscle.label) }
        parts.append("Exercise \(self.item + 1) of \(live.items.count)")
        return parts.joined(separator: " · ")
    }

    /// "Set 2 of 3", a strip of the sets, and last time.
    private func position(_ item: LiveItem, _ exercise: Exercise) -> some View {
        let warmup = item.sets[set].prescription.kind == .warmup
        let indices = item.sets.indices.filter { (item.sets[$0].prescription.kind == .warmup) == warmup }
        let number = (indices.firstIndex(of: set) ?? 0) + 1
        let label =
            indices.count <= 1 && !item.plan.isStrength ? item.plan.block.label : "\(warmup ? "Warm-up" : "Set") \(number) of \(indices.count)"
        let last =
            warmup || !item.plan.isStrength
            ? nil : model.lastTime(exercise, setNumber: number).map { Format.logged($0, exercise: exercise, unit: model.gym.unit) }
        return HStack(spacing: 16) {
            Text(label).font(.system(size: 32, weight: .bold)).tracking(-0.8).foregroundStyle(Ink.text).fixedSize()
            if indices.count > 1 {
                HStack(spacing: 5) {
                    ForEach(indices, id: \.self) { index in
                        SetSegment(state: index == set ? .now : (item.sets[index].isOpen ? .pending : .done))
                    }
                }
            }
            if let last {
                Text("Last time \(last)").font(.system(size: 32, weight: .medium)).tracking(-0.8).foregroundStyle(Ink.text3)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.leading, 10)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The weight and reps as large as the room allows; a tap opens them to change.
    private func hero(_ exercise: Exercise) -> some View {
        Button {
            editing = true
        } label: {
            BoardHero(value: heroValue(exercise))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!editable(exercise))
        .accessibilityLabel(spokenValue(exercise))
        .accessibilityHint(editable(exercise) ? "Change the weight or reps" : "")
        .accessibilityIdentifier("scoreboard.set")
        .popover(isPresented: $editing) { editor(exercise) }
    }

    private func editor(_ exercise: Exercise) -> some View {
        @Bindable var draft = draft
        let increments = model.gymForToday.increments(for: exercise)
        return HStack(spacing: 12) {
            if hasLoad(exercise) {
                LoadControl(
                    title: SetLogger.loadTitle(exercise), load: $draft.load, increments: increments,
                    basis: exercise.loadBasis, identifier: "scoreboard.load")
            }
            if !isTimed {
                Stepperish(
                    title: "Reps", value: "\(draft.reps)", minus: { draft.reps = max(0, draft.reps - 1) }, plus: { draft.reps += 1 },
                    entry: .init(unit: "reps", text: "\(draft.reps)") { text in if let n = Stepperish.typedReps(text) { draft.reps = n } },
                    identifier: "scoreboard.reps"
                )
                .frame(width: 240)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .environment(\.sessionScale, .large)
        .presentationCompactAdaptation(.popover)
    }

    private var isTimed: Bool {
        if case .timed = kind { return true }
        return false
    }

    private func hasLoad(_ exercise: Exercise) -> Bool {
        exercise.loadBasis != .none && kind != .done && !isTimed
    }

    private func editable(_ exercise: Exercise) -> Bool { kind != .done && !isTimed }

    private func heroValue(_ exercise: Exercise) -> BoardHero.Value {
        switch kind {
        case .timed(let seconds):
            return .clock(start: draft.timerStart, seconds: seconds)
        case .done:
            return .reps(live.items[item].sets[set].prescription.targetReps)
        case .rated, .warmup, .repOut:
            let load = Format.load(draft.load, unit: model.gym.unit, basis: exercise.loadBasis)
            let parts = load.split(separator: " ", maxSplits: 1).map(String.init)
            guard exercise.loadBasis != .none, let number = parts.first, number.contains(where: \.isNumber) else {
                return .reps(draft.reps)
            }
            return .load(number, unit: parts.count > 1 ? parts[1] : "", reps: draft.reps)
        }
    }

    private func spokenValue(_ exercise: Exercise) -> String {
        switch heroValue(exercise) {
        case .load(let number, let unit, let reps): "\(number) \(unit) for \(reps)"
        case .reps(let reps): "\(reps) reps"
        case .clock(_, let seconds): Format.duration(seconds)
        }
    }

    private func prompt(_ set: LiveSet) -> String {
        switch kind {
        case .rated: "How did it feel?"
        case .warmup: "Warm-up: log it when it's done"
        case .repOut: set.prescription.stopAtFormBreakdown ? "Stop when your form slips" : "As many as you can"
        case .timed(let seconds): draft.timerStart == nil ? "Hold for \(Format.duration(seconds))" : "Holding"
        case .done: "Log it when it's done"
        }
    }

    // MARK: Zones, as the dock's buttons

    @ViewBuilder
    private func zones(_ set: LiveSet) -> some View {
        HStack(spacing: 14) {
            switch kind {
            case .rated:
                ForEach(Array(SetRating.allCases.enumerated()), id: \.element) { index, rating in
                    BoardZone(
                        title: rating.label, detail: rating.shortDetail, dot: rating == .orange ? nil : rating.color, filled: rating == .orange
                    ) {
                        if rating == .red, draft.reps >= set.prescription.targetReps { askMissed = true } else { log(rating) }
                    }
                    // Easy, Just right, Missed: 1, 2, 3, left to right as they're drawn.
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    .accessibilityLabel("\(rating.label): \(rating.detail)")
                    .accessibilityIdentifier("scoreboard.rating\(rating.rawValue.identifierSuffix)")
                }
            case .repOut:
                BoardZone(title: "−1", detail: "One fewer") { draft.reps = max(0, draft.reps - 1) }
                    .keyboardShortcut("-", modifiers: [])
                    .accessibilityLabel("One fewer rep")
                BoardZone(title: "Log \(draft.reps)", detail: "reps", filled: true) { log(nil) }
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel("Log \(draft.reps) reps")
                    .accessibilityIdentifier("scoreboard.logRepOut")
                BoardZone(title: "+1", detail: "One more") { draft.reps += 1 }
                    .keyboardShortcut("=", modifiers: [])
                    .accessibilityLabel("One more rep")
            case .warmup:
                BoardZone(title: "Done", detail: "Warm-up", filled: true) { log(nil) }
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("scoreboard.done")
            case .timed(let seconds):
                if draft.timerStart == nil {
                    BoardZone(title: "Start", detail: Format.duration(seconds), filled: true) { draft.timerStart = Date() }
                        .keyboardShortcut(.return, modifiers: [])
                        .accessibilityIdentifier("scoreboard.start")
                } else {
                    BoardZone(title: "Done", detail: "Log the time", filled: true) { logTimed() }
                        .keyboardShortcut(.return, modifiers: [])
                        .accessibilityIdentifier("scoreboard.done")
                }
            case .done:
                BoardZone(title: "Done", detail: "\(set.prescription.targetReps) reps", filled: true) { logTimed() }
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("scoreboard.done")
            }
        }
    }

    /// The wide layout's keys for the weight and reps, which the board has no buttons for.
    @ViewBuilder
    private var keys: some View {
        if case .rated = kind, let live = model.live, live.items.indices.contains(item) {
            let exercise = model.catalog.resolve(live.items[item].exerciseID)
            let increments = model.gymForToday.increments(for: exercise)
            Group {
                if hasLoad(exercise) {
                    Button("Heavier") { draft.load = increments.step(draft.load, direction: 1) }.keyboardShortcut(.upArrow, modifiers: [])
                    Button("Lighter") { draft.load = increments.step(draft.load, direction: -1) }.keyboardShortcut(.downArrow, modifiers: [])
                }
                Button("One More Rep") { draft.reps += 1 }.keyboardShortcut("=", modifiers: [])
                Button("One Fewer Rep") { draft.reps = max(0, draft.reps - 1) }.keyboardShortcut("-", modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func log(_ rating: SetRating?) {
        draft.log(item: item, set: set, rating: rating, model: model)
    }

    private func logTimed() {
        draft.logTimed(item: item, set: set, model: model)
    }
}

/// One of the board's big buttons: a word, a line under it, and a rating's dot or the accent's
/// fill. 150 points tall, for a knuckle.
struct BoardZone: View {
    let title: String
    let detail: String
    var dot: Color?
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 14) {
                    if let dot { Circle().fill(dot).frame(width: 18, height: 18) }
                    Text(title).font(.system(size: 42, weight: .heavy)).tracking(-1.5)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                Text(detail).font(.system(size: 21, weight: .medium))
                    .foregroundStyle(filled ? Ink.onAccent.opacity(0.8) : Ink.text2)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(filled ? Ink.onAccent : Ink.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(filled ? Color.accentColor : Ink.raised, in: .rect(cornerRadius: 32, style: .continuous))
            .contentShape(.rect(cornerRadius: 32))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }
}

/// One set in the strip under the exercise: filled once done, outlined for the one in front of you.
private struct SetSegment: View {
    enum State { case done, now, pending }
    let state: State

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            switch state {
            case .done: shape.fill(Color.accentColor)
            case .now: shape.strokeBorder(Color.accentColor, lineWidth: 2)
            case .pending: shape.fill(Ink.track)
            }
        }
        .frame(width: 34, height: 12)
        .accessibilityHidden(true)
    }
}

/// "70 kg × 7" (or the reps, or the clock) as large as the room allows, up to 220 points.
private struct BoardHero: View {
    enum Value: Hashable {
        case load(String, unit: String, reps: Int)
        case reps(Int)
        case clock(start: Date?, seconds: Int)
    }

    let value: Value
    /// Largest first: the first that fits is shown.
    private static let sizes: [CGFloat] = [220, 200, 180, 160, 140, 120, 100, 84, 72]

    var body: some View {
        switch value {
        case .clock(let start?, let seconds):
            TimelineView(.periodic(from: start, by: 1)) { context in
                let left = max(0, Double(seconds) - context.date.timeIntervalSince(start))
                sized { line(Format.clock(Int(left.rounded(.up))), size: $0) }
            }
        case .clock(nil, let seconds):
            sized { line(Format.clock(seconds), size: $0) }
        case .reps(let reps):
            sized { line("\(reps)", unit: "reps", size: $0) }
        case .load(let number, let unit, let reps):
            sized { size in
                HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
                    line(number, unit: unit, size: size)
                    Text("×").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(Ink.text3)
                    Text("\(reps)").font(.system(size: size, weight: .heavy)).tracking(-size * 0.05).foregroundStyle(Ink.text)
                }
                .frame(height: size * 0.8)
            }
        }
    }

    private func sized<Content: View>(@ViewBuilder _ content: @escaping (CGFloat) -> Content) -> some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            ForEach(Self.sizes, id: \.self) { size in
                content(size).fixedSize()
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    /// A line of numerals cropped to the digits' height, with its unit small beside it.
    private func line(_ text: String, unit: String? = nil, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.04) {
            Text(text).font(.system(size: size, weight: .heavy)).tracking(-size * 0.05).foregroundStyle(Ink.text)
            if let unit, !unit.isEmpty {
                Text(unit).font(.system(size: max(24, size * 0.3), weight: .bold)).foregroundStyle(Ink.text2)
            }
        }
        .frame(height: size * 0.8)
    }
}
