import SwiftUI
import ExerciseLibrary
import LiftEngine
import SystemCore

/// The current set: load and reps already filled in, then one tap to rate it.
struct SetLogger: View {
    @Environment(AppModel.self) private var model
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
                } else if !item.plan.isStrength || exercise.timed {
                    timedControls(set: set, exercise: exercise)
                } else {
                    strengthControls(set: set, exercise: exercise)
                }
            }
            .padding()
            .floatingGlass(in: RoundedRectangle(cornerRadius: 28), interactive: false)
            .onAppear { prepare(set: set, exercise: exercise, item: item) }
        }
    }

    // MARK: Pieces

    private func header(item: LiveItem, set: LiveSet, exercise: Exercise) -> some View {
        let work = item.sets.filter { $0.prescription.kind != .warmup }
        let position = item.sets[...setIndex].filter { $0.prescription.kind == set.prescription.kind || set.prescription.kind != .warmup && $0.prescription.kind != .warmup }.count
        let label: String = switch set.prescription.kind {
        case .warmup: "Warm-up \(item.sets[...setIndex].filter { $0.prescription.kind == .warmup }.count) of \(item.sets.filter { $0.prescription.kind == .warmup }.count)"
        case .repOut: set.prescription.stopAtFormBreakdown ? "Rep-out: stop when your form starts to slip" : "Rep-out: as many good reps as you can"
        case .findingWeight: set.prescription.loadKg == nil ? "Pick a weight you think you can do for \(set.prescription.targetReps)" : "Finding your weight · set \(position) of \(work.count)"
        default: "Set \(position) of \(work.count)"
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name).font(.title3.bold()).lineLimit(1)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            if let note = set.note { Text(note).font(.footnote.weight(.semibold)).foregroundStyle(.tint) }
        }
    }

    private func strengthControls(set: LiveSet, exercise: Exercise) -> some View {
        let increments = model.gymForToday.increments(for: exercise.equipment)
        let hasLoad = exercise.loadBasis != .none
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                if hasLoad {
                    Stepperish(title: loadTitle(exercise), value: Format.load(load, unit: increments.gym.unit, basis: exercise.loadBasis),
                               minus: { load = increments.step(load, direction: -1) },
                               plus: { load = increments.step(load, direction: 1) })
                }
                Stepperish(title: set.prescription.kind == .repOut ? "Reps done" : "Reps", value: "\(reps)",
                           minus: { reps = max(0, reps - 1) }, plus: { reps += 1 })
                    .frame(maxWidth: hasLoad ? 140 : .infinity)
            }
            if let plates = increments.platesPerSide(load), !plates.isEmpty, exercise.equipment.platePaired {
                Text("Per side: \(plates.map { Format.number($0, digits: 2) }.joined(separator: " + ")) \(increments.gym.unit.symbol)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            switch set.prescription.kind {
            case .warmup:
                Button { log(rating: nil) } label: { Text("Done").font(.headline).frame(maxWidth: .infinity) }
                    .primaryAction().controlSize(.large)
            case .repOut:
                Button { log(rating: nil) } label: { Text("Log \(reps) reps").font(.headline).frame(maxWidth: .infinity) }
                    .primaryAction().controlSize(.large)
            default:
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

    private func loadTitle(_ exercise: Exercise) -> String {
        switch exercise.loadBasis {
        case .bodyweightPlus: "Added"
        case .assisted: "Assistance"
        case .perHand: "Each hand"
        default: "Weight"
        }
    }

    private func timedControls(set: LiveSet, exercise: Exercise) -> some View {
        VStack(spacing: 10) {
            if let seconds = set.prescription.seconds {
                if let timerStart {
                    let end = timerStart.addingTimeInterval(TimeInterval(seconds))
                    Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(maxWidth: .infinity)
                } else {
                    Button { timerStart = Date() } label: {
                        Label("Start \(Format.duration(seconds))", systemImage: "timer").frame(maxWidth: .infinity)
                    }
                    .secondaryAction()
                }
            } else {
                Text("\(set.prescription.targetReps) reps\(exercise.unilateral ? " each side" : "")").font(.title3.monospacedDigit())
            }
            Button {
                let elapsed = timerStart.map { Int(Date().timeIntervalSince($0)) }
                model.update { live in
                    live.log(item: itemIndex, set: setIndex, reps: set.prescription.targetReps, loadKg: nil, rating: nil,
                             seconds: elapsed ?? set.prescription.seconds, environment: environment, now: Date())
                }
                timerStart = nil
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryAction()
            .controlSize(.large)
        }
    }

    private func conditioningControls(_ plan: ConditioningPlan) -> some View {
        VStack(spacing: 10) {
            Text(plan.summary).font(.headline.monospacedDigit())
            if let timerStart {
                Text(timerStart, style: .timer).font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
            }
            HStack {
                if timerStart == nil {
                    Button { timerStart = Date() } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .secondaryAction()
                }
                Button {
                    let minutes = timerStart.map { max(1, Int(Date().timeIntervalSince($0) / 60)) } ?? plan.minutes
                    model.update { $0.logConditioning(item: itemIndex, minutes: minutes, averageHeartRate: nil, zoneMinutes: [:]) }
                    timerStart = nil
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity)
                }
                .primaryAction()
                .controlSize(.large)
            }
            Text("With your Watch running the session, heart-rate zones are logged automatically.").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Logic

    private var environment: SessionEnvironment {
        model.environment ?? SessionEnvironment(catalog: model.catalog, gym: model.gym, trust: TrustState(prior: 0.5),
                                                phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: nil, history: [:],
                                                enduranceScore: nil, heartRateGuidedRest: false)
    }

    /// Fills load and reps from the prescription, or a sensible starting guess when the person
    /// is picking a weight.
    private func prepare(set: LiveSet, exercise: Exercise, item: LiveItem) {
        guard !prepared else { return }
        prepared = true
        reps = set.prescription.targetReps
        if let prescribed = set.prescription.loadKg {
            load = prescribed
            return
        }
        let increments = model.gymForToday.increments(for: exercise.equipment)
        if let earlier = item.sets[..<setIndex].last(where: { $0.logged != nil })?.logged?.loadKg {
            load = earlier
        } else if let last = model.analysis?.history[exercise.id]?.last?.loadKg {
            load = last
        } else {
            load = switch exercise.loadBasis {
            case .bodyweightPlus, .assisted, .none: 0
            case .perHand: increments.round(model.gym.unit == .kg ? 8 : 8.5, down: false)
            case .external:
                exercise.equipment.platePaired ? increments.round(increments.gym.unit.toKilograms(increments.gym.barWeight) * 1.5, down: false)
                    : increments.round(20, down: false)
            }
        }
    }

    private func log(rating: SetRating?) {
        let exercise = model.catalog.resolve(model.live?.items[itemIndex].exerciseID ?? "")
        let peak: Double? = nil
        model.update { live in
            live.log(item: itemIndex, set: setIndex, reps: reps, loadKg: exercise.loadBasis == .none ? 0 : load, rating: rating,
                     heartRatePeak: peak, environment: environment, now: Date())
        }
        UIAccessibility.post(notification: .announcement, argument: model.live?.message ?? "Logged")
    }
}

/// A − value + control, big enough for gym hands.
struct Stepperish: View {
    let title: String
    let value: String
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button(action: minus) { Image(systemName: "minus").frame(width: 36, height: 36) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("Less \(title.lowercased())")
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                Button(action: plus) { Image(systemName: "plus").frame(width: 36, height: 36) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("More \(title.lowercased())")
            }
        }
        .padding(8)
        .background(.insetBackground, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
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
                        Toggle(joint.label, isOn: Binding(get: { pain.contains(joint) }, set: { on in
                            if on { pain.insert(joint) } else { pain.remove(joint) }
                        }))
                    }
                } header: {
                    Text("Any joint pain?")
                } footer: {
                    Text("Feeling beat up and stalling means less whole-body fatigue next block before less work. Pain that persists or worsens means a physio.")
                }
            }
            .navigationTitle("How was it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save session") {
                        dismiss()
                        model.finish(feedback: SessionFeedback(soreness: soreness, jointPain: Joint.allCases.filter(pain.contains), energy: energy))
                    }
                }
            }
        }
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
                    let options = query.isEmpty
                        ? Substitutions.candidates(for: current, in: model.catalog.all, availability: model.gymForToday.availability,
                                                   injuries: injuries, avoid: model.settings.avoid, limit: 20)
                        : ExerciseSearch.search(InjuryFilter.allowed(model.catalog.of(kind: .strength).filter { model.gymForToday.availability.allows($0) },
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
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Swap exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
