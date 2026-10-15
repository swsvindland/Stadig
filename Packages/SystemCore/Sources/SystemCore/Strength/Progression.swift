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
    /// Nil when the person picks: "a weight you think you can do for 10".
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

    public init(sets: Int, repRange: RepRange, targetRIR: Double, deload: Bool = false, repOut: Bool = false) {
        self.sets = max(1, sets)
        self.repRange = repRange
        self.targetRIR = targetRIR
        self.deload = deload
        self.repOut = repOut
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

    public init(exercise: any ExerciseTraits, increments: any LoadIncrements, trust: TrustState, phase: PhaseEffects,
                loadFactor: Double = 1, bodyweightKg: Double?, history: [LoggedSet]) {
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
    static func coarse(_ logged: Double, basis: LoadBasis, bodyweight: Double?, increments: any LoadIncrements,
                       setToSet: Bool = false) -> Bool {
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
}

/// The next set adapts immediately to the rating. Green bumps the weight or reps to test the claim,
/// orange holds, red drops the load slightly. A miss is no big deal, just data.
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

        public init(exercise: any ExerciseTraits, increments: any LoadIncrements, trust: TrustState, repRange: RepRange,
                    verifiedAlready: Bool = false, hasSafeties: Bool = false) {
            self.exercise = exercise
            self.increments = increments
            self.trust = trust
            self.repRange = repRange
            self.verifiedAlready = verifiedAlready
            self.hasSafeties = hasSafeties
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
        let coarse = fixedLoad || (!finding && LoadMath.coarse(current, basis: basis, bodyweight: bw, increments: context.increments,
                                                                setToSet: true))
        switch rating {
        case .red:
            // What they managed, to failure, sets the load for the target with a rep in hand.
            let doneEffective = LoadMath.effective(current, basis: basis, bodyweight: bw)
            let target = max(1, next.targetReps)
            if done.reps > 0, doneEffective > 0, !coarse {
                let e1rm = OneRepMax.epley(doneEffective, reps: done.reps)
                let effective = OneRepMax.load(e1rm: e1rm, reps: target, rir: 1)
                var load = LoadMath.logged(forEffective: effective, basis: basis, bodyweight: bw, increments: context.increments)
                let oneDown = LoadMath.step(current, -1, basis: basis, increments: context.increments)
                if basis == .assisted ? load < oneDown : load > oneDown { load = oneDown }
                next.loadKg = load
            } else if coarse, done.reps >= max(1, target - 2) {
                // Coarse jumps: keep the load and aim for what was actually done.
                next.targetReps = max(1, done.reps)
            } else {
                next.loadKg = LoadMath.step(current, -1, basis: basis, increments: context.increments)
            }
            if planned.kind == .findingWeight { next.kind = .findingWeight }
            return SetAdjustment(kind: .drop, next: next, message: "Missed reps are just data. Next set is a little lighter.")

        case .orange:
            if finding {
                next.kind = .working
                return SetAdjustment(kind: .found, next: next, message: "That's your working weight. Same again.")
            }
            let canVerify = context.trust.isLow && context.safeSetup && !context.verifiedAlready
            if canVerify {
                if coarse {
                    next.targetReps = done.reps + 2
                } else {
                    next.loadKg = LoadMath.step(current, 1, basis: basis, increments: context.increments)
                    next.targetReps = done.reps
                }
                return SetAdjustment(kind: .verify, next: next,
                                     message: "You rated that just right. Let's check: same reps, one step up. If it's a miss, that's useful too.")
            }
            return SetAdjustment(kind: .hold, next: next, message: "Just right. Same again.")

        case .green:
            if coarse {
                next.targetReps = min(done.reps + 2, context.repRange.upper + 3)
                if planned.kind == .findingWeight { next.kind = .findingWeight }
                return SetAdjustment(kind: .bump, next: next, message: "Easy, so aim for \(next.targetReps) reps this time.")
            }
            let effective = LoadMath.effective(current, basis: basis, bodyweight: bw)
            let reserve = context.trust.reserve(for: .green)
            let floor = OneRepMax.epley(effective, reps: done.reps)
            let claimed = OneRepMax.epley(effective, reps: done.reps, rir: reserve)
            let e1rm = floor + max(context.trust.score, 0.5) * (claimed - floor)
            let rir = planned.kind == .findingWeight ? 2 : max(1, planned.targetRIR)
            var load = LoadMath.logged(forEffective: OneRepMax.load(e1rm: e1rm, reps: max(1, next.targetReps), rir: rir),
                                       basis: basis, bodyweight: bw, increments: context.increments)
            let oneUp = LoadMath.step(current, 1, basis: basis, increments: context.increments)
            let maxSteps = planned.kind == .findingWeight ? 4 : 2
            var cap = current
            for _ in 0..<maxSteps { cap = LoadMath.step(cap, 1, basis: basis, increments: context.increments) }
            let harder: (Double, Double) -> Bool = { a, b in basis == .assisted ? a < b : a > b }
            if !harder(load, current) { load = oneUp }
            if harder(load, cap) { load = cap }
            next.loadKg = load
            if planned.kind == .findingWeight { next.kind = .findingWeight }
            let kind: AdjustmentKind = context.trust.isLow ? .verify : .bump
            return SetAdjustment(kind: kind, next: next,
                                 message: kind == .verify ? "Easy? Let's test that: more weight, same reps." : "Easy, so the weight goes up.")
        }
    }
}

// MARK: - Session to session

public enum Progression {
    static let findingReps = 10

    public static func prescribe(_ target: SlotTarget, _ context: ProgressionContext) -> ExercisePrescription {
        let exercise = context.exercise
        let basis = exercise.loadBasis
        let bw = context.bodyweightKg
        // Deload sessions never anchor progression: the next block builds on the last real one.
        let work = context.history.filter { $0.kind.countsAsWork && $0.kind != .deload && $0.reps > 0 }
        let sessions = Dictionary(grouping: work) { Day($0.date) }
        let lastDay = sessions.keys.max()

        guard let lastDay, let last = sessions[lastDay] else {
            // Finding working weights.
            let reps = clamp(findingReps, target.repRange.lower, max(target.repRange.upper, target.repRange.lower))
            let sets = (0..<target.sets).map { _ in SetPrescription(kind: .findingWeight, loadKg: nil, targetReps: reps, targetRIR: 2) }
            return ExercisePrescription(exerciseID: exercise.id, sets: sets, mode: .findingWeight, e1rm: nil,
                                        reason: "Pick a weight you think you can do for \(reps), then rate it. The next set adjusts.")
        }

        let top = last.max { a, b in
            LoadMath.effective(a.loadKg, basis: basis, bodyweight: a.bodyweightKg) < LoadMath.effective(b.loadKg, basis: basis, bodyweight: b.bodyweightKg)
        }!
        let lastLoad = top.loadKg
        let topSets = last.filter { abs($0.loadKg - lastLoad) < 0.01 }
        // A miss that matters: the first top set fell short, or more than one did. A last set a
        // rep short through fatigue doesn't hold progression back.
        let missed = topSets.first?.rating == .red || topSets.filter { $0.rating == .red }.count >= 2
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
            let effective = LoadMath.effective(lastLoad, basis: basis, bodyweight: bw) * 0.88
            let load = LoadMath.logged(forEffective: effective, basis: basis, bodyweight: bw, increments: context.increments)
            let reps = max(target.repRange.lower, min(bestReps, target.repRange.middle))
            let count = max(1, Int((Double(target.sets) / 2).rounded(.up)))
            sets = (0..<count).map { _ in SetPrescription(kind: .deload, loadKg: load * context.loadFactor, targetReps: reps, targetRIR: rir) }
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
                load = LoadMath.logged(forEffective: OneRepMax.load(e1rm: e1rm, reps: reps, rir: rir) * context.loadFactor,
                                       basis: basis, bodyweight: bw, increments: context.increments)
            }
            let harder: (Double, Double) -> Bool = { a, b in basis == .assisted ? a < b : a > b }
            var cap = lastLoad
            let steps = missed ? 0 : context.phase.maxLoadStepsPerSession
            for _ in 0..<steps { cap = LoadMath.step(cap, 1, basis: basis, increments: context.increments) }
            if harder(load, cap) { load = cap }
            if context.loadFactor >= 1, !missed {
                // Don't slide back more than a step on a single off day.
                let floor = LoadMath.step(lastLoad, -1, basis: basis, increments: context.increments)
                if harder(floor, load) { load = floor }
            }
            if harder(load, lastLoad) {
                reason = "Your estimate says \(reps) reps with \(rir.formatted()) in reserve is a step up from last time."
            } else if load == lastLoad {
                reason = missed ? "Last time was a miss, so the same weight again." : "Same weight, aiming for \(reps) reps with \(rir.formatted()) left."
            } else {
                reason = context.loadFactor < 1 ? "Easing back in after time off." : "A little lighter to land the target reps."
            }
            sets = (0..<target.sets).map { _ in SetPrescription(kind: .working, loadKg: load, targetReps: reps, targetRIR: rir) }
        }

        // Rep-outs land in the assessment and at check-ins (the end of a deload, when fresh). A
        // check-in rep-out uses the last working weight so the reps stay where Epley is accurate.
        if target.repOut, var lastSet = sets.last {
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

    /// Ramp-up sets to a working load. In short sessions they double as the warm-up.
    public static func rampUp(to workingKg: Double, reps: Int, exercise: some ExerciseTraits, increments: any LoadIncrements,
                              bodyweightKg: Double?) -> [SetPrescription] {
        guard exercise.isCompound, exercise.loadBasis == .external || exercise.loadBasis == .perHand, workingKg > 0 else { return [] }
        let steps: [(Double, Int)] = workingKg >= 60 ? [(0.45, 8), (0.65, 5), (0.82, 3)] : [(0.5, 8), (0.75, 4)]
        var seen: Set<Double> = []
        return steps.compactMap { fraction, r in
            let load = increments.round(workingKg * fraction, down: true)
            guard load > 0, load < workingKg, !seen.contains(load) else { return nil }
            seen.insert(load)
            return SetPrescription(kind: .warmup, loadKg: load, targetReps: min(r, max(reps, 3)), targetRIR: 5)
        }
    }

    /// Reps in reserve to aim for across a loading block: start comfortable, finish close to
    /// failure. RP-style.
    public static func targetRIR(week: Int, of loadingWeeks: Int) -> Double {
        guard loadingWeeks > 1 else { return 2 }
        let t = Double(week) / Double(loadingWeeks - 1)
        return (3 - 2.5 * t).rounded(toNearestHalf: true)
    }
}

extension Double {
    func rounded(toNearestHalf: Bool) -> Double { (self * 2).rounded() / 2 }
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
    public static func detect(_ context: ProgressionContext, sets: Int, repRange: RepRange, today: Day,
                              phase: PhaseEffects, beatUp: Bool) -> StallReport? {
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

        // The prompt: the smallest overload from the last top set, at the bottom of the range.
        let work = context.history.filter { $0.kind.countsAsWork && $0.reps > 0 }
        var suggestion: SetPrescription?
        if let last = work.last {
            let reps = reading == .programming ? max(repRange.lower, min(5, repRange.upper)) : repRange.middle
            let load = reading == .programming
                ? LoadMath.step(last.loadKg, 1, basis: basis, increments: context.increments)
                : last.loadKg
            suggestion = SetPrescription(kind: .working, loadKg: load, targetReps: reps, targetRIR: 1)
        }
        return StallReport(exerciseID: context.exercise.id, weeks: days / 7, bestE1RM: best, since: bestDay, reading: reading,
                           suggestion: suggestion, suggestedSets: reading == .programming ? 3 : sets)
    }
}
