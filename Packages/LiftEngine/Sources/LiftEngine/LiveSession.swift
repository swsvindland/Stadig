import ExerciseLibrary
import Foundation
import SystemCore

/// What the live session needs from outside to adjust sets: the same on the phone and the Watch.
public struct SessionEnvironment: Sendable {
    public var catalog: ExerciseCatalog
    public var gym: Gym
    public var trust: TrustState
    public var phase: PhaseEffects
    public var bodyweightKg: Double?
    public var history: [String: [LoggedSet]]
    public var enduranceScore: Double?
    public var heartRateGuidedRest: Bool
    /// Past sauna and steam sessions, for today's time.
    public var heat: [HeatLog] = []

    public init(
        catalog: ExerciseCatalog, gym: Gym, trust: TrustState, phase: PhaseEffects, bodyweightKg: Double?,
        history: [String: [LoggedSet]], enduranceScore: Double?, heartRateGuidedRest: Bool
    ) {
        self.catalog = catalog
        self.gym = gym
        self.trust = trust
        self.phase = phase
        self.bodyweightKg = bodyweightKg
        self.history = history
        self.enduranceScore = enduranceScore
        self.heartRateGuidedRest = heartRateGuidedRest
    }

    public func increments(for exercise: Exercise) -> GymIncrements { gym.increments(for: exercise.equipment) }
}

public struct LiveSet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var prescription: SetPrescription
    public var logged: LoggedSet?
    public var skipped: Bool
    /// The adjustment that produced this set's numbers, said plainly.
    public var note: String?
    /// The set as first prescribed, before any rating adjusted it: where a correction starts from.
    public var planned: SetPrescription?

    public init(id: UUID = UUID(), prescription: SetPrescription, logged: LoggedSet? = nil, skipped: Bool = false, note: String? = nil) {
        self.id = id
        self.prescription = prescription
        self.logged = logged
        self.skipped = skipped
        self.note = note
        planned = prescription
    }

    public var isOpen: Bool { logged == nil && !skipped }
}

// A session in progress is saved after every change and read back at the next launch, which may
// be an app update later: anything added since decodes as absent (nil, false, empty) rather than
// leaving the session unreadable. What a thing can't be without (its plan, its prescription, its
// id) stays required. A field added to one of these needs a line in its decoder.
extension LiveSet {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        prescription = try c.decode(SetPrescription.self, forKey: .prescription)
        logged = try c.decodeIfPresent(LoggedSet.self, forKey: .logged)
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note)
        planned = try c.decodeIfPresent(SetPrescription.self, forKey: .planned)
    }
}

public struct LiveItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var plan: PlannedItem
    public var exerciseID: String
    public var sets: [LiveSet]
    public var skipped: Bool
    public var verified: Bool
    public var conditioning: ConditioningLog?
    /// The sauna or steam room, as it went.
    public var heat: HeatLog?

    public init(plan: PlannedItem) {
        id = plan.id
        self.plan = plan
        exerciseID = plan.exerciseID
        sets = plan.sets.map { LiveSet(prescription: $0) }
        skipped = false
        verified = false
    }

    public var isDone: Bool { skipped || sets.allSatisfy { !$0.isOpen } }
    public var nextSet: Int? { skipped ? nil : sets.firstIndex { $0.isOpen } }
    public var loggedSets: [LoggedSet] { sets.compactMap(\.logged) }

    /// Whether "Add a set" means anything: a conditioning piece or a sauna round is logged once, as
    /// a whole, so a second bout would write over the first.
    public var takesMoreSets: Bool { plan.conditioning == nil && plan.role != .conditioning && plan.role != .recovery }

    /// Adapts the exercise's open work sets to a rated set: the next one gets the adjustment and its
    /// message, and every later one the same numbers; a rep-out keeps its kind. Nil when no open
    /// work set is left after it.
    mutating func adjustOpenSets(after logged: LoggedSet, at index: Int, environment: SessionEnvironment) -> SetAdjustment? {
        guard let next = sets.indices.first(where: { $0 > index && sets[$0].isOpen && sets[$0].prescription.kind != .warmup }) else { return nil }
        let exercise = environment.catalog.resolve(exerciseID)
        let context = Autoregulation.Context(
            exercise: exercise, increments: environment.increments(for: exercise), trust: environment.trust,
            repRange: plan.repRange, verifiedAlready: verified, hasSafeties: environment.gym.hasSafeties)
        let result = Autoregulation.next(after: logged, planned: sets[next].prescription, context: context)
        if result.kind == .verify { verified = true }
        for later in sets.indices where later >= next && sets[later].isOpen {
            var updated = result.next
            if sets[later].prescription.kind == .repOut {
                updated.kind = .repOut
                updated.targetRIR = 0
                updated.stopAtFormBreakdown = sets[later].prescription.stopAtFormBreakdown
            }
            sets[later].prescription = updated
            sets[later].note = later == next ? result.message : nil
        }
        return result
    }

    /// A finding-weight set with no load yet takes the weight just used.
    mutating func carryFindingWeight(of logged: LoggedSet, after index: Int) {
        for later in sets.indices where later > index && sets[later].isOpen && sets[later].prescription.loadKg == nil {
            sets[later].prescription.loadKg = logged.loadKg
        }
    }
}

extension LiveItem {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(PlannedItem.self, forKey: .plan)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseID = try c.decodeIfPresent(String.self, forKey: .exerciseID) ?? plan.exerciseID
        sets = try c.decodeIfPresent([LiveSet].self, forKey: .sets) ?? plan.sets.map { LiveSet(prescription: $0) }
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified) ?? false
        conditioning = try c.decodeIfPresent(ConditioningLog.self, forKey: .conditioning)
        heat = try c.decodeIfPresent(HeatLog.self, forKey: .heat)
    }
}

public struct RestState: Codable, Hashable, Sendable {
    public var started: Date
    public var plan: RestPlan
    public var itemID: UUID
    /// When the rest is due to end; heart rate may end it early, the person may skip or extend it.
    public var endsAt: Date
    /// Heart rate when the set began, for recovery thresholds.
    public var preSetHeartRate: Double?
    public var filler: String?
}

/// A session in progress: a pure state machine the phone and the Watch both run.
public struct LiveSession: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var plan: SessionPlan
    public var items: [LiveItem]
    public var startedAt: Date
    public var rest: RestState?
    public var message: String?
    public var lastAdjustment: AdjustmentKind?
    public var device: String
    public var mobilityDone: [String]
    public var heartRateSamples: [HeartRatePoint]
    public var updatedAt: Date

    public struct HeartRatePoint: Codable, Hashable, Sendable {
        public var date: Date
        public var bpm: Double

        public init(date: Date, bpm: Double) {
            self.date = date
            self.bpm = bpm
        }
    }

    public init(plan: SessionPlan, device: String, now: Date = Date()) {
        id = UUID()
        self.plan = plan
        items = plan.items.map(LiveItem.init)
        startedAt = now
        self.device = device
        mobilityDone = []
        heartRateSamples = []
        updatedAt = now
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        plan = try c.decode(SessionPlan.self, forKey: .plan)
        items = try c.decodeIfPresent([LiveItem].self, forKey: .items) ?? plan.items.map(LiveItem.init)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        // Only a timer: one that can't be read is dropped, and the session picks up without it.
        rest = try? c.decodeIfPresent(RestState.self, forKey: .rest)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        lastAdjustment = try c.decodeIfPresent(AdjustmentKind.self, forKey: .lastAdjustment)
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? "iPhone"
        mobilityDone = try c.decodeIfPresent([String].self, forKey: .mobilityDone) ?? []
        heartRateSamples = try c.decodeIfPresent([HeartRatePoint].self, forKey: .heartRateSamples) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? startedAt
    }

    // MARK: Where we are

    /// The next thing to do: the first open item, alternating within a superset.
    public var current: (item: Int, set: Int)? {
        guard let first = items.firstIndex(where: { !$0.isDone }) else { return nil }
        if let group = items[first].plan.supersetGroup {
            let members = items.indices.filter { items[$0].plan.supersetGroup == group && !items[$0].isDone }
            // The member with the fewest logged sets goes next.
            if let pick = members.min(by: { items[$0].sets.filter { !$0.isOpen }.count < items[$1].sets.filter { !$0.isOpen }.count }),
                let set = items[pick].nextSet
            {
                return (pick, set)
            }
        }
        guard let set = items[first].nextSet else { return nil }
        return (first, set)
    }

    public var isComplete: Bool { items.allSatisfy(\.isDone) }

    public var progress: Double {
        let all = items.flatMap(\.sets).filter { $0.prescription.kind != .warmup }
        guard !all.isEmpty else { return 1 }
        return Double(all.filter { !$0.isOpen }.count) / Double(all.count)
    }

    // MARK: Logging

    /// Logs a set and adapts the rest of the exercise to its rating. Returns the adjustment.
    @discardableResult
    public mutating func log(
        item index: Int, set setIndex: Int, reps: Int, loadKg: Double?, rating: SetRating?, seconds: Int? = nil,
        heartRatePeak: Double? = nil, environment: SessionEnvironment, now: Date = Date()
    ) -> SetAdjustment? {
        guard items.indices.contains(index), items[index].sets.indices.contains(setIndex) else { return nil }
        var item = items[index]
        let prescription = item.sets[setIndex].prescription
        let restBefore = rest.map { Int(now.timeIntervalSince($0.started)) }
        let logged = LoggedSet(
            exerciseID: item.exerciseID, date: now, kind: prescription.kind, loadKg: loadKg ?? prescription.loadKg ?? 0,
            reps: reps, targetReps: prescription.targetReps, rating: prescription.kind == .warmup ? nil : rating,
            bodyweightKg: environment.bodyweightKg, stoppedAtFormBreakdown: prescription.stopAtFormBreakdown,
            restBeforeSeconds: restBefore, heartRatePeak: heartRatePeak, seconds: seconds)
        item.sets[setIndex].logged = logged
        var adjustment: SetAdjustment?
        if item.plan.isStrength, prescription.kind != .warmup, rating != nil,
            let result = item.adjustOpenSets(after: logged, at: setIndex, environment: environment)
        {
            adjustment = result
            message = result.message
            lastAdjustment = result.kind
        } else {
            message = nil
        }
        if prescription.kind == .findingWeight { item.carryFindingWeight(of: logged, after: setIndex) }
        items[index] = item
        if !item.plan.isStrength, item.isDone, !mobilityDone.contains(item.exerciseID) { mobilityDone.append(item.exerciseID) }
        startRest(after: index, environment: environment, now: now)
        // Ramp-up sets need only a short breather.
        if prescription.kind == .warmup, var state = rest, state.plan.target > 45 {
            state.plan = RestPlan(target: 45, minimum: 0, heartRateGuided: false)
            state.endsAt = now.addingTimeInterval(45)
            rest = state
        }
        updatedAt = now
        return adjustment
    }

    /// Corrects a logged set (the wrong weight, a rating tapped too fast) and redoes what it set in
    /// motion: the sets still to come are worked out again from the plan and the corrected log.
    public mutating func edit(
        item index: Int, set setIndex: Int, reps: Int, loadKg: Double?, rating: SetRating?,
        environment: SessionEnvironment, now: Date = Date()
    ) {
        guard items.indices.contains(index), items[index].sets.indices.contains(setIndex),
            var logged = items[index].sets[setIndex].logged
        else { return }
        logged.reps = reps
        if let loadKg { logged.loadKg = loadKg }
        if logged.kind != .warmup { logged.rating = rating }
        items[index].sets[setIndex].logged = logged
        replay(item: index, environment: environment)
        updatedAt = now
    }

    /// Works an exercise's open sets out again: back to how they were first prescribed, then each
    /// logged set's adjustment in order, as if it had been logged right the first time.
    mutating func replay(item index: Int, environment: SessionEnvironment) {
        var item = items[index]
        guard item.plan.isStrength else { return }
        for i in item.sets.indices where item.sets[i].isOpen {
            if let planned = item.sets[i].planned { item.sets[i].prescription = planned }
            item.sets[i].note = nil
        }
        item.verified = false
        var last: SetAdjustment?
        for k in item.sets.indices {
            // Sets logged before a swap belong to the exercise swapped out: they say nothing about this one's load.
            guard let logged = item.sets[k].logged, logged.kind != .warmup, logged.exerciseID == item.exerciseID else { continue }
            if logged.rating != nil, let result = item.adjustOpenSets(after: logged, at: k, environment: environment) { last = result }
            if logged.kind == .findingWeight { item.carryFindingWeight(of: logged, after: k) }
        }
        items[index] = item
        message = last?.message
        lastAdjustment = last?.kind
    }

    // MARK: Order

    /// Does an exercise now, ahead of the plan's order (its rack or machine came free, or the next
    /// one is taken): it moves in front of whatever isn't done yet, with its superset partner.
    public mutating func doNext(item index: Int, now: Date = Date()) {
        guard items.indices.contains(index), !items[index].isDone else { return }
        let group = items[index].plan.supersetGroup
        let moving = items.indices.filter { $0 == index || (group != nil && items[$0].plan.supersetGroup == group && !items[$0].isDone) }
        let moved = moving.map { items[$0] }
        var others = items.indices.filter { !moving.contains($0) }.map { items[$0] }
        // In front of the first exercise not done yet; one half done picks up again straight after.
        let target = others.firstIndex { !$0.isDone } ?? others.count
        others.insert(contentsOf: moved, at: target)
        items = others
        if let rest, !items.contains(where: { $0.id == rest.itemID && !$0.isDone }) { self.rest = nil }
        updatedAt = now
    }

    /// Moves an exercise to another place in the order.
    public mutating func moveItem(from source: Int, to destination: Int, now: Date = Date()) {
        guard items.indices.contains(source), destination >= 0, destination <= items.count, source != destination else { return }
        let item = items.remove(at: source)
        items.insert(item, at: destination > source ? destination - 1 : destination)
        updatedAt = now
    }

    /// Moves exercises in the order the way a list's drag does: `destination` is a place in the order
    /// as it was before the move. A superset moves whole, its partners coming along in their order,
    /// and a move never lands between two partners of another superset. The rest running carries on:
    /// reordering what's next isn't starting it.
    public mutating func move(items source: IndexSet, to destination: Int, now: Date = Date()) {
        var moving = IndexSet(source.filter(items.indices.contains))
        guard !moving.isEmpty else { return }
        for index in Array(moving) {
            guard let group = items[index].plan.supersetGroup else { continue }
            for partner in items.indices where items[partner].plan.supersetGroup == group { moving.insert(partner) }
        }
        let moved = moving.map { items[$0] }
        var others = items.indices.filter { !moving.contains($0) }.map { items[$0] }
        var target = min(others.count, max(0, destination - moving.count(in: 0..<max(0, destination))))
        // Not between two halves of a superset: after the pair instead.
        while target > 0, target < others.count, let group = others[target].plan.supersetGroup, others[target - 1].plan.supersetGroup == group {
            target += 1
        }
        others.insert(contentsOf: moved, at: target)
        guard others.map(\.id) != items.map(\.id) else { return }
        items = others
        updatedAt = now
    }

    public mutating func skipSet(item index: Int, set setIndex: Int, now: Date = Date()) {
        guard items.indices.contains(index), items[index].sets.indices.contains(setIndex) else { return }
        items[index].sets[setIndex].skipped = true
        updatedAt = now
    }

    public mutating func skip(item index: Int, now: Date = Date()) {
        guard items.indices.contains(index) else { return }
        items[index].skipped = true
        if rest?.itemID == items[index].id { rest = nil }
        updatedAt = now
    }

    public mutating func addSet(item index: Int, now: Date = Date()) {
        guard items.indices.contains(index), items[index].takesMoreSets else { return }
        let last = items[index].sets.last { $0.prescription.kind != .warmup }
        var prescription =
            last?.prescription ?? SetPrescription(kind: .working, loadKg: nil, targetReps: items[index].plan.repRange.middle, targetRIR: 2)
        if prescription.kind == .repOut {
            prescription.kind = .working
            prescription.targetRIR = 1
        }
        if let logged = last?.logged { prescription.loadKg = logged.loadKg }
        items[index].sets.append(LiveSet(prescription: prescription))
        items[index].skipped = false
        updatedAt = now
    }

    /// Swaps an exercise for the rest of the session; open sets are prescribed afresh from its own history.
    public mutating func swap(item index: Int, to exercise: Exercise, environment: SessionEnvironment, now: Date = Date()) {
        guard items.indices.contains(index) else { return }
        var item = items[index]
        let open = item.sets.filter { $0.isOpen && $0.prescription.kind != .warmup }
        let target = SlotTarget(
            sets: max(1, open.count), repRange: item.plan.repRange, targetRIR: open.first?.prescription.targetRIR ?? 2,
            deload: open.first?.prescription.kind == .deload)
        let context = ProgressionContext(
            exercise: exercise, increments: environment.increments(for: exercise), trust: environment.trust,
            phase: environment.phase, bodyweightKg: environment.bodyweightKg,
            history: environment.history[exercise.id] ?? [])
        let prescription = Progression.prescribe(target, context)
        item.plan.substitutedFor = item.plan.substitutedFor ?? item.exerciseID
        item.exerciseID = exercise.id
        item.sets.removeAll { $0.isOpen }
        item.sets += prescription.sets.map { LiveSet(prescription: $0) }
        item.plan.note = prescription.reason
        item.verified = false
        items[index] = item
        updatedAt = now
    }

    public mutating func logConditioning(item index: Int, minutes: Int, averageHeartRate: Double?, zoneMinutes: [Int: Double], now: Date = Date()) {
        guard items.indices.contains(index) else { return }
        let zone = items[index].plan.conditioning?.zones.lowerBound ?? 2
        items[index].conditioning = ConditioningLog(
            exerciseID: items[index].exerciseID, minutes: minutes,
            averageHeartRate: averageHeartRate, zoneMinutes: zoneMinutes, zone: zone)
        for s in items[index].sets.indices where items[index].sets[s].isOpen {
            items[index].sets[s].logged = LoggedSet(
                exerciseID: items[index].exerciseID, date: now, kind: .working, loadKg: 0, reps: 1,
                seconds: minutes * 60)
        }
        rest = nil
        updatedAt = now
    }

    /// Logs the sauna or steam room: minutes, the thermometer, and how it felt.
    public mutating func logHeat(item index: Int, minutes: Double, temperatureC: Double?, rating: SetRating?, now: Date = Date()) {
        guard items.indices.contains(index) else { return }
        let start = now.addingTimeInterval(-minutes * 60)
        let readings = heartRateSamples.filter { $0.date >= start && $0.date <= now }.map(\.bpm)
        items[index].heat = HeatLog(
            exerciseID: items[index].exerciseID, date: now, minutes: minutes, temperatureC: temperatureC,
            rating: rating, averageHeartRate: readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count),
            peakHeartRate: readings.max())
        for s in items[index].sets.indices where items[index].sets[s].isOpen {
            items[index].sets[s].logged = LoggedSet(
                exerciseID: items[index].exerciseID, date: now, kind: .working, loadKg: 0, reps: 1,
                rating: nil, seconds: Int(minutes * 60))
        }
        rest = nil
        updatedAt = now
    }

    // MARK: Rest

    public mutating func startRest(after index: Int, environment: SessionEnvironment, now: Date = Date()) {
        let item = items[index]
        // Within a superset, move straight to the partner.
        if let group = item.plan.supersetGroup,
            items.contains(where: { $0.id != item.id && $0.plan.supersetGroup == group && !$0.isDone }),
            let current, items[current.item].id != item.id
        {
            rest = RestState(
                started: now, plan: RestPlan(target: 20, minimum: 0, heartRateGuided: false), itemID: item.id,
                endsAt: now.addingTimeInterval(20), preSetHeartRate: nil, filler: nil)
            return
        }
        let plan = item.plan.rest
        guard plan.target > 0, !isComplete else {
            rest = nil
            return
        }
        let preSet = heartRateSamples.last { $0.date <= now.addingTimeInterval(-30) }?.bpm
        rest = RestState(
            started: now, plan: plan, itemID: item.id, endsAt: now.addingTimeInterval(TimeInterval(plan.target)),
            preSetHeartRate: preSet, filler: item.plan.restFiller)
    }

    public mutating func endRest(now: Date = Date()) {
        rest = nil
        updatedAt = now
    }

    public mutating func extendRest(by seconds: Int, now: Date = Date()) {
        guard var state = rest else { return }
        state.endsAt = max(now, state.endsAt).addingTimeInterval(TimeInterval(seconds))
        rest = state
        updatedAt = now
    }

    /// Feeds live heart rate (Watch). Returns true when a heart-rate-guided rest has recovered while
    /// it's still running: once its time is up the person is already on the next set, though the
    /// session keeps the rest until that set is logged (its rest is timed from it).
    @discardableResult
    public mutating func record(heartRate bpm: Double, zones: HeartRateZones, now: Date = Date()) -> Bool {
        heartRateSamples.append(HeartRatePoint(date: now, bpm: bpm))
        if heartRateSamples.count > 4000 { heartRateSamples.removeFirst(heartRateSamples.count - 4000) }
        guard let state = rest, now < state.endsAt else { return false }
        let elapsed = Int(now.timeIntervalSince(state.started))
        return Rest.recovered(heartRate: bpm, preSet: state.preSetHeartRate, zones: zones, elapsed: elapsed, plan: state.plan)
    }

    /// Minutes in each heart-rate zone between two times: each reading counts until the next, and
    /// a gap over 15 s (the sensor dropping out) counts 15 s.
    public func zoneMinutes(from start: Date, to end: Date, zones: HeartRateZones) -> [Int: Double] {
        let samples = heartRateSamples.filter { $0.date >= start && $0.date <= end }
        var minutes: [Int: Double] = [:]
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].date : end
            let seconds = min(max(0, next.timeIntervalSince(sample.date)), 15)
            minutes[zones.zone(for: sample.bpm), default: 0] += seconds / 60
        }
        return minutes
    }

    public func averageHeartRate(from start: Date, to end: Date) -> Double? {
        let samples = heartRateSamples.filter { $0.date >= start && $0.date <= end }
        return samples.isEmpty ? nil : samples.map(\.bpm).reduce(0, +) / Double(samples.count)
    }

    // MARK: Finish

    /// The finished session, its day kept in the time zone it was done in.
    public func record(feedback: SessionFeedback?, now: Date = Date(), timeZone: TimeZone = .current) -> SessionRecord {
        var exercises: [ExerciseLog] = []
        var conditioning: [ConditioningLog] = []
        let samples = heartRateSamples.map { (date: $0.date, bpm: $0.bpm) }
        for item in items {
            if let c = item.conditioning { conditioning.append(c) }
            guard item.plan.isStrength else { continue }
            var sets = item.loggedSets
            guard !sets.isEmpty else { continue }
            if !samples.isEmpty {
                for i in sets.indices where sets[i].kind.countsAsWork {
                    if let hrr = HeartRateRecovery.drop(samples: samples, setEnd: sets[i].date) {
                        sets[i].heartRatePeak = hrr.peak
                        sets[i].heartRateDrop60 = hrr.drop
                    }
                }
            }
            // A swap partway through leaves the first exercise's sets in the item: each exercise
            // keeps its own log, so its history and progression never see the other's loads.
            let planned = item.plan.substitutedFor ?? item.plan.exerciseID
            for group in sets.groupedByExercise() {
                exercises.append(
                    ExerciseLog(
                        slotID: item.plan.slotID, exerciseID: group.exerciseID, sets: group.sets,
                        substitutedFor: group.exerciseID == planned ? nil : planned))
            }
        }
        let average = samples.isEmpty ? nil : samples.map(\.bpm).reduce(0, +) / Double(samples.count)
        // Heat is kept apart from lifting: it isn't a set, and its rating isn't a rating of strength.
        let heat = items.filter { $0.plan.role == .recovery }.compactMap { item -> HeatLog? in
            if let heat = item.heat { return heat }
            // Timed on the Watch, without a thermometer reading.
            guard let done = item.loggedSets.last, let seconds = done.seconds, seconds > 0 else { return nil }
            return HeatLog(exerciseID: item.exerciseID, date: done.date, minutes: Double(seconds) / 60, temperatureC: nil, rating: nil)
        }
        return SessionRecord(
            id: id, start: startedAt, end: now, title: plan.title, mesocycleID: plan.mesocycleID, dayID: plan.dayID,
            planned: plan.mesocycleID != nil, deload: plan.deload, exercises: exercises, conditioning: conditioning,
            mobility: mobilityDone.filter { id in !items.contains { $0.exerciseID == id && $0.plan.role == .recovery } },
            feedback: feedback, device: device, averageHeartRate: average, heat: heat.isEmpty ? nil : heat,
            timeZoneID: timeZone.identifier, updatedAt: now)
    }
}
