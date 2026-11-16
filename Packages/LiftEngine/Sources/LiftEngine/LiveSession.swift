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

    public func increments(for exercise: Exercise) -> GymIncrements { gym.increments(for: exercise) }
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
    /// How its reps were worked out from the set before at the same weight, so a rest cut short can
    /// work them out again.
    public var fatigue: FatigueBasis?

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
        fatigue = try c.decodeIfPresent(FatigueBasis.self, forKey: .fatigue)
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
    /// message, and every later one the same weight, its reps falling on from the next one's as
    /// fatigue says; a rep-out keeps its kind. Nil when no open work set is left after it.
    mutating func adjustOpenSets(after logged: LoggedSet, at index: Int, environment: SessionEnvironment) -> SetAdjustment? {
        guard let next = sets.indices.first(where: { $0 > index && sets[$0].isOpen && sets[$0].prescription.kind != .warmup }) else { return nil }
        let exercise = environment.catalog.resolve(exerciseID)
        let context = Autoregulation.Context(
            exercise: exercise, increments: environment.increments(for: exercise), trust: environment.trust,
            repRange: plan.repRange, verifiedAlready: verified, hasSafeties: environment.gym.hasSafeties,
            restSeconds: plan.rest.target > 0 ? plan.rest.target : SetFatigue.typicalRest)
        let result = Autoregulation.next(after: logged, planned: sets[next].prescription, context: context)
        if result.kind == .verify { verified = true }
        var updated = result.next
        var basis = result.fatigue
        for later in sets.indices where later >= next && sets[later].isOpen {
            // Each later set as if the one before it comes out as aimed; they're worked out again
            // as each is logged, lighter by then if the reps would fall below the range.
            if later > next, let following = basis?.following {
                basis = following
                updated.targetReps = min(updated.targetReps, max(plan.repRange.lower, following.reps()))
            }
            var set = updated
            if sets[later].prescription.kind == .repOut {
                set.kind = .repOut
                set.targetRIR = 0
                set.stopAtFormBreakdown = sets[later].prescription.stopAtFormBreakdown
            }
            sets[later].prescription = set
            sets[later].note = later == next ? result.message : nil
            sets[later].fatigue = later == next ? result.fatigue : nil
        }
        return result
    }

    /// A rest cut short (skipped, or ended by a recovered heart rate) leaves less in the next set:
    /// its reps are worked out again for the rest taken, and the sets after it follow on.
    mutating func retarget(next index: Int, restTaken seconds: Int) {
        guard let basis = sets[index].fatigue, seconds < basis.restSeconds else { return }
        let reps = basis.reps(restSeconds: seconds)
        guard reps < sets[index].prescription.targetReps else { return }
        sets[index].prescription.targetReps = reps
        sets[index].note = "A shorter rest, so aim for \(reps)."
        var following = FatigueBasis(
            capacity: Double(reps) + basis.aim, reserve: basis.aim, aim: basis.aim, scale: basis.scale, restSeconds: basis.restSeconds)
        for later in sets.indices where later > index && sets[later].isOpen && sets[later].prescription.kind != .warmup {
            sets[later].prescription.targetReps = min(sets[later].prescription.targetReps, max(plan.repRange.lower, following.reps()))
            following = following.following
        }
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

    /// The heart rate that ends this rest early once its minimum has passed ("go at 105"): the
    /// highest whole bpm `Rest.recovered` takes as recovered. Nil when heart rate doesn't guide it.
    public func recoveredAt(zones: HeartRateZones) -> Int? {
        guard plan.heartRateGuided else { return nil }
        let recovered = { (bpm: Int) in
            Rest.recovered(heartRate: Double(bpm), preSet: preSetHeartRate, zones: zones, elapsed: plan.minimum, plan: plan)
        }
        // Recovered is every reading at or under one threshold: find it by halving.
        var low = 0
        var high = 250
        guard recovered(low) else { return nil }
        while low < high {
            let middle = (low + high + 1) / 2
            if recovered(middle) { low = middle } else { high = middle - 1 }
        }
        return low
    }
}

/// The set just logged, and the session as it stood before: what Undo puts back. It's kept from a
/// set's log until the next set is logged or the exercises change some other way (a swap, a skip,
/// a set added, a correction, Do This Now), so Undo only ever takes back the last set, and only
/// while nothing has been built on it; the rest running after it can be skipped or changed meanwhile.
public struct LoggedSetUndo: Codable, Hashable, Sendable {
    public var itemID: UUID
    public var setID: UUID
    /// The exercise before the set was logged: the set open, and the later sets' targets and notes
    /// before its rating adjusted them (or a rest cut short after it lowered them).
    var item: LiveItem
    /// The rest before: the one the set followed, timed from, or none.
    var rest: RestState?
    var message: String?
    var lastAdjustment: AdjustmentKind?
    var mobilityDone: [String]
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
    /// How many of the Watch's changes this session has taken (`take`), in the Watch's numbering, so
    /// one that arrives twice or early isn't taken again, and the Watch can tell which have landed.
    public var takenChanges: Int
    /// What Undo takes back, while there's something to (`undoableSet`). Only a set logged on this
    /// device: one the Watch logged (`apply`) leaves none, and the copy the Watch is sent has none.
    public internal(set) var undo: LoggedSetUndo?

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
        takenChanges = 0
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
        takenChanges = try c.decodeIfPresent(Int.self, forKey: .takenChanges) ?? 0
        // Only a convenience, like the rest: one that can't be read leaves nothing to undo.
        undo = try? c.decodeIfPresent(LoggedSetUndo.self, forKey: .undo)
    }

    // MARK: Where we are

    /// The next thing to do: the first open item, alternating within a superset. A superset pairs
    /// work sets: each member's warm-ups run straight through first, in order, so the partner's work
    /// never lands between a lift's warm-ups; then the member with the fewest work sets done goes
    /// next, the first of them on a tie.
    public var current: (item: Int, set: Int)? {
        guard let first = items.firstIndex(where: { !$0.isDone }) else { return nil }
        if let group = items[first].plan.supersetGroup {
            let members = items.indices.filter { items[$0].plan.supersetGroup == group && !items[$0].isDone }
            for member in members {
                if let set = items[member].nextSet, items[member].sets[set].prescription.kind == .warmup { return (member, set) }
            }
            func workDone(_ index: Int) -> Int { items[index].sets.filter { !$0.isOpen && $0.prescription.kind != .warmup }.count }
            if let pick = members.min(by: { workDone($0) < workDone($1) }), let set = items[pick].nextSet {
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
        undo = LoggedSetUndo(
            itemID: item.id, setID: item.sets[setIndex].id, item: item, rest: rest, message: message, lastAdjustment: lastAdjustment,
            mobilityDone: mobilityDone)
        let prescription = item.sets[setIndex].prescription
        // From the exercise's last set when there is one, so a skipped rest still counts, and in a
        // superset it's the time this exercise had, its partner's set included.
        let previous = item.sets.compactMap { $0.logged?.date }.max()
        let restBefore = (previous ?? rest?.started).map { Int(now.timeIntervalSince($0)) }
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
        startRest(after: index, warmup: prescription.kind == .warmup, environment: environment, now: now)
        // Warm-ups need only a short breather. The last one, at or near the working weight, gets
        // half the work's rest, so the first work set doesn't start tired from it.
        if prescription.kind == .warmup, var state = rest {
            let next = item.sets.indices.first { $0 > setIndex && item.sets[$0].isOpen }
            let beforeWork = next.map { item.sets[$0].prescription.kind != .warmup } ?? false
            let breather = beforeWork ? max(45, item.plan.rest.target / 2) : 45
            if state.plan.target > breather {
                state.plan = RestPlan(target: breather, minimum: 0, heartRateGuided: false)
                state.endsAt = now.addingTimeInterval(TimeInterval(breather))
                rest = state
            }
        }
        updatedAt = now
        return adjustment
    }

    /// The set Undo takes back: the last one logged on this device, while nothing has been built on it.
    public var undoableSet: (item: Int, set: Int, logged: LoggedSet)? {
        guard let undo, let index = item(undo.itemID), let set = items[index].sets.firstIndex(where: { $0.id == undo.setID }),
            let logged = items[index].sets[set].logged
        else { return nil }
        return (index, set, logged)
    }

    /// Takes back the last set logged: it's open again, and everything logging it did is undone, the
    /// rest it started (put back to the one before, which may well have run out), its rating's
    /// adjustment of the sets after it and its message, a finding weight carried on, a drill counted
    /// done. The set's numbers are gone from the session, so they count for nothing, the rating's
    /// evidence about how far it can be trusted included. Logging it again does exactly what logging
    /// it the first time would have. Returns false, changing nothing, when there's nothing to undo.
    @discardableResult
    public mutating func undoLastSet(now: Date = Date()) -> Bool {
        guard let undo, undoableSet != nil, let index = item(undo.itemID) else { return false }
        items[index] = undo.item
        rest = undo.rest
        message = undo.message
        lastAdjustment = undo.lastAdjustment
        mobilityDone = undo.mobilityDone
        self.undo = nil
        updatedAt = now
        return true
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
        undo = nil
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
            item.sets[i].fatigue = nil
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
        undo = nil
        updatedAt = now
    }

    /// Whether an exercise is in a superset still under way: it and a partner both have sets to go.
    public func canSplitSuperset(item index: Int) -> Bool {
        guard items.indices.contains(index), let group = items[index].plan.supersetGroup, !items[index].isDone else { return false }
        return items.indices.contains { $0 != index && items[$0].plan.supersetGroup == group && !items[$0].isDone }
    }

    /// Breaks a superset up for the rest of the session (the gym's busy, and the partner's bench or
    /// bar won't stay free): its exercises are done one after the other, in the order they're in,
    /// each with its own rests. A quick switch to the partner that's running becomes the exercise's
    /// own rest, timed from the same set. The session runs longer than planned for it.
    public mutating func splitSuperset(item index: Int, now: Date = Date()) {
        guard items.indices.contains(index), let group = items[index].plan.supersetGroup else { return }
        let members = items.indices.filter { items[$0].plan.supersetGroup == group }
        for member in members { items[member].plan.supersetGroup = nil }
        if var state = rest, let resting = item(state.itemID), members.contains(resting),
            items[resting].sets.last(where: { $0.logged != nil })?.logged?.kind != .warmup,
            state.plan.target < items[resting].plan.rest.target
        {
            state.plan = items[resting].plan.rest
            state.endsAt = state.started.addingTimeInterval(TimeInterval(state.plan.target))
            state.filler = items[resting].plan.restFiller
            rest = state
        }
        // Undo would put back one half of the pair.
        undo = nil
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
        undo = nil
        updatedAt = now
    }

    public mutating func skip(item index: Int, now: Date = Date()) {
        guard items.indices.contains(index) else { return }
        items[index].skipped = true
        if rest?.itemID == items[index].id { rest = nil }
        undo = nil
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
        undo = nil
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
        // Swapped before anything was done or skipped: the new exercise warms up its own way.
        var warmups: [SetPrescription] = []
        if item.sets.isEmpty, let first = prescription.sets.first, first.kind != .findingWeight, let load = first.loadKg {
            warmups = Warmup.sets(
                to: load, reps: first.targetReps, targetRIR: first.targetRIR, exercise: exercise, role: item.plan.role,
                increments: environment.increments(for: exercise))
        }
        item.sets += (warmups + prescription.sets).map { LiveSet(prescription: $0) }
        item.plan.note = prescription.reason
        item.verified = false
        items[index] = item
        undo = nil
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
        undo = nil
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
        undo = nil
        updatedAt = now
    }

    // MARK: Rest

    /// The rest after a set of the item at `index`; `warmup` when the set was a warm-up.
    public mutating func startRest(after index: Int, warmup: Bool = false, environment: SessionEnvironment, now: Date = Date()) {
        let item = items[index]
        // Within a superset, move straight to the partner: after a work set, or on to the partner's
        // warm-ups. The last warm-up before the pairing starts keeps its breather (`log`), so the
        // first work set isn't done straight off it.
        if let group = item.plan.supersetGroup,
            items.contains(where: { $0.id != item.id && $0.plan.supersetGroup == group && !$0.isDone }),
            let current, items[current.item].id != item.id,
            !warmup || items[current.item].sets[current.set].prescription.kind == .warmup
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

    /// Ends the rest: skipped, recovered, or the next exercise taken first. When the next set is the
    /// same exercise's and the rest was shorter than its reps assumed, they're worked out again.
    public mutating func endRest(now: Date = Date()) {
        if let rest, let current, items[current.item].id == rest.itemID, items[current.item].plan.supersetGroup == nil {
            items[current.item].retarget(next: current.set, restTaken: Int(now.timeIntervalSince(rest.started)))
        }
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
