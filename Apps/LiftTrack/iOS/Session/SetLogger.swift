import ExerciseLibrary
import LiftEngine
import SwiftUI
import SystemCore

/// The current set: load and reps already filled in, then one tap to rate it.
struct SetLogger: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionScale) private var scale
    let itemIndex: Int
    let setIndex: Int

    @State private var load: Double = 0
    @State private var reps: Int = 0
    @State private var askMissed = false
    @State private var timerStart: Date?
    @State private var prepared = false

    var body: some View {
        if let live = model.live, live.items.indices.contains(itemIndex), live.items[itemIndex].sets.indices.contains(setIndex) {
            let item = live.items[itemIndex]
            let set = item.sets[setIndex]
            let exercise = model.catalog.resolve(item.exerciseID)
            VStack(alignment: .leading, spacing: 12) {
                header(item: item, set: set, exercise: exercise)
                if let conditioning = item.plan.conditioning {
                    conditioningControls(conditioning)
                } else if item.plan.role == .recovery {
                    HeatControls(itemIndex: itemIndex, room: item.exerciseID)
                } else if !item.plan.isStrength || exercise.timed {
                    timedControls(set: set, exercise: exercise)
                } else {
                    strengthControls(set: set, exercise: exercise)
                }
            }
            .sessionDock()
            .onAppear { prepare(set: set, exercise: exercise, item: item) }
        }
    }

    // MARK: Pieces

    private func header(item: LiveItem, set: LiveSet, exercise: Exercise) -> some View {
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        let position = item.sets[...setIndex].filter {
            $0.prescription.kind == set.prescription.kind || set.prescription.kind != .warmup && $0.prescription.kind != .warmup
        }.count
        let label: String =
            switch set.prescription.kind {
            case .warmup:
                "Warm-up \(item.sets[...setIndex].filter { $0.prescription.kind == .warmup }.count) of \(item.sets.filter { $0.prescription.kind == .warmup }.count)"
            case .repOut:
                set.prescription.stopAtFormBreakdown ? "Rep-out: stop when your form starts to slip" : "Rep-out: as many good reps as you can"
            case .findingWeight:
                set.prescription.loadKg == nil
                    ? "Pick a weight you think you can do for \(set.prescription.targetReps)"
                    : "Finding your weight · set \(position) of \(work.count)"
            default: "Set \(position) of \(work.count)"
            }
        // The phone names the exercise above the dock: the dock says which set, and what it was last time.
        let last = set.prescription.kind == .warmup ? nil : model.lastTime(exercise, setNumber: position)
        let increments = model.gymForToday.increments(for: exercise.equipment)
        let plates =
            exercise.equipment.platePaired && item.plan.isStrength ? Format.plates(increments.platesPerSide(load), unit: increments.gym.unit) : nil
        return VStack(alignment: .leading, spacing: 4) {
            if scale.isLarge {
                Text(exercise.name).font(scale.titleFont).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(last.map { "\(label) · last time \(Format.logged($0, exercise: exercise, unit: model.gym.unit))" } ?? label)
                    .eyebrow()
                    .lineLimit(2)
                Spacer(minLength: 4)
                if let plates { Text(plates).font(.caption.monospacedDigit()).foregroundStyle(Ink.text2).lineLimit(1) }
            }
            if let note = set.note { Text(note).font(.footnote.weight(.semibold)).foregroundStyle(.tint) }
        }
    }

    private func strengthControls(set: LiveSet, exercise: Exercise) -> some View {
        let increments = model.gymForToday.increments(for: exercise.equipment)
        let hasLoad = exercise.loadBasis != .none
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                if hasLoad {
                    LoadControl(
                        title: loadTitle(exercise), load: $load, increments: increments, basis: exercise.loadBasis,
                        identifier: "logger.load", keys: (.downArrow, .upArrow), showsTitle: scale.isLarge || exercise.loadBasis != .external)
                }
                Stepperish(
                    title: set.prescription.kind == .repOut ? "Reps done" : "Reps", value: "\(reps)",
                    minus: { reps = max(0, reps - 1) }, plus: { reps += 1 },
                    entry: .init(unit: "reps", text: "\(reps)") { text in if let n = Stepperish.typedReps(text) { reps = n } },
                    identifier: "logger.reps", keys: ("-", "="), showsTitle: scale.isLarge || set.prescription.kind == .repOut
                )
                .frame(maxWidth: hasLoad ? (scale.isLarge ? 260 : 132) : .infinity)
            }
            switch set.prescription.kind {
            case .warmup:
                Button {
                    log(rating: nil)
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction().controlSize(.large)
                .keyboardShortcut(scale.shortcut(.return))
                .accessibilityIdentifier("logger.done")
            case .repOut:
                Button {
                    log(rating: nil)
                } label: {
                    Text("Log \(reps) reps").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction().controlSize(.large)
                .keyboardShortcut(scale.shortcut(.return))
                .accessibilityIdentifier("logger.logRepOut")
            default:
                if !scale.isLarge {
                    Text("How did it feel? One tap logs the set and starts your rest.")
                        .font(.caption).foregroundStyle(Ink.text2)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                RatingButtons { rating in
                    if rating == .red, reps >= set.prescription.targetReps { askMissed = true } else { log(rating: rating) }
                }
                .confirmationDialog("How many did you get?", isPresented: $askMissed, titleVisibility: .visible) {
                    ForEach((max(0, set.prescription.targetReps - 6)..<set.prescription.targetReps).reversed(), id: \.self) { n in
                        Button("\(n) reps") {
                            reps = n
                            log(rating: .red)
                        }
                    }
                } message: {
                    Text("Missed reps are just data. The next set adjusts.")
                }
            }
        }
    }

    func loadTitle(_ exercise: Exercise) -> String {
        switch exercise.loadBasis {
        case .bodyweightPlus: "Added"
        case .assisted: "Assistance"
        case .perHand: "Each hand"
        default: "Weight"
        }
    }

    private func timedControls(set: LiveSet, exercise: Exercise) -> some View {
        VStack(spacing: 10) {
            // Easy means easy: a warm-up in zones 1–2, and the sauna's climb, shown as they happen.
            if let item = model.live?.items[itemIndex], item.plan.block == .warmup || item.plan.block == .recovery {
                HeartRateLine(aim: item.plan.block == .warmup ? 1...2 : nil)
            }
            if let seconds = set.prescription.seconds {
                if let timerStart {
                    let end = timerStart.addingTimeInterval(TimeInterval(seconds))
                    Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                        .font(.system(size: scale.clockSize, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(maxWidth: .infinity)
                } else {
                    Button {
                        timerStart = Date()
                    } label: {
                        Label("Start \(Format.duration(seconds))", systemImage: "timer").frame(maxWidth: .infinity)
                    }
                    .secondaryAction()
                    .accessibilityIdentifier("logger.startTimer")
                }
            } else {
                Text("\(set.prescription.targetReps) reps\(exercise.unilateral ? " each side" : "")").font(.title3.monospacedDigit())
            }
            Button {
                let elapsed = timerStart.map { Int(Date().timeIntervalSince($0)) }
                model.update { live in
                    live.log(
                        item: itemIndex, set: setIndex, reps: set.prescription.targetReps, loadKg: nil, rating: nil,
                        seconds: elapsed ?? set.prescription.seconds, environment: environment, now: Date())
                }
                timerStart = nil
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.large)
            .keyboardShortcut(scale.shortcut(.return))
            .accessibilityIdentifier("logger.done")
        }
    }

    private func conditioningControls(_ plan: ConditioningPlan) -> some View {
        VStack(spacing: 10) {
            Text(plan.summary).font(.headline.monospacedDigit())
            HeartRateLine(aim: plan.zones)
            if let timerStart {
                Text(timerStart, style: .timer).font(.system(size: scale.clockSize, weight: .semibold, design: .rounded).monospacedDigit())
            }
            HStack {
                if timerStart == nil {
                    Button {
                        timerStart = Date()
                    } label: {
                        Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .secondaryAction()
                    .accessibilityIdentifier("logger.startTimer")
                }
                Button {
                    let now = Date()
                    let minutes = timerStart.map { max(1, Int(now.timeIntervalSince($0) / 60)) } ?? plan.minutes
                    let start = timerStart ?? now.addingTimeInterval(-Double(minutes * 60))
                    // With the Watch measuring: the average and the minutes in each zone.
                    let average = model.live?.averageHeartRate(from: start, to: now)
                    let zones = model.live?.zoneMinutes(from: start, to: now, zones: model.heartRateZones) ?? [:]
                    model.update { $0.logConditioning(item: itemIndex, minutes: minutes, averageHeartRate: average, zoneMinutes: zones) }
                    timerStart = nil
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
                .keyboardShortcut(scale.shortcut(.return))
                .accessibilityIdentifier("logger.done")
            }
            // Only an iPhone streams a Watch's heart rate into the session.
            if model.currentHeartRate == nil && Platform.canPairWatch {
                Text("Wear your Apple Watch with Stadig Lift on it and heart rate and zones are logged automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Logic

    private var environment: SessionEnvironment {
        model.environment
            ?? SessionEnvironment(
                catalog: model.catalog, gym: model.gym, trust: TrustState(prior: 0.5),
                phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: nil, history: [:],
                enduranceScore: nil, heartRateGuidedRest: false)
    }

    /// Fills load and reps from the prescription, or a sensible starting guess when the person
    /// is picking a weight.
    private func prepare(set: LiveSet, exercise: Exercise, item: LiveItem) {
        guard !prepared else { return }
        prepared = true
        reps = set.prescription.targetReps
        load = model.startingLoad(for: set, at: setIndex, of: item, exercise: exercise)
    }

    private func log(rating: SetRating?) {
        let exercise = model.catalog.resolve(model.live?.items[itemIndex].exerciseID ?? "")
        let peak: Double? = nil
        model.update { live in
            live.log(
                item: itemIndex, set: setIndex, reps: reps, loadKg: exercise.loadBasis == .none ? 0 : load, rating: rating,
                heartRatePeak: peak, environment: environment, now: Date())
        }
        AccessibilityNotification.Announcement(model.live?.message ?? "Logged").post()
    }
}

/// The load: − and + step through what the gym can make (hold to keep going), and a tap on the
/// number types it in.
struct LoadControl: View {
    let title: String
    @Binding var load: Double
    let increments: GymIncrements
    let basis: LoadBasis
    var identifier: String?
    /// The keys for − and + in the session's large layout.
    var keys: (minus: KeyEquivalent, plus: KeyEquivalent)?
    var showsTitle = true

    var body: some View {
        let unit = increments.gym.unit
        let parts = Format.load(load, unit: unit, basis: basis).split(separator: " ", maxSplits: 1).map(String.init)
        Stepperish(
            title: title, value: parts.first ?? "", unit: parts.count > 1 ? parts[1] : nil,
            minus: { load = increments.step(load, direction: -1) },
            plus: { load = increments.step(load, direction: 1) },
            entry: .init(unit: unit.symbol, text: Format.number(unit.fromKilograms(load), digits: 2), decimal: true) { text in
                if let typed = Self.typedLoad(text, increments: increments) { load = typed }
            },
            identifier: identifier, keys: keys, showsTitle: showsTitle)
    }

    /// A typed load in kilograms, rounded to what the gym can make; nil for anything that isn't a
    /// number, is negative, or is past `GymIncrements.maximumLoadKg` (a slip, a few extra digits). A
    /// decimal comma reads as a point.
    static func typedLoad(_ text: String, increments: GymIncrements) -> Double? {
        let unit = increments.gym.unit
        guard let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), value >= 0,
            unit.toKilograms(value) <= GymIncrements.maximumLoadKg
        else { return nil }
        return increments.round(unit.toKilograms(value), down: false)
    }
}

/// A − value + control, big enough for gym hands. With an entry, a tap on the value types it.
struct Stepperish: View {
    /// Typing a value in: its unit, the text to start from, and what to do with the result.
    struct Entry {
        var unit: String
        var text: String
        var decimal = false
        var apply: (String) -> Void
    }

    let title: String
    let value: String
    /// Set smaller beside the value: "kg".
    var unit: String?
    let minus: () -> Void
    let plus: () -> Void
    var entry: Entry?
    /// For UI tests: the value is "<identifier>", its buttons "<identifier>Less" and "<identifier>More",
    /// and the typing alert's field and button "<identifier>Field" and "<identifier>Set".
    var identifier: String?
    /// The keys for − and + in the session's large layout.
    var keys: (minus: KeyEquivalent, plus: KeyEquivalent)?
    /// The title over the value; the phone's dock leaves it off, where the unit says enough.
    var showsTitle = true
    @Environment(\.sessionScale) private var scale
    @State private var typing = false
    @State private var typed = ""

    /// Typed reps: a whole number from 0, at most 100.
    static func typedReps(_ text: String) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), n >= 0 else { return nil }
        return min(n, 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsTitle { Text(title).eyebrow().padding(.top, 6) }
            HStack(spacing: 0) {
                Button(action: minus) {
                    Image(systemName: "minus").font(.title3.weight(.medium)).frame(width: scale.stepButton, height: scale.stepButton).contentShape(
                        .rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.text2)
                .buttonRepeatBehavior(.enabled)
                .hoverHighlight()
                .keyboardShortcut(keys.flatMap { scale.shortcut($0.minus) })
                .accessibilityLabel("Less \(title.lowercased())")
                .accessibilityIdentifier(identifier.map { "\($0)Less" } ?? "")
                Button {
                    guard let entry else { return }
                    typed = entry.text
                    typing = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value).numeral(scale.isLarge ? 64 : 44, weight: .heavy).foregroundStyle(Ink.text)
                        if let unit { Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text2).lineLimit(1) }
                    }
                    .frame(minWidth: 28, maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .disabled(entry == nil)
                // The number wins the space over the buttons.
                .layoutPriority(1)
                .accessibilityHint(entry == nil ? "" : "Type a value")
                .accessibilityIdentifier(identifier ?? "")
                Button(action: plus) {
                    Image(systemName: "plus").font(.title3.weight(.medium)).frame(width: scale.stepButton, height: scale.stepButton).contentShape(
                        .rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.text2)
                .buttonRepeatBehavior(.enabled)
                .hoverHighlight()
                .keyboardShortcut(keys.flatMap { scale.shortcut($0.plus) })
                .accessibilityLabel("More \(title.lowercased())")
                .accessibilityIdentifier(identifier.map { "\($0)More" } ?? "")
            }
            .frame(minHeight: scale.isLarge ? 96 : 72)
        }
        .alert(title, isPresented: $typing) {
            TextField(entry?.unit ?? "", text: $typed)
                .fieldKeyboard(entry?.decimal == true ? .decimal : .number)
                .accessibilityIdentifier(identifier.map { "\($0)Field" } ?? "")
            Button("Set") { entry?.apply(typed) }
                .accessibilityIdentifier(identifier.map { "\($0)Set" } ?? "")
            Button("Cancel", role: .cancel) {}
        } message: {
            if let unit = entry?.unit { Text("In \(unit)") }
        }
        .padding(.horizontal, 2)
        .background(.insetBackground, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: plus()
            case .decrement: minus()
            @unknown default: break
            }
        }
    }
}

/// How the session felt: what feeds the hidden Fatigue Budget.
struct FeedbackSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var soreness = 1
    @State private var energy = 3
    @State private var pain: Set<Joint> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Coming in, how sore were you?") {
                    Picker("Soreness", selection: $soreness) {
                        Text("None").tag(0)
                        Text("A little").tag(1)
                        Text("Sore").tag(2)
                        Text("Very").tag(3)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Energy") {
                    Picker("Energy", selection: $energy) {
                        Text("Drained").tag(1)
                        Text("Low").tag(2)
                        Text("OK").tag(3)
                        Text("Good").tag(4)
                        Text("Great").tag(5)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(Joint.allCases) { joint in
                        Toggle(
                            joint.label,
                            isOn: Binding(
                                get: { pain.contains(joint) },
                                set: { on in
                                    if on { pain.insert(joint) } else { pain.remove(joint) }
                                }))
                    }
                } header: {
                    Text("Any joint pain?")
                } footer: {
                    Text(
                        "Feeling beat up and stalling means less whole-body fatigue next block before less work. Pain that persists or worsens means a physio."
                    )
                }
            }
            .navigationTitle("How was it?")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() }.accessibilityIdentifier("feedback.back") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save session") {
                        dismiss()
                        model.finish(feedback: SessionFeedback(soreness: soreness, jointPain: Joint.allCases.filter(pain.contains), energy: energy))
                    }
                    .accessibilityIdentifier("feedback.save")
                }
            }
        }
        .sheetFrame()
        .presentationDetents([.large])
    }
}

/// Swaps an exercise for the rest of the session: same movement first, filtered by the gym and injuries.
struct SwapSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let index: Int
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if let live = model.live, live.items.indices.contains(index) {
                    let current = model.catalog.resolve(live.items[index].exerciseID)
                    let injuries = model.analysis?.life.injuries ?? []
                    let options =
                        query.isEmpty
                        ? Substitutions.candidates(
                            for: current, in: model.catalog.all, availability: model.gymForToday.availability,
                            injuries: injuries, avoid: model.settings.avoid, limit: 20)
                        : ExerciseSearch.search(
                            InjuryFilter.allowed(
                                model.catalog.of(kind: .strength).filter { model.gymForToday.availability.allows($0) },
                                injuries: injuries), query)
                    ForEach(options.prefix(30)) { exercise in
                        Button {
                            if let environment = model.environment {
                                model.update { $0.swap(item: index, to: exercise, environment: environment) }
                            }
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).foregroundStyle(.primary)
                                Text("\(exercise.equipment.label) · \(exercise.primaryMuscles.map(\.label).joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("swap.option")
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Swap exercise")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("swap.cancel") } }
        }
        .sheetFrame()
    }
}

/// Corrects a logged set: the weight, the reps, the rating. The sets still to come adjust again
/// from the corrected numbers.
struct EditSetSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let itemIndex: Int
    let setIndex: Int
    @State private var load: Double = 0
    @State private var reps = 0
    @State private var rating: SetRating?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            if let live = model.live, live.items.indices.contains(itemIndex), live.items[itemIndex].sets.indices.contains(setIndex),
                let logged = live.items[itemIndex].sets[setIndex].logged
            {
                // The exercise the set was done on, which a swap since may have replaced: its loads and steps.
                let exercise = model.catalog.resolve(logged.exerciseID)
                let increments = model.gymForToday.increments(for: exercise.equipment)
                Form {
                    Section {
                        HStack(spacing: 12) {
                            if exercise.loadBasis != .none {
                                LoadControl(
                                    title: "Weight", load: $load, increments: increments, basis: exercise.loadBasis,
                                    identifier: "editSet.load")
                            }
                            Stepperish(
                                title: "Reps", value: "\(reps)", minus: { reps = max(0, reps - 1) }, plus: { reps += 1 },
                                entry: .init(unit: "reps", text: "\(reps)") { text in if let n = Stepperish.typedReps(text) { reps = n } },
                                identifier: "editSet.reps"
                            )
                            .frame(maxWidth: exercise.loadBasis != .none ? 140 : .infinity)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    } footer: {
                        Text("Tap a number to type it.")
                    }
                    if logged.kind != .warmup, logged.kind != .repOut {
                        Section("How it felt") {
                            Picker("Rating", selection: $rating) {
                                ForEach(SetRating.allCases) { Text($0.label).tag(SetRating?.some($0)) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                .navigationTitle(exercise.name)
                .inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("editSet.cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let environment = model.environment {
                                model.update { live in
                                    live.edit(
                                        item: itemIndex, set: setIndex, reps: reps, loadKg: exercise.loadBasis == .none ? 0 : load,
                                        rating: rating, environment: environment)
                                }
                            }
                            dismiss()
                        }
                        .accessibilityIdentifier("editSet.save")
                    }
                }
                .onAppear {
                    guard !loaded else { return }
                    loaded = true
                    load = logged.loadKg
                    reps = logged.reps
                    rating = logged.rating
                }
            } else {
                ContentUnavailableView("Set not found", systemImage: "questionmark")
            }
        }
        .sheetFrame()
        .presentationDetents([.medium])
    }
}

/// The Watch's latest reading, its zone, and the zones to aim for.
struct HeartRateLine: View {
    @Environment(AppModel.self) private var model
    let aim: ClosedRange<Int>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            if let bpm = model.currentHeartRate {
                let zone = model.heartRateZones.zone(for: bpm)
                let inside = aim.map { $0.contains(zone) } ?? true
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").foregroundStyle(Ink.bad).symbolEffect(.pulse)
                    Text("\(Int(bpm))").font(.title2.weight(.semibold).monospacedDigit())
                    Text("Zone \(zone)").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background((inside ? Ink.good : Ink.ok).opacity(0.18), in: .capsule)
                    Spacer()
                    if let aim {
                        let low = Int(model.heartRateZones.range(zone: aim.lowerBound).lowerBound)
                        let high = Int(model.heartRateZones.range(zone: aim.upperBound).upperBound)
                        Text("Aim \(low)–\(high)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Heart rate \(Int(bpm)), zone \(zone)\(inside ? "" : aim.map { ", aim zone \($0.lowerBound) to \($0.upperBound)" } ?? "")")
            }
        }
    }
}

/// The sauna or steam room: read the thermometer, and the time follows from the last session and
/// how it felt; afterwards, how this one felt.
struct HeatControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionScale) private var scale
    let itemIndex: Int
    let room: String
    @State private var temperatureC: Double?
    @State private var started: Date?
    @State private var finished: Date?

    var body: some View {
        let plan = HeatDose.plan(model.environment?.heat ?? [], room: room)
        let celsius = temperatureC ?? plan.temperatureC
        let minutes = plan.minutes(at: celsius, room: room)
        let fahrenheit = model.fahrenheit
        VStack(spacing: 10) {
            HeartRateLine(aim: nil)
            if finished == nil {
                VStack(spacing: 10) {
                    Thermometer(celsius: celsius, fahrenheit: fahrenheit) { temperatureC = $0 }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Aim for").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(minutes) min").font(.title2.weight(.semibold).monospacedDigit())
                        Spacer()
                    }
                }
                Text(explanation(plan, today: celsius, minutes: minutes, fahrenheit: fahrenheit))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let started {
                    let end = started.addingTimeInterval(TimeInterval(minutes * 60))
                    Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                        .font(.system(size: scale.clockSize, weight: .semibold, design: .rounded).monospacedDigit())
                    Button {
                        finished = Date()
                    } label: {
                        Text("Done").font(.headline).frame(maxWidth: .infinity)
                    }
                    .primaryAction().controlSize(.large)
                    .keyboardShortcut(scale.shortcut(.return))
                    .accessibilityIdentifier("heat.done")
                } else {
                    Button {
                        started = Date()
                    } label: {
                        Label("Start \(minutes) min", systemImage: "timer").font(.headline).frame(maxWidth: .infinity)
                    }
                    .primaryAction().controlSize(.large)
                    .accessibilityIdentifier("heat.start")
                }
                Text("Leave whenever you feel dizzy or unwell, and drink water afterwards.").font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("How was it?").font(.headline)
                HStack(spacing: 10) {
                    rating(.green, "Easy", "Could stay longer").keyboardShortcut(scale.shortcut("1"))
                    rating(.orange, "Just right", "Ready to leave").keyboardShortcut(scale.shortcut("2"))
                    rating(.red, "Too much", "Left early or felt rough").keyboardShortcut(scale.shortcut("3"))
                }
            }
        }
    }

    func rating(_ value: SetRating, _ label: String, _ detail: String) -> some View {
        Button {
            let end = finished ?? Date()
            let spent =
                started.map { max(1, end.timeIntervalSince($0) / 60) }
                ?? Double(HeatDose.plan(model.environment?.heat ?? [], room: room).minutes(at: temperatureC ?? HeatDose.reference(room), room: room))
            let reading = temperatureC ?? HeatDose.plan(model.environment?.heat ?? [], room: room).temperatureC
            model.update { $0.logHeat(item: itemIndex, minutes: (spent * 2).rounded() / 2, temperatureC: reading, rating: value, now: end) }
        } label: {
            // As the set's ratings: a dot in its colour, Just right the filled accent.
            let filled = value == .orange
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    if !filled { Circle().fill(value.color).frame(width: 8, height: 8) }
                    Text(label).font(.subheadline.weight(.semibold))
                }
                Text(detail).font(.caption2).foregroundStyle(filled ? Ink.onAccent.opacity(0.85) : Ink.text2).multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(filled ? Ink.onAccent : Ink.text)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: scale.isLarge ? 96 : 64)
            .background(filled ? Color.accentColor : Ink.raised, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel("\(label): \(detail)")
        .accessibilityIdentifier("heat.rating\(value.rawValue.identifierSuffix)")
    }

    /// Where today's minutes come from, in a line.
    func explanation(_ plan: HeatDose.Plan, today: Double, minutes: Int, fahrenheit: Bool) -> String {
        guard let last = plan.last else {
            return "First time: about ten minutes at \(Format.temperature(HeatDose.reference(room), fahrenheit: fahrenheit)), less when it's hotter."
        }
        let then =
            "\(Int(last.minutes.rounded())) min at \(last.temperatureC.map { Format.temperature($0, fahrenheit: fahrenheit) } ?? "an unknown heat")"
        let felt =
            switch plan.change {
            case .more: "felt easy, so a little more"
            case .less: "was too much, so a little less"
            default: "was right, so the same"
            }
        let hotter =
            last.temperatureC.map { today - $0 >= 2 ? " Hotter today, so shorter." : ($0 - today >= 2 ? " Cooler today, so longer." : "") } ?? ""
        return "Last time \(then) \(felt).\(hotter)"
    }

}

/// The room's thermometer: − and + in 5 °F or 2 °C steps, or tap to type the reading.
struct Thermometer: View {
    let celsius: Double
    let fahrenheit: Bool
    let set: (Double) -> Void
    @State private var typing = false
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 4) {
            Text("Thermometer").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    set(step(by: -1))
                } label: {
                    Image(systemName: "minus").frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered).buttonBorderShape(.circle).buttonRepeatBehavior(.enabled)
                .accessibilityLabel("Cooler")
                Spacer()
                Button {
                    typed = Format.temperature(celsius, fahrenheit: fahrenheit).filter(\.isNumber)
                    typing = true
                } label: {
                    Text(Format.temperature(celsius, fahrenheit: fahrenheit))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                .accessibilityHint("Type the reading")
                Spacer()
                Button {
                    set(step(by: 1))
                } label: {
                    Image(systemName: "plus").frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered).buttonBorderShape(.circle).buttonRepeatBehavior(.enabled)
                .accessibilityLabel("Hotter")
            }
        }
        .padding(8)
        .background(.insetBackground, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thermometer")
        .accessibilityValue(Format.temperature(celsius, fahrenheit: fahrenheit))
        .alert("Thermometer", isPresented: $typing) {
            TextField(fahrenheit ? "°F" : "°C", text: $typed).fieldKeyboard(.number)
            Button("Set") {
                guard let value = Double(typed) else { return }
                set(min(120, max(30, fahrenheit ? (value - 32) * 5 / 9 : value)))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(fahrenheit ? "In °F" : "In °C")
        }
    }

    func step(by direction: Double) -> Double {
        if fahrenheit {
            let f = (celsius * 9 / 5 + 32) / 5
            return (((f.rounded() + direction) * 5) - 32) * 5 / 9
        }
        return (celsius / 2).rounded() * 2 + 2 * direction
    }
}

extension AppModel {
    /// Where the logger's load starts for a set: the prescription; else this exercise's last set in
    /// this session (not one logged before a swap: that was another exercise's load); else its last
    /// set ever; else a guess from the strength standards for someone like this, so a 400 lb leg
    /// press isn't fifty taps away; else a light default for the equipment.
    func startingLoad(for set: LiveSet, at setIndex: Int, of item: LiveItem, exercise: Exercise) -> Double {
        if let prescribed = set.prescription.loadKg { return prescribed }
        let increments = gymForToday.increments(for: exercise.equipment)
        if let earlier = item.sets[..<min(setIndex, item.sets.count)].last(where: { $0.logged?.exerciseID == exercise.id })?.logged?.loadKg {
            return earlier
        }
        if let last = analysis?.history[exercise.id]?.last?.loadKg { return last }
        if let profile,
            let guess = StartingLoad.estimate(
                exercise, reps: set.prescription.targetReps, bodyweightKg: state?.effectiveBodyweight,
                sex: profile.sex, experience: profile.experience)
        {
            return increments.round(guess, down: true)
        }
        return switch exercise.loadBasis {
        case .bodyweightPlus, .assisted, .none: 0
        case .perHand: increments.round(gym.unit == .kg ? 8 : 8.5, down: false)
        case .external:
            exercise.equipment.platePaired
                ? increments.round(increments.gym.unit.toKilograms(increments.gym.barWeight) * 1.5, down: false)
                : increments.round(20, down: false)
        }
    }
}
