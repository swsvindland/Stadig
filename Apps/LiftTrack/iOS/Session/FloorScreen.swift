import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

// Floor mode (docs/lift-track.md): the iPhone set down on the floor or a bench a metre or two away,
// the hands chalky. The session becomes a scoreboard and the whole screen is the button: a tap
// anywhere is the dock's main button, a swipe up or down (starting anywhere) its others. Picked up,
// it's the normal screen with its dock again.

/// The floor: the set in front of you on a slab of the accent, or the rest as a gauge the height of
/// the screen.
struct FloorScreen: View {
    @Environment(AppModel.self) private var model
    let content: FloorContent
    let floor: FloorMode
    /// A miss with the reps still at the target: the session asks how many, as the dock does, from
    /// a view that outlives the set (asked from the set's own view, answering it closed the session).
    let missed: (SetTarget) -> Void

    var body: some View {
        if let live = model.live {
            switch content {
            case .rest:
                if let rest = model.activeRest { FloorRest(live: live, rest: rest, floor: floor) }
            case .set(let item, let set, let kind):
                if live.items.indices.contains(item), live.items[item].sets.indices.contains(set) {
                    FloorSetView(live: live, item: item, set: set, kind: kind, floor: floor, missed: missed)
                        .id(live.items[item].sets[set].id)
                }
            }
        }
    }
}

// MARK: - The set

/// The set in front of you: the exercise, which set with a strip of them, the weight and reps as
/// large as the screen allows, last time and the plates, and what each gesture does at the edges.
private struct FloorSetView: View {
    @Environment(AppModel.self) private var model
    @Environment(SetDraft.self) private var draft
    /// The design's 30 points, growing with the text size like the words round it.
    @ScaledMetric(relativeTo: .title) private var nameSize: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var actionSize: CGFloat = 44
    let live: LiveSession
    let item: Int
    let set: Int
    let kind: FloorSet
    let floor: FloorMode
    let missed: (SetTarget) -> Void

    var body: some View {
        let liveItem = live.items[item]
        let liveSet = liveItem.sets[set]
        let exercise = model.catalog.resolve(liveItem.exerciseID)
        let value = heroValue(liveItem, liveSet, exercise)
        ZStack {
            // The whole screen, edge to edge, is the button.
            Color.accentColor.ignoresSafeArea()
            content(liveItem, liveSet, exercise, value)
        }
        .floorGestures(tap: tap, up: swipeUp, down: swipeDown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(liveItem, liveSet, exercise, value))
        .accessibilityHint(hint)
        // Over the session's normal screen: VoiceOver stays on the floor, not the dock under it.
        .accessibilityAddTraits([.isButton, .isModal])
        .accessibilityAction { tap() }
        .modifier(SwipeActions(kind: kind, up: up, down: down))
        .accessibilityIdentifier("floor.set")
        .onAppear { draft.prepare(item: item, set: set, model: model) }
    }

    private func content(_ liveItem: LiveItem, _ liveSet: LiveSet, _ exercise: Exercise, _ value: FloorHero.Value) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FloorEdge(text: upLabel, up: true)
            header(liveItem, liveSet, exercise)
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 10) {
                FloorHero(value: value)
                details(liveItem, liveSet, exercise)
            }
            .padding(.top, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap anywhere").floorEyebrow()
                    Text(tapLabel)
                        .font(.system(size: actionSize, weight: .heavy)).tracking(-1.4)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: "tray.and.arrow.up").font(.body.weight(.semibold))
                    Text("Pick up to edit").font(.footnote.weight(.semibold))
                }
                .padding(.bottom, 4)
            }
            .padding(.top, 12)
            FloorEdge(text: downLabel, up: false)
                .padding(.top, 18)
        }
        .foregroundStyle(Ink.onAccent)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pieces

    /// "Set 2 of 3", "Warm-up 1 of 3", or a drill's block, and the sets in the strip: the warm-ups
    /// during the warm-ups, the work sets after.
    private func position(_ item: LiveItem, _ set: LiveSet) -> (label: String, indices: [Int]) {
        let warmup = set.prescription.kind == .warmup
        let indices = item.sets.indices.filter { (item.sets[$0].prescription.kind == .warmup) == warmup }
        let number = (indices.firstIndex(of: self.set) ?? 0) + 1
        let label =
            indices.count <= 1 && !item.plan.isStrength
            ? item.plan.block.label
            : "\(warmup ? "Warm-up" : "Set") \(number) of \(indices.count)"
        return (label, indices)
    }

    private func header(_ item: LiveItem, _ set: LiveSet, _ exercise: Exercise) -> some View {
        let (label, indices) = position(item, set)
        return VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name)
                .font(.system(size: nameSize, weight: .bold)).tracking(-1)
                .lineLimit(2).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text(label).font(.title3.weight(.bold)).lineLimit(1).fixedSize()
                if indices.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(indices, id: \.self) { index in
                            Segment(state: index == self.set ? .now : (item.sets[index].isOpen ? .pending : .done))
                        }
                    }
                }
            }
        }
    }

    /// What it was last time and the plates; a rep-out's or a timed set's instruction.
    @ViewBuilder
    private func details(_ item: LiveItem, _ set: LiveSet, _ exercise: Exercise) -> some View {
        let lines = detailLines(item, set, exercise)
        if !lines.isEmpty {
            Text(lines.joined(separator: " · "))
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailLines(_ item: LiveItem, _ set: LiveSet, _ exercise: Exercise) -> [String] {
        var lines: [String] = []
        switch kind {
        case .repOut:
            lines.append(set.prescription.stopAtFormBreakdown ? "Stop when your form slips" : "As many as you can")
        case .timed(let seconds):
            lines.append(draft.timerStart == nil ? "Hold for \(Format.duration(seconds))" : "Holding")
        case .done where exercise.unilateral:
            lines.append("Each side")
        default:
            break
        }
        if set.prescription.kind != .warmup, item.plan.isStrength {
            let number = item.sets[...self.set].filter { $0.prescription.kind != .warmup }.count
            if let last = model.lastTime(exercise, setNumber: number) {
                lines.append("Last time \(Format.logged(last, exercise: exercise, unit: model.gym.unit))")
            }
        }
        let increments = model.gymForToday.increments(for: exercise)
        if item.plan.isStrength, exercise.equipment.platePaired,
            let side = Format.side(increments.platesPerSide(draft.load), unit: increments.gym.unit)
        {
            lines.append(side)
        }
        return lines
    }

    private func heroValue(_ item: LiveItem, _ set: LiveSet, _ exercise: Exercise) -> FloorHero.Value {
        switch kind {
        case .timed(let seconds):
            return .clock(start: draft.timerStart, seconds: seconds)
        case .done:
            return .reps(set.prescription.targetReps)
        case .rated, .warmup, .repOut:
            let load = Format.load(draft.load, unit: model.gym.unit, basis: exercise.loadBasis)
            let parts = load.split(separator: " ", maxSplits: 1).map(String.init)
            // A number to lift: "70 kg", "+10 kg", "15 kg each". Bodyweight is the reps alone.
            guard exercise.loadBasis != .none, let number = parts.first, number.contains(where: \.isNumber) else {
                return .reps(draft.reps)
            }
            return .load(number, unit: parts.count > 1 ? parts[1] : "", reps: draft.reps)
        }
    }

    private var upLabel: String? {
        switch kind {
        case .rated: "Swipe up · Easy"
        case .repOut: "Swipe up · One more rep"
        default: nil
        }
    }

    private var downLabel: String? {
        switch kind {
        case .rated: "Swipe down · Missed"
        case .repOut: "Swipe down · One fewer"
        default: nil
        }
    }

    private var tapLabel: String {
        switch kind {
        case .rated: SetRating.orange.label
        case .warmup, .done: "Done"
        case .repOut: "Log \(draft.reps) reps"
        case .timed: draft.timerStart == nil ? "Start" : "Done"
        }
    }

    private var hint: String {
        switch kind {
        case .rated: "Double-tap to log it as Just right. Easy and Missed are in the actions."
        case .repOut: "Swipe up or down to count the reps, double-tap to log them."
        case .timed: draft.timerStart == nil ? "Double-tap to start the clock." : "Double-tap when you're done."
        case .warmup, .done: "Double-tap to log it."
        }
    }

    private func spoken(_ item: LiveItem, _ set: LiveSet, _ exercise: Exercise, _ value: FloorHero.Value) -> String {
        let what: String =
            switch value {
            case .load(let number, let unit, let reps): "\(number) \(unit) for \(reps)"
            case .reps(let reps): "\(reps) reps"
            case .clock(_, let seconds): Format.duration(seconds)
            }
        let details = detailLines(item, set, exercise)
        return (["Floor mode", exercise.name, position(item, set).label, what] + details).joined(separator: ", ")
    }

    // MARK: Gestures, as the dock's buttons

    private var swipeUp: (() -> Void)? { kind.swipes ? { up() } : nil }
    private var swipeDown: (() -> Void)? { kind.swipes ? { down() } : nil }

    private func tap() {
        switch kind {
        case .rated: log(.orange)
        case .warmup, .repOut: log(nil)
        case .done: logTimed()
        case .timed:
            if draft.timerStart == nil {
                draft.timerStart = Date()
                floor.nudged()
            } else {
                logTimed()
            }
        }
    }

    private func up() {
        switch kind {
        case .rated: log(.green)
        case .repOut:
            draft.reps += 1
            floor.nudged()
        default: break
        }
    }

    private func down() {
        switch kind {
        case .rated:
            // As the dock's Missed: with the reps still at the target, how many there were.
            if let target = model.live?.items[item].sets[set].prescription.targetReps, draft.reps >= target {
                missed(SetTarget(item: item, set: set))
            } else {
                log(.red)
            }
        case .repOut:
            draft.reps = max(0, draft.reps - 1)
            floor.nudged()
        default: break
        }
    }

    private func log(_ rating: SetRating?) {
        draft.log(item: item, set: set, rating: rating, model: model)
        floor.logged()
    }

    private func logTimed() {
        draft.logTimed(item: item, set: set, model: model)
        floor.logged()
    }
}

/// The swipes as VoiceOver's actions, where it takes swipes up and down for itself: Easy and Missed
/// by name, a rep-out's count as an adjustable value.
private struct SwipeActions: ViewModifier {
    let kind: FloorSet
    let up: () -> Void
    let down: () -> Void

    func body(content: Content) -> some View {
        switch kind {
        case .rated:
            content
                .accessibilityAction(named: SetRating.green.label, up)
                .accessibilityAction(named: SetRating.red.label, down)
        case .repOut:
            content.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: up()
                case .decrement: down()
                @unknown default: break
                }
            }
        case .warmup, .timed, .done:
            content
        }
    }
}

/// One set in the strip: filled once done, outlined for the one in front of you.
private struct Segment: View {
    enum State { case done, now, pending }
    let state: State

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            switch state {
            case .done: shape.fill(Ink.onAccent)
            case .now: shape.strokeBorder(Ink.onAccent, lineWidth: 3)
            case .pending: shape.fill(Ink.onAccent.opacity(0.22))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)
        .accessibilityHidden(true)
    }
}

/// The weight and reps (or the reps, or the clock) as large as the room under the header allows:
/// "70 kg" over "× 7" at up to 240 points on a phone in portrait.
private struct FloorHero: View {
    enum Value: Hashable {
        case load(String, unit: String, reps: Int)
        case reps(Int)
        case clock(start: Date?, seconds: Int)
    }

    let value: Value
    /// Largest first: the first that fits is shown.
    private static let sizes: [CGFloat] = [240, 210, 184, 160, 140, 120, 104, 88, 72, 60, 48]

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
                VStack(alignment: .leading, spacing: 0) {
                    line(number, unit: unit, size: size)
                    HStack(alignment: .center, spacing: size * 0.06) {
                        Text("×").font(.system(size: size * 0.58, weight: .semibold))
                        Text("\(reps)").font(.system(size: size, weight: .heavy)).tracking(-size * 0.05)
                    }
                    .frame(height: size * 0.8)
                }
            }
        }
    }

    /// The largest of the sizes that fits.
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

    /// One line of numerals, cropped to the digits' height (a line's leading would leave a gap above
    /// and below the size of a word), with its unit small beside it.
    private func line(_ text: String, unit: String? = nil, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.04) {
            Text(text).font(.system(size: size, weight: .heavy)).tracking(-size * 0.05)
            if let unit, !unit.isEmpty {
                Text(unit).font(.system(size: max(17, size * 0.14), weight: .bold))
            }
        }
        .frame(height: size * 0.8)
    }
}

// MARK: - The rest

/// The rest, where the whole screen is the gauge: the accent fills it from the bottom and drains as
/// the rest runs out (the dock's ruler stood on end, ticked every 10 s and longer every 30), behind
/// the countdown and the set that's next. A tap skips it; swipes give or take 15 seconds.
private struct FloorRest: View {
    @Environment(AppModel.self) private var model
    @Environment(SetDraft.self) private var draft
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let live: LiveSession
    let rest: RestState
    let floor: FloorMode

    var body: some View {
        let total = max(1, rest.endsAt.timeIntervalSince(rest.started))
        let logged = model.justLogged(after: rest)
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            TimelineView(.periodic(from: rest.started, by: 1)) { context in
                let left = max(0, rest.endsAt.timeIntervalSince(context.date))
                // The fill heads for where it'll be a second from now and takes the second to get
                // there, so it drains smoothly; with Reduce Motion it steps once a second.
                let fraction = (reduceMotion ? left : max(0, left - 1)) / total
                let seconds = Int(left.rounded())
                GeometryReader { screen in
                    let height = screen.size.height
                    let filled = height * fraction
                    // Only the fill's edge moves smoothly: the numbers change on the second.
                    let drain: Animation? = reduceMotion ? nil : .linear(duration: 1)
                    ZStack(alignment: .bottom) {
                        Ink.ground
                        Color.accentColor.animation(drain) { $0.frame(height: filled) }
                        layer(onFill: false, seconds: seconds, total: total, insets: insets)
                            .mask(alignment: .top) { Rectangle().animation(drain) { $0.frame(height: height - filled) } }
                        layer(onFill: true, seconds: seconds, total: total, insets: insets)
                            .mask(alignment: .bottom) { Rectangle().animation(drain) { $0.frame(height: filled) } }
                    }
                }
                // The whole screen, edge to edge, is the gauge and the button.
                .ignoresSafeArea()
                .floorGestures(tap: skip, up: { extend(by: 15) }, down: { extend(by: -15) })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Floor mode, rest")
                .accessibilityValue("\(Format.duration(seconds)) left")
                .accessibilityHint("Double-tap to skip the rest. Swipe up or down for 15 seconds more or less.")
                .accessibilityAddTraits([.isButton, .isModal])
                .accessibilityAction { skip() }
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: extend(by: 15)
                    case .decrement: extend(by: -15)
                    @unknown default: break
                    }
                }
                .modifier(UndoAction(logged: logged, undo: undo))
                .accessibilityIdentifier("floor.rest")
            }
        }
        // Undo is drawn on the gauge, twice like everything on it; this is the button over it, so a
        // tap there takes the set back rather than skipping the rest.
        .overlayPreferenceValue(UndoBounds.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let logged, logged.undoable {
                    let rect = proxy[anchor]
                    Button(action: undo) {
                        Color.clear.contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width + 40, height: max(56, rect.height + 28))
                    .position(x: rect.midX - 8, y: rect.midY)
                    .accessibilityLabel("Undo \(logged.name.lowercased())")
                    .accessibilityIdentifier("floor.undo")
                }
            }
        }
    }

    private func undo() {
        draft.undo(model: model)
        floor.nudged()
    }

    /// Everything on the gauge, in the ground's colours or the accent's ink: drawn twice and cut at
    /// the fill's edge, so the countdown and the next set read on either side of it.
    private func layer(onFill: Bool, seconds: Int, total: Double, insets: EdgeInsets) -> some View {
        let primary = onFill ? Ink.onAccent : Ink.text
        let secondary = onFill ? Ink.onAccent.opacity(0.85) : Ink.text2
        return ZStack(alignment: .topLeading) {
            Ticks(total: total, color: onFill ? Ink.onAccent.opacity(0.6) : Ink.text3)
            FloorRestContent(live: live, rest: rest, seconds: seconds, primary: primary, secondary: secondary, onFill: onFill)
                .padding(insets)
        }
    }

    private func skip() {
        model.update { $0.endRest() }
        floor.nudged()
    }

    private func extend(by seconds: Int) {
        model.update { $0.extendRest(by: seconds) }
        floor.nudged()
    }
}

/// The rest's words and numbers, in one pair of colours.
private struct FloorRestContent: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .largeTitle) private var actionSize: CGFloat = 44
    let live: LiveSession
    let rest: RestState
    let seconds: Int
    let primary: Color
    let secondary: Color
    /// The copy on the accent's fill, which says where Undo is for the button over it.
    let onFill: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FloorEdge(text: "Swipe up · 15 s more", up: true)
                .foregroundStyle(secondary)
            if let logged = model.justLogged(after: rest) {
                HStack(spacing: 8) {
                    if let rating = logged.rating { Circle().fill(rating.color).frame(width: 9, height: 9) }
                    Text(logged.text).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 12)
                    if logged.undoable {
                        Text("Undo")
                            .font(.headline)
                            .foregroundStyle(onFill ? Ink.onAccent : Color.accentColor)
                            .anchorPreference(key: UndoBounds.self, value: .bounds) { onFill ? $0 : nil }
                    }
                }
                .foregroundStyle(primary)
                .padding(.top, 20)
            }
            Text(Format.clock(seconds))
                .font(.system(size: 180, weight: .heavy)).tracking(-11)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(primary)
            if let next = model.nextSet(after: rest) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(next.exercise.map { "\(next.label) · \($0)" } ?? next.label).floorEyebrow()
                    Text(next.target)
                        .font(.system(size: 88, weight: .heavy)).tracking(-4)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.3)
                    if let note = next.repOut ? (next.stopAtFormBreakdown ? "Stop when your form slips" : "As many as you can") : live.message {
                        Text(note).font(.title2.weight(.bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    if let bpm = model.currentHeartRate {
                        Label {
                            Text("\(Int(bpm)) bpm\(rest.plan.heartRateGuided ? " · ends early when it recovers" : "")")
                        } icon: {
                            Image(systemName: "heart")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                    }
                }
                .foregroundStyle(primary)
                .padding(.top, 8)
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tap anywhere").floorEyebrow()
                Text("Skip rest").font(.system(size: actionSize, weight: .heavy)).tracking(-1.4).lineLimit(1).minimumScaleFactor(0.5)
            }
            .foregroundStyle(primary)
            FloorEdge(text: "Swipe down · 15 s less", up: false)
                .foregroundStyle(secondary)
                .padding(.top, 18)
        }
        .padding(.leading, 40)
        .padding(.trailing, 20)
        .padding(.vertical, 8)
    }
}

/// Where the rest's Undo is drawn, for the button over it.
private struct UndoBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// Undo as one of the rest's actions for VoiceOver, while there's a set to take back.
private struct UndoAction: ViewModifier {
    let logged: JustLogged?
    let undo: () -> Void

    func body(content: Content) -> some View {
        if let logged, logged.undoable {
            content.accessibilityAction(named: "Undo \(logged.name.lowercased())", undo)
        } else {
            content
        }
    }
}

/// The gauge's ticks down the leading edge, counted up from the bottom: a short one every 10 s
/// of the rest, a long one every 30.
private struct Ticks: View {
    let total: Double
    let color: Color

    var body: some View {
        Canvas { context, size in
            let count = Int(total / 10)
            guard count > 1 else { return }
            for step in 1..<count {
                let y = (size.height - size.height * Double(step * 10) / total).rounded()
                let width: CGFloat = step.isMultiple(of: 3) ? 20 : 10
                context.fill(Path(CGRect(x: 0, y: y - 1, width: width, height: 2)), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shared

/// What a swipe does, at the edge it points to: "SWIPE UP · EASY" under a chevron.
private struct FloorEdge: View {
    let text: String?
    let up: Bool

    var body: some View {
        VStack(spacing: 2) {
            if let text {
                if up { Image(systemName: "chevron.up").font(.body.weight(.bold)) }
                Text(text).floorEyebrow()
                if !up { Image(systemName: "chevron.down").font(.body.weight(.bold)) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The floor's small labels: bold capitals, spaced, readable from a metre away.
    fileprivate func floorEyebrow() -> some View {
        font(.footnote.weight(.bold)).textCase(.uppercase).tracking(1.1).lineLimit(1).minimumScaleFactor(0.7)
    }

    /// The floor's three gestures: a tap anywhere, and a swipe up or down that starts anywhere. A
    /// sideways drag does nothing.
    fileprivate func floorGestures(tap: @escaping () -> Void, up: (() -> Void)?, down: (() -> Void)?) -> some View {
        contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) < 16, abs(dy) < 16 {
                            tap()
                            return
                        }
                        guard abs(dy) > abs(dx) * 1.5 else { return }
                        let flung = value.predictedEndTranslation.height
                        if dy < -50 || flung < -160 {
                            up?()
                        } else if dy > 50 || flung > 160 {
                            down?()
                        }
                    }
            )
            .defersEdgeSwipes()
    }
}

extension Format {
    /// "25 kg a side": the floor's line has no room for the plates themselves.
    static func side(_ plates: [Double]?, unit: WeightUnit) -> String? {
        guard let plates, !plates.isEmpty else { return nil }
        return "\(number(plates.reduce(0, +), digits: 2)) \(unit.symbol) a side"
    }
}
