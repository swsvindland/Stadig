import Foundation
import ExerciseLibrary
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

    public init(catalog: ExerciseCatalog, gym: Gym, trust: TrustState, phase: PhaseEffects, bodyweightKg: Double?,
                history: [String: [LoggedSet]], enduranceScore: Double?, heartRateGuidedRest: Bool) {
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

    public init(id: UUID = UUID(), prescription: SetPrescription, logged: LoggedSet? = nil, skipped: Bool = false, note: String? = nil) {
        self.id = id
        self.prescription = prescription
        self.logged = logged
        self.skipped = skipped
        self.note = note
    }

    public var isOpen: Bool { logged == nil && !skipped }
}

public struct LiveItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var plan: PlannedItem
    public var exerciseID: String
    public var sets: [LiveSet]
    public var skipped: Bool
    public var verified: Bool
    public var conditioning: ConditioningLog?

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

    // MARK: Where we are

    /// The next thing to do: the first open item, alternating within a superset.
    public var current: (item: Int, set: Int)? {
        guard let first = items.firstIndex(where: { !$0.isDone }) else { return nil }
        if let group = items[first].plan.supersetGroup {
            let members = items.indices.filter { items[$0].plan.supersetGroup == group && !items[$0].isDone }
            // The member with the fewest logged sets goes next.
            if let pick = members.min(by: { items[$0].sets.filter { !$0.isOpen }.count < items[$1].sets.filter { !$0.isOpen }.count }),
               let set = items[pick].nextSet {
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
    public mutating func log(item index: Int, set setIndex: Int, reps: Int, loadKg: Double?, rating: SetRating?, seconds: Int? = nil,
                             heartRatePeak: Double? = nil, environment: SessionEnvironment, now: Date = Date()) -> SetAdjustment? {
        guard items.indices.contains(index), items[index].sets.indices.contains(setIndex) else { return nil }
        var item = items[index]
        let exercise = environment.catalog.resolve(item.exerciseID)
        let prescription = item.sets[setIndex].prescription
        let restBefore = rest.map { Int(now.timeIntervalSince($0.started)) }
        let logged = LoggedSet(exerciseID: item.exerciseID, date: now, kind: prescription.kind, loadKg: loadKg ?? prescription.loadKg ?? 0,
                               reps: reps, targetReps: prescription.targetReps, rating: prescription.kind == .warmup ? nil : rating,
                               bodyweightKg: environment.bodyweightKg, stoppedAtFormBreakdown: prescription.stopAtFormBreakdown,
                               restBeforeSeconds: restBefore, heartRatePeak: heartRatePeak, seconds: seconds)
        item.sets[setIndex].logged = logged
        var adjustment: SetAdjustment?
        if item.plan.isStrength, prescription.kind != .warmup, rating != nil,
           let next = item.sets.indices.first(where: { $0 > setIndex && item.sets[$0].isOpen && item.sets[$0].prescription.kind != .warmup }) {
            let context = Autoregulation.Context(exercise: exercise, increments: environment.increments(for: exercise), trust: environment.trust,
                                                 repRange: item.plan.repRange, verifiedAlready: item.verified,
                                                 hasSafeties: environment.gym.hasSafeties)
            let result = Autoregulation.next(after: logged, planned: item.sets[next].prescription, context: context)
            adjustment = result
            if result.kind == .verify { item.verified = true }
            // The adjustment carries to every remaining set; a rep-out keeps its kind.
            for later in item.sets.indices where later >= next && item.sets[later].isOpen {
                let kind = item.sets[later].prescription.kind
                var updated = result.next
                if kind == .repOut {
                    updated.kind = .repOut
                    updated.targetRIR = 0
                    updated.stopAtFormBreakdown = item.sets[later].prescription.stopAtFormBreakdown
                }
                item.sets[later].prescription = updated
                item.sets[later].note = later == next ? result.message : nil
            }
            message = result.message
            lastAdjustment = result.kind
        } else {
            message = nil
        }
        // A finding-weight set with no load yet takes the weight just used.
        if prescription.kind == .findingWeight {
            for later in item.sets.indices where later > setIndex && item.sets[later].isOpen && item.sets[later].prescription.loadKg == nil {
                item.sets[later].prescription.loadKg = logged.loadKg
            }
        }
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
        guard items.indices.contains(index) else { return }
        let last = items[index].sets.last { $0.prescription.kind != .warmup }
        var prescription = last?.prescription ?? SetPrescription(kind: .working, loadKg: nil, targetReps: items[index].plan.repRange.middle, targetRIR: 2)
        if prescription.kind == .repOut { prescription.kind = .working; prescription.targetRIR = 1 }
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
        let target = SlotTarget(sets: max(1, open.count), repRange: item.plan.repRange, targetRIR: open.first?.prescription.targetRIR ?? 2,
                                deload: open.first?.prescription.kind == .deload)
        let context = ProgressionContext(exercise: exercise, increments: environment.increments(for: exercise), trust: environment.trust,
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
        items[index].conditioning = ConditioningLog(exerciseID: items[index].exerciseID, minutes: minutes,
                                                    averageHeartRate: averageHeartRate, zoneMinutes: zoneMinutes, zone: zone)
        for s in items[index].sets.indices where items[index].sets[s].isOpen {
            items[index].sets[s].logged = LoggedSet(exerciseID: items[index].exerciseID, date: now, kind: .working, loadKg: 0, reps: 1,
                                                    seconds: minutes * 60)
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
           let current, items[current.item].id != item.id {
            rest = RestState(started: now, plan: RestPlan(target: 20, minimum: 0, heartRateGuided: false), itemID: item.id,
                             endsAt: now.addingTimeInterval(20), preSetHeartRate: nil, filler: nil)
            return
        }
        let plan = item.plan.rest
        guard plan.target > 0, !isComplete else {
            rest = nil
            return
        }
        let preSet = heartRateSamples.last { $0.date <= now.addingTimeInterval(-30) }?.bpm
        rest = RestState(started: now, plan: plan, itemID: item.id, endsAt: now.addingTimeInterval(TimeInterval(plan.target)),
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

    /// Feeds live heart rate (Watch). Returns true when a heart-rate-guided rest has recovered.
    @discardableResult
    public mutating func record(heartRate bpm: Double, zones: HeartRateZones, now: Date = Date()) -> Bool {
        heartRateSamples.append(HeartRatePoint(date: now, bpm: bpm))
        if heartRateSamples.count > 4000 { heartRateSamples.removeFirst(heartRateSamples.count - 4000) }
        guard let state = rest else { return false }
        let elapsed = Int(now.timeIntervalSince(state.started))
        return Rest.recovered(heartRate: bpm, preSet: state.preSetHeartRate, zones: zones, elapsed: elapsed, plan: state.plan)
    }

    // MARK: Finish

    public func record(feedback: SessionFeedback?, now: Date = Date()) -> SessionRecord {
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
            exercises.append(ExerciseLog(slotID: item.plan.slotID, exerciseID: item.exerciseID, sets: sets, substitutedFor: item.plan.substitutedFor))
        }
        let average = samples.isEmpty ? nil : samples.map(\.bpm).reduce(0, +) / Double(samples.count)
        return SessionRecord(id: id, start: startedAt, end: now, title: plan.title, mesocycleID: plan.mesocycleID, dayID: plan.dayID,
                             planned: plan.mesocycleID != nil, deload: plan.deload, exercises: exercises, conditioning: conditioning,
                             mobility: mobilityDone, feedback: feedback, device: device, averageHeartRate: average, updatedAt: now)
    }
}
