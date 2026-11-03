import Foundation

public struct RepRange: Hashable, Codable, Sendable {
    public var lower: Int
    public var upper: Int

    public init(_ lower: Int, _ upper: Int) {
        self.lower = min(lower, upper)
        self.upper = max(lower, upper)
    }

    public var middle: Int { (lower + upper + 1) / 2 }
    public func contains(_ reps: Int) -> Bool { reps >= lower && reps <= upper }
    public var label: String { lower == upper ? "\(lower)" : "\(lower)–\(upper)" }
}

/// One set to do.
public struct SetPrescription: Hashable, Codable, Sendable {
    public var kind: SetKind
    /// Nil when the person picks: "a weight you think you can do for 7".
    public var loadKg: Double?
    public var targetReps: Int
    public var targetRIR: Double
    /// For rep-outs on free weights: stop at form breakdown, not the bar stopping.
    public var stopAtFormBreakdown: Bool
    /// Timed work: holds, carries, intervals.
    public var seconds: Int?

    public init(kind: SetKind, loadKg: Double?, targetReps: Int, targetRIR: Double, stopAtFormBreakdown: Bool = false, seconds: Int? = nil) {
        self.kind = kind
        self.loadKg = loadKg
        self.targetReps = targetReps
        self.targetRIR = targetRIR
        self.stopAtFormBreakdown = stopAtFormBreakdown
        self.seconds = seconds
    }
}

public enum ProgressionMode: String, Codable, Sendable {
    /// Week one: the person picks, rates, and the app adjusts until the weight is right.
    case findingWeight
    /// Fine increments: load rises, reps hold.
    case load
    /// Coarse increments (dumbbells, stacks, bodyweight): reps climb the range, then load steps up.
    case reps
    case deload
}

public struct ExercisePrescription: Hashable, Codable, Sendable {
    public var exerciseID: String
    public var sets: [SetPrescription]
    public var mode: ProgressionMode
    /// The trust-weighted estimate it was built from.
    public var e1rm: Double?
    public var reason: String

    public init(exerciseID: String, sets: [SetPrescription], mode: ProgressionMode, e1rm: Double?, reason: String) {
        self.exerciseID = exerciseID
        self.sets = sets
        self.mode = mode
        self.e1rm = e1rm
        self.reason = reason
    }
}

/// What a slot asks for this week.
public struct SlotTarget: Hashable, Codable, Sendable {
    public var sets: Int
    public var repRange: RepRange
    public var targetRIR: Double
    public var deload: Bool
    /// Make the last set a controlled rep-out.
    public var repOut: Bool
    /// A block's first loading week. It starts easier than the last block ended (more in reserve,
    /// and more reps when a size block follows a strength one), so the weight comes down to the
    /// target instead of holding within a step of the last block's heaviest.
    public var firstWeek: Bool

    public init(sets: Int, repRange: RepRange, targetRIR: Double, deload: Bool = false, repOut: Bool = false, firstWeek: Bool = false) {
        self.sets = max(1, sets)
        self.repRange = repRange
        self.targetRIR = targetRIR
        self.deload = deload
        self.repOut = repOut
        self.firstWeek = firstWeek
    }
}

public struct ProgressionContext: Sendable {
    public var exercise: any ExerciseTraits
    public var increments: any LoadIncrements
    public var trust: TrustState
    public var phase: PhaseEffects
    /// Fraction of normal load: an injury ramping back, or the week after time off.
    public var loadFactor: Double
    public var bodyweightKg: Double?
    /// Every past set of this exercise, oldest first.
    public var history: [LoggedSet]

    public init(
        exercise: any ExerciseTraits, increments: any LoadIncrements, trust: TrustState, phase: PhaseEffects,
        loadFactor: Double = 1, bodyweightKg: Double?, history: [LoggedSet]
    ) {
        self.exercise = exercise
        self.increments = increments
        self.trust = trust
        self.phase = phase
        self.loadFactor = loadFactor
        self.bodyweightKg = bodyweightKg
        self.history = history
    }
}

// MARK: - Loads in the exercise's own terms

enum LoadMath {
    /// One step harder (+1) or easier (−1). Assisted exercises get harder as assistance comes off.
    static func step(_ logged: Double, _ direction: Int, basis: LoadBasis, increments: any LoadIncrements) -> Double {
        increments.step(logged, direction: basis == .assisted ? -direction : direction)
    }

    /// Whether logged load `a` is harder than `b`: heavier, or for assisted exercises less assistance.
    static func harder(_ a: Double, _ b: Double, basis: LoadBasis) -> Bool { basis == .assisted ? a < b : a > b }

    static func effective(_ logged: Double, basis: LoadBasis, bodyweight: Double?) -> Double {
        OneRepMax.effectiveLoad(logged, basis: basis, bodyweightKg: bodyweight)
    }

    /// The logged load for an effective one, rounded so it never overshoots.
    static func logged(forEffective effective: Double, basis: LoadBasis, bodyweight: Double?, increments: any LoadIncrements) -> Double {
        let raw = OneRepMax.loggedLoad(forEffective: effective, basis: basis, bodyweightKg: bodyweight)
        // Rounding assistance down would make it harder; round it up instead.
        if basis == .assisted {
            let down = increments.round(raw, down: true)
            return down < raw - 1e-6 ? increments.step(down, direction: 1) : down
        }
        return increments.round(raw, down: true)
    }

    /// Whether load steps are too coarse to progress by load. From session to session, a step either
    /// way of more than 6% means reps climb the range instead (checking both ways keeps an exercise
    /// from flipping between modes at the boundary). From one set to the next, only an upward step
    /// of more than 12.5% is too coarse: a green set has about 10% in hand.
    static func coarse(
        _ logged: Double, basis: LoadBasis, bodyweight: Double?, increments: any LoadIncrements,
        setToSet: Bool = false
    ) -> Bool {
        switch basis {
        case .none: return true
        case .bodyweightPlus where logged <= 0: return true
        default: break
        }
        let now = effective(logged, basis: basis, bodyweight: bodyweight)
        guard now > 0 else { return true }
        let up = effective(step(logged, 1, basis: basis, increments: increments), basis: basis, bodyweight: bodyweight) - now
        if setToSet { return up / now > 0.125 }
        let down = now - effective(step(logged, -1, basis: basis, increments: increments), basis: basis, bodyweight: bodyweight)
        return max(up, down) / now > 0.06
    }
}

// MARK: - Set to set

public enum AdjustmentKind: String, Codable, Sendable {
    case bump, verify, hold, drop, found
}

public struct SetAdjustment: Hashable, Sendable {
    public var kind: AdjustmentKind
    public var next: SetPrescription
    /// Plain words: "Easy — up to 85 kg." Loads are formatted by the app.
    public var message: String
    /// How the next set's reps were worked out when it keeps the weight, so a shorter rest than
    /// planned can work them out again.
    public var fatigue: FatigueBasis? = nil
}

/// The next set adapts immediately to the rating. Green bumps the weight or reps to test the claim,
/// orange holds the weight, red holds it while the reps stay in the range and drops it slightly
/// below. Held weights aim for the reps the rest gives back (``SetFatigue``), so reps falling set to
/// set isn't a miss. A miss is no big deal, just data.
public enum Autoregulation {
    public struct Context: Sendable {
        public var exercise: any ExerciseTraits
        public var increments: any LoadIncrements
        public var trust: TrustState
        public var repRange: RepRange
        /// A verification push already happened for this exercise this session.
        public var verifiedAlready: Bool
        /// A rack with pins or safety arms, so racked barbell lifts are a safe setup too.
        public var hasSafeties: Bool
        /// The rest planned before the next set.
        public var restSeconds: Int

        public init(
            exercise: any ExerciseTraits, increments: any LoadIncrements, trust: TrustState, repRange: RepRange,
            verifiedAlready: Bool = false, hasSafeties: Bool = false, restSeconds: Int = SetFatigue.typicalRest
        ) {
            self.exercise = exercise
            self.increments = increments
            self.trust = trust
            self.repRange = repRange
            self.verifiedAlready = verifiedAlready
            self.hasSafeties = hasSafeties
            self.restSeconds = restSeconds
        }

        /// Verification pushes use controlled increments on safe setups only: machines, or a rack
        /// with safeties set. Never a maximal attempt.
        var safeSetup: Bool {
            switch exercise.safetyTier {
            case .safeToFail: true
            case .failWithSetup: hasSafeties && exercise.pattern != .hinge
            case .neverToFailure: false
            }
        }
    }

    public static func next(after done: LoggedSet, planned: SetPrescription, context: Context) -> SetAdjustment {
        let basis = context.exercise.loadBasis
        let bw = done.bodyweightKg
        var next = planned
        let current = done.loadKg
        next.loadKg = planned.loadKg == nil || planned.kind == .findingWeight ? current : planned.loadKg
        // A planned load the person beat or missed is replaced by what they actually did.
        if planned.kind != .repOut { next.loadKg = current }

        guard let rating = done.rating else {
            return SetAdjustment(kind: .hold, next: next, message: "Same again.")
        }
        if planned.kind == .deload || done.kind == .deload {
            if rating == .red {
                next.loadKg = LoadMath.step(current, -1, basis: basis, increments: context.increments)
                return SetAdjustment(kind: .drop, next: next, message: "Deload week: take a step off and keep it easy.")
            }
            return SetAdjustment(kind: .hold, next: next, message: "Deload week: same again, nowhere near failure.")
        }

        let finding = planned.kind == .findingWeight || done.kind == .findingWeight
        let fixedLoad = basis == .none || (basis == .bodyweightPlus && current <= 0)
        // Finding a weight always moves the weight; otherwise very coarse steps move reps instead.
        let coarse =
            fixedLoad
            || (!finding
                && LoadMath.coarse(
                    current, basis: basis, bodyweight: bw, increments: context.increments,
                    setToSet: true))
        let scale = SetFatigue.scale(of: context.exercise)
        // The next set at this weight, leaving `aim` in hand after a set that left `reserve`.
        func holding(reserve: Double, aim: Double) -> FatigueBasis {
            FatigueBasis(capacity: Double(done.reps) + reserve, reserve: reserve, aim: aim, scale: scale, restSeconds: context.restSeconds)
        }
        // Coarse steps are a big change in weight, so the reps may run a little under the range first.
        let fewest = coarse ? max(1, context.repRange.lower - 2) : context.repRange.lower
        let doneEffective = LoadMath.effective(current, basis: basis, bodyweight: bw)
        // Lighter for `reps`, from what the set says is left after the rest: never less than a step off.
        func lighter(_ hold: FatigueBasis, reps: Int) {
            guard !coarse, done.reps > 0, doneEffective > 0 else {
                next.loadKg = LoadMath.step(current, -1, basis: basis, increments: context.increments)
                return
            }
            let left = hold.capacity * (1 - SetFatigue.loss(reserve: hold.reserve, restSeconds: context.restSeconds, scale: scale))
            let effective = OneRepMax.load(e1rm: SetFatigue.e1rm(load: doneEffective, capacity: left), reps: reps, rir: hold.aim)
            var load = LoadMath.logged(forEffective: effective, basis: basis, bodyweight: bw, increments: context.increments)
            let oneDown = LoadMath.step(current, -1, basis: basis, increments: context.increments)
            if LoadMath.harder(load, oneDown, basis: basis) { load = oneDown }
            next.loadKg = load
            next.targetReps = reps
        }

        switch rating {
        case .red:
            // Failure: what they managed, less what the rest won't give back, with a rep in hand.
            // While that stays in the range the weight holds; below it, or while a weight is still
            // being found, the weight comes down instead.
            let hold = holding(reserve: 0, aim: 1)
            if done.reps > 0, fixedLoad || (!finding && hold.reps() >= fewest) {
                next.targetReps = hold.reps()
                return SetAdjustment(
                    kind: .hold, next: next, message: "Missed reps are just data. Same weight, aim for \(next.targetReps).", fatigue: hold)
            }
            lighter(hold, reps: finding ? max(1, next.targetReps) : max(1, min(next.targetReps, max(context.repRange.lower, done.reps))))
            return SetAdjustment(kind: .drop, next: next, message: "Missed reps are just data. Next set is a little lighter.")

        case .orange:
            let reserve = context.trust.reserve(for: .orange)
            let hold = holding(reserve: reserve, aim: reserve)
            if finding {
                next.kind = .working
                next.targetReps = hold.reps()
                let message =
                    next.targetReps < done.reps
                    ? "That's your working weight. Same weight, aim for \(next.targetReps): reps fall a bit as the sets add up."
                    : "That's your working weight. Same again."
                return SetAdjustment(kind: .found, next: next, message: message, fatigue: hold)
            }
            let canVerify = context.trust.isLow && context.safeSetup && !context.verifiedAlready
            if canVerify {
                // The reps the weight should give after the rest, with more weight or more reps:
                // an accurate "just right" makes this a near miss.
                if coarse {
                    next.targetReps = hold.reps() + 2
                } else {
                    next.loadKg = LoadMath.step(current, 1, basis: basis, increments: context.increments)
                    next.targetReps = hold.reps()
                }
                let check = coarse ? "\(next.targetReps) reps this time" : "one step up, for \(next.targetReps)"
                return SetAdjustment(
                    kind: .verify, next: next,
                    message: "You rated that just right. Let's check: \(check). If it's a miss, that's useful too.")
            }
            if fixedLoad || hold.reps() >= fewest {
                next.targetReps = hold.reps()
                let message =
                    next.targetReps < done.reps
                    ? "Just right. Same weight, aim for \(next.targetReps): reps fall a bit as the sets add up." : "Just right. Same again."
                return SetAdjustment(kind: .hold, next: next, message: message, fatigue: hold)
            }
            lighter(hold, reps: context.repRange.lower)
            return SetAdjustment(
                kind: .drop, next: next, message: "Just right. A little lighter now, to keep the reps in the \(context.repRange.label) range.")

        case .green:
            if coarse {
                next.targetReps = min(done.reps + 2, context.repRange.upper + 3)
                if planned.kind == .findingWeight { next.kind = .findingWeight }
                return SetAdjustment(kind: .bump, next: next, message: "Easy, so aim for \(next.targetReps) reps this time.")
            }
            let effective = doneEffective
            let reserve = context.trust.reserve(for: .green)
            // What was done, and as much of the claim as trust allows, less what the rest won't give back.
            let claimed = Double(done.reps) + max(context.trust.score, 0.5) * reserve
            let left = claimed * (1 - SetFatigue.loss(reserve: reserve, restSeconds: context.restSeconds, scale: scale))
            let e1rm = SetFatigue.e1rm(load: effective, capacity: left)
            let rir = planned.kind == .findingWeight ? 2 : max(1, planned.targetRIR)
            var load = LoadMath.logged(
                forEffective: OneRepMax.load(e1rm: e1rm, reps: max(1, next.targetReps), rir: rir),
                basis: basis, bodyweight: bw, increments: context.increments)
            let oneUp = LoadMath.step(current, 1, basis: basis, increments: context.increments)
            let maxSteps = planned.kind == .findingWeight ? 4 : 2
            var cap = current
            for _ in 0..<maxSteps { cap = LoadMath.step(cap, 1, basis: basis, increments: context.increments) }
            if !LoadMath.harder(load, current, basis: basis) { load = oneUp }
            if LoadMath.harder(load, cap, basis: basis) { load = cap }
            next.loadKg = load
            if planned.kind == .findingWeight { next.kind = .findingWeight }
            let kind: AdjustmentKind = context.trust.isLow ? .verify : .bump
            return SetAdjustment(
                kind: kind, next: next,
                message: kind == .verify ? "Easy? Let's test that: more weight, same reps." : "Easy, so the weight goes up.")
        }
    }
}

// MARK: - Session to session

public enum Progression {
    public static func prescribe(_ target: SlotTarget, _ context: ProgressionContext) -> ExercisePrescription {
        let exercise = context.exercise
        let basis = exercise.loadBasis
        let bw = context.bodyweightKg
        // Deload sessions never anchor progression: the next block builds on the last real one.
        let work = Progression.anchoringWork(context.history)
        guard let last = StrengthEstimator.sessions(work).last, let top = topSet(last, basis: basis) else {
            // Finding working weights, at the reps the sessions after will aim for.
            let reps = target.repRange.middle
            let sets = (0..<target.sets).map { _ in SetPrescription(kind: .findingWeight, loadKg: nil, targetReps: reps, targetRIR: 2) }
            return ExercisePrescription(
                exerciseID: exercise.id, sets: sets, mode: .findingWeight, e1rm: nil,
                reason: "Pick a weight you think you can do for \(reps), then rate it. The next set adjusts.")
        }

        let lastLoad = top.loadKg
        let topSets = last.filter { abs($0.loadKg - lastLoad) < 0.01 }
        // A miss that matters: the first top set fell short, or more than one fell shorter than
        // the sets before them and their rests explain. Reps falling set to set is fatigue.
        let missed = topSets.first?.rating == .red || shortfalls(last, at: lastLoad, exercise: exercise, trust: context.trust) >= 2
        let allGreen = !topSets.isEmpty && topSets.allSatisfy { $0.rating == .green }
        let bestReps = topSets.map(\.reps).max() ?? top.reps

        let recentBest = StrengthEstimator.current(work, basis: basis, trust: context.trust)
        let lastEstimate = StrengthEstimator.sessionBests(last, basis: basis, trust: context.trust).last?.e1rm
        var e1rm = lastEstimate ?? recentBest
        if let best = recentBest, let estimate = e1rm { e1rm = max(estimate, best * 0.97) }

        var sets: [SetPrescription] = []
        var mode: ProgressionMode
        var reason: String
        let coarse = LoadMath.coarse(lastLoad, basis: basis, bodyweight: bw, increments: context.increments)
        let rir = target.deload ? 4 : target.targetRIR

        if target.deload {
            mode = .deload
            // An injury ramp or a week back scales the effective load before rounding, so assisted
            // lifts get more assistance (not less) and the load is one the gym can make.
            let effective = LoadMath.effective(lastLoad, basis: basis, bodyweight: bw) * deloadShare * context.loadFactor
            let load = LoadMath.logged(forEffective: effective, basis: basis, bodyweight: bw, increments: context.increments)
            let reps = max(target.repRange.lower, min(bestReps, target.repRange.middle))
            let count = max(1, Int((Double(target.sets) / 2).rounded(.up)))
            sets = (0..<count).map { _ in SetPrescription(kind: .deload, loadKg: load, targetReps: reps, targetRIR: rir) }
            reason = "Deload: fewer sets, lighter, well short of failure."
        } else if coarse {
            mode = .reps
            var load = lastLoad
            var reps: Int
            if bestReps >= target.repRange.upper && !missed {
                load = LoadMath.step(lastLoad, 1, basis: basis, increments: context.increments)
                reps = target.repRange.lower
                reason = "Top of the range last time, so the weight goes up and reps start again at \(reps)."
            } else if missed {
                reps = max(target.repRange.lower, bestReps)
                reason = "Last time was a miss, so the same target again."
            } else {
                reps = min(target.repRange.upper, bestReps + (allGreen ? 2 : 1))
                reps = max(reps, target.repRange.lower)
                reason = allGreen ? "Easy last time: two more reps." : "One more rep than last time."
            }
            if basis == .none || (basis == .bodyweightPlus && load <= 0) { load = 0 }
            if context.loadFactor < 1 { reps = max(target.repRange.lower, Int(Double(reps) * context.loadFactor)) }
            sets = (0..<target.sets).map { _ in SetPrescription(kind: .working, loadKg: load, targetReps: reps, targetRIR: rir) }
        } else {
            mode = .load
            let reps = target.repRange.middle
            var load = lastLoad
            if let e1rm {
                load = LoadMath.logged(
                    forEffective: OneRepMax.load(e1rm: e1rm, reps: reps, rir: rir) * context.loadFactor,
                    basis: basis, bodyweight: bw, increments: context.increments)
            }
            var cap = lastLoad
            let steps = missed ? 0 : context.phase.maxLoadStepsPerSession
            for _ in 0..<steps { cap = LoadMath.step(cap, 1, basis: basis, increments: context.increments) }
            if LoadMath.harder(load, cap, basis: basis) { load = cap }
            if context.loadFactor >= 1, !missed, !target.firstWeek {
                // Don't slide back more than a step on a single off day. A block's first week is
                // meant to be lighter, and the estimate stays within 3% of the recent best anyway.
                let floor = LoadMath.step(lastLoad, -1, basis: basis, increments: context.increments)
                if LoadMath.harder(floor, load, basis: basis) { load = floor }
            }
            if LoadMath.harder(load, lastLoad, basis: basis) {
                reason = "Your estimate says \(reps) reps with \(rir.formatted()) in reserve is a step up from last time."
            } else if load == lastLoad {
                reason =
                    missed ? "Last time was a miss, so the same weight again." : "Same weight, aiming for \(reps) reps with \(rir.formatted()) left."
            } else {
                reason = context.loadFactor < 1 ? "Easing back in after time off." : "A little lighter to land the target reps."
            }
            sets = (0..<target.sets).map { _ in SetPrescription(kind: .working, loadKg: load, targetReps: reps, targetRIR: rir) }
        }

        // Rep-outs land in the assessment and at check-ins (the end of a deload, when fresh). A
        // check-in rep-out uses the last working weight so the reps stay where Epley is accurate.
        // None while the lift is easing back in (an injury ramp, a week back): failure, and at the
        // full working weight, is what the ramp is there to avoid.
        if target.repOut, context.loadFactor >= 1, var lastSet = sets.last {
            if target.deload {
                lastSet.loadKg = lastLoad
                lastSet.targetReps = target.repRange.middle
            }
            lastSet.kind = .repOut
            lastSet.targetRIR = 0
            lastSet.stopAtFormBreakdown = FailurePolicy.stopAtFormBreakdown(exercise, trust: context.trust)
            sets[sets.count - 1] = lastSet
            reason += lastSet.stopAtFormBreakdown ? " Last set: reps until your form starts to slip." : " Last set: as many reps as you can."
        }
        return ExercisePrescription(exerciseID: exercise.id, sets: sets, mode: mode, e1rm: e1rm, reason: reason)
    }

    /// Reps in reserve to aim for across a loading block: start comfortable, finish close to
    /// failure. RP-style.
    public static func targetRIR(week: Int, of loadingWeeks: Int) -> Double {
        guard loadingWeeks > 1 else { return 2 }
        let t = Double(week) / Double(loadingWeeks - 1)
        return (3 - 2.5 * t).roundedToNearestHalf()
    }

    /// A deload's share of the last working load, in effective terms.
    static let deloadShare = 0.88

    /// The sets that anchor progression: work with reps, never warm-ups or deload sets.
    static func anchoringWork(_ history: [LoggedSet]) -> [LoggedSet] {
        history.filter { $0.kind.countsAsWork && $0.kind != .deload && $0.reps > 0 }
    }

    /// Missed sets at a weight that fatigue doesn't explain: a miss after a set at another weight,
    /// or more than a rep short of what the set before at the same weight left after its rest.
    static func shortfalls(_ session: [LoggedSet], at load: Double, exercise: some ExerciseTraits, trust: TrustState) -> Int {
        session.indices.filter { k in
            let set = session[k]
            guard set.rating == .red, abs(set.loadKg - load) < 0.01 else { return false }
            guard k > 0, abs(session[k - 1].loadKg - set.loadKg) < 0.01 else { return true }
            let before = session[k - 1]
            let reserve = before.rating.map { trust.reserve(for: $0) } ?? (before.reachedFailure ? 0 : 1)
            let left = SetFatigue.capacity(after: before.reps, reserve: reserve, restSeconds: SetFatigue.rest(before: set), exercise: exercise)
            return Double(set.reps) < left - Calibration.tolerance
        }.count
    }

    /// The heaviest set of a session, by effective load.
    static func topSet(_ session: [LoggedSet], basis: LoadBasis) -> LoggedSet? {
        session.max { a, b in
            LoadMath.effective(a.loadKg, basis: basis, bodyweight: a.bodyweightKg)
                < LoadMath.effective(b.loadKg, basis: basis, bodyweight: b.bodyweightKg)
        }
    }
}

extension Double {
    func roundedToNearestHalf() -> Double { (self * 2).rounded() / 2 }
}

// MARK: - Stalls

public struct StallReport: Hashable, Codable, Sendable, Identifiable {
    public enum Reading: String, Codable, Sendable {
        /// During a cut: expected, not a plateau.
        case expectedInDeficit
        /// Beat up and stalled: a recovery problem before a programming one.
        case recovery
        /// A real signal: change something.
        case programming
    }

    public var exerciseID: String
    public var weeks: Int
    public var bestE1RM: Double
    public var since: Day
    public var reading: Reading
    /// The progressive-overload prompt: "next session, 82.5 kg for 3×5".
    public var suggestion: SetPrescription?
    public var suggestedSets: Int

    public var id: String { exerciseID }
}

public enum Stalls {
    /// A lift that hasn't set a new best (by more than 1%) for three or more weeks, across at
    /// least three sessions.
    public static func detect(
        _ context: ProgressionContext, sets: Int, repRange: RepRange, today: Day,
        phase: PhaseEffects, beatUp: Bool
    ) -> StallReport? {
        let basis = context.exercise.loadBasis
        let bests = StrengthEstimator.sessionBests(context.history, basis: basis, trust: context.trust)
            .filter { $0.day >= today.adding(days: -84) }
        guard bests.count >= 4 else { return nil }
        var best = bests[0].e1rm
        var bestDay = bests[0].day
        for point in bests.dropFirst() where point.e1rm > best * 1.01 {
            best = point.e1rm
            bestDay = point.day
        }
        let since = bests.filter { $0.day > bestDay }.count
        let days = bestDay.days(until: today)
        guard days >= 21, since >= 3 else { return nil }
        let reading: StallReport.Reading = phase.stallsExpected ? .expectedInDeficit : (beatUp ? .recovery : .programming)

        // The prompt: the smallest overload from the last top set, at the bottom of the range. A
        // deload's lighter sets never set new bests, so the stall outlasts the deload; the prompt
        // still builds on the last real session, as `prescribe` does.
        var suggestion: SetPrescription?
        if let session = StrengthEstimator.sessions(Progression.anchoringWork(context.history)).last,
            let top = Progression.topSet(session, basis: basis)
        {
            let reps = reading == .programming ? max(repRange.lower, min(5, repRange.upper)) : repRange.middle
            let load =
                reading == .programming
                ? LoadMath.step(top.loadKg, 1, basis: basis, increments: context.increments)
                : top.loadKg
            suggestion = SetPrescription(kind: .working, loadKg: load, targetReps: reps, targetRIR: 1)
        }
        return StallReport(
            exerciseID: context.exercise.id, weeks: days / 7, bestE1RM: best, since: bestDay, reading: reading,
            suggestion: suggestion, suggestedSets: reading == .programming ? 3 : sets)
    }
}
