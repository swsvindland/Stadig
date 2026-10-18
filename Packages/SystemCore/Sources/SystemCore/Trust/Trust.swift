import Foundation

/// One piece of evidence about how well a rating matched reality.
public struct CalibrationObservation: Hashable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// A rep-out to failure right after the rated set: the reserve is known, near enough.
        case repOut
        /// A later, heavier set showed more was left than claimed.
        case laterSet
        /// A deliberate push to check a rating.
        case verification
    }

    public var day: Day
    public var exerciseID: String
    public var rating: SetRating
    /// Reps of reserve beyond the claim. Positive: more was left than claimed (sandbagging).
    /// Negative: less was left (overconfident). Zero: the rating was right.
    public var error: Double
    public var source: Source
    /// Machines give unambiguous failure; free-weight evidence counts for less.
    public var tier: SafetyTier

    public init(day: Day, exerciseID: String, rating: SetRating, error: Double, source: Source, tier: SafetyTier) {
        self.day = day
        self.exerciseID = exerciseID
        self.rating = rating
        self.error = error
        self.source = source
        self.tier = tier
    }

    /// 1 when the rating was right, falling quickly as the miss grows. Errors are already measured
    /// beyond a rep of tolerance.
    public var accuracy: Double { exp(-abs(error) / 1.5) }

    /// How much this observation counts. A contradiction says more than a confirmation: the "0–2
    /// left" band is often right by chance. Machines give unambiguous failure; free weights count less.
    var weight: Double { (error == 0 ? 0.5 : 1.5) * (tier == .safeToFail ? 1 : 0.5) }
}

/// How far a person's colour ratings can be believed. It starts from training experience and
/// moves only on evidence: rising as estimates prove accurate, falling with sandbagging or
/// overconfidence, for novices and veterans alike. Machines calibrate it; free-weight ratings use it.
public struct TrustState: Hashable, Codable, Sendable {
    public var prior: Double
    public var observations: [CalibrationObservation]

    /// Pseudo-observations the prior is worth.
    static let priorStrength = 4.0
    static let biasPriorStrength = 3.0
    static let recency = 0.93
    static let kept = 40

    public init(prior: Double, observations: [CalibrationObservation] = []) {
        self.prior = clamp(prior, 0.05, 0.95)
        self.observations = observations
    }

    public init(experience: TrainingExperience) {
        self.init(prior: experience.startingTrust)
    }

    private var weighted: [(observation: CalibrationObservation, weight: Double)] {
        let n = observations.count
        return observations.enumerated().map { i, o in (o, o.weight * pow(Self.recency, Double(n - 1 - i))) }
    }

    /// 0–1.
    public var score: Double {
        let list = weighted
        let total = list.map(\.weight).reduce(0, +)
        let accurate = list.map { $0.weight * $0.observation.accuracy }.reduce(0, +)
        return (Self.priorStrength * prior + accurate) / (Self.priorStrength + total)
    }

    /// Reps of reserve the person systematically under- (positive) or over- (negative) states.
    public var bias: Double {
        let list = weighted
        let total = list.map(\.weight).reduce(0, +)
        let sum = list.map { $0.weight * $0.observation.error }.reduce(0, +)
        return sum / (Self.biasPriorStrength + total)
    }

    /// The reserve a rating stands for once this person's bias is allowed for.
    public func reserve(for rating: SetRating) -> Double {
        switch rating {
        case .red: 0
        case .orange: clamp(rating.nominalRIR + bias, 0, 6)
        case .green: clamp(rating.nominalRIR + bias, 1, 8)
        }
    }

    public var evidenceCount: Int { observations.count }

    /// Low trust leans on objective performance and pushes to verify.
    public var isLow: Bool { score < 0.5 }

    /// Experienced lifters may shorten the lifting assessment once ratings have proven themselves.
    public var provenAccurate: Bool { score >= 0.7 && observations.count >= 6 }

    public var label: String {
        switch score {
        case ..<0.35: "Still learning your ratings"
        case ..<0.55: "Getting to know your ratings"
        case ..<0.75: "Your ratings are mostly on the mark"
        default: "Your ratings are reliable"
        }
    }

    /// The tendency in plain words, once there's evidence of one.
    public var tendency: String? {
        guard observations.count >= 3 else { return nil }
        if bias >= 1.2 { return "You tend to have more reps left than you think." }
        if bias <= -1.2 { return "You tend to have fewer reps left than you think." }
        return "Your ratings match what you can do."
    }

    public mutating func record(_ new: [CalibrationObservation]) {
        observations.append(contentsOf: new)
        if observations.count > Self.kept { observations.removeFirst(observations.count - Self.kept) }
    }
}

public enum Calibration {
    /// Reps of slack before a rating counts as wrong: Epley is only good to about a rep.
    static let tolerance = 1.0
    /// Reps of capacity a set loses to each earlier hard set in the same exercise.
    static let fatiguePerSet = 0.75

    /// Evidence from one exercise's sets in one session, in the order they were done.
    public static func observations(sets: [LoggedSet], exercise: some ExerciseTraits) -> [CalibrationObservation] {
        let work = sets.filter { $0.kind.countsAsWork && $0.reps > 0 }
        var result: [CalibrationObservation] = []
        for i in work.indices {
            let set = work[i]
            guard let rating = set.rating, rating != .red else { continue }
            let loadI = OneRepMax.effectiveLoad(set.loadKg, basis: exercise.loadBasis, bodyweightKg: set.bodyweightKg)
            guard loadI > 0 else { continue }
            var exact: Double?
            var lowerBound: Double?
            var source = CalibrationObservation.Source.laterSet
            for j in work.indices where j > i {
                let later = work[j]
                let loadJ = OneRepMax.effectiveLoad(later.loadKg, basis: exercise.loadBasis, bodyweightKg: later.bodyweightKg)
                guard loadJ >= loadI * 0.85, later.reps <= StrengthEstimator.maxUsefulReps else { continue }
                let capacityAtI = OneRepMax.repsToFailure(e1rm: OneRepMax.epley(loadJ, reps: later.reps), at: loadI)
                let fresher = fatiguePerSet * Double(j - i)
                if later.reachedFailure, j - i <= 2, abs(loadJ / loadI - 1) <= 0.12 {
                    exact = capacityAtI + fresher - Double(set.reps)
                    source = later.kind == .repOut ? .repOut : .verification
                    break
                }
                let bound = capacityAtI - Double(set.reps)
                if bound > (lowerBound ?? -.infinity) {
                    lowerBound = bound
                    source = loadJ > loadI ? .verification : .laterSet
                }
            }
            let claim = rating.claimedReserve
            var error: Double?
            if let exact {
                if exact < claim.lowerBound - tolerance {
                    error = exact - claim.lowerBound
                } else if exact > claim.upperBound + tolerance {
                    error = exact - claim.upperBound
                } else {
                    error = 0
                }
            } else if let lowerBound, lowerBound > claim.upperBound + tolerance {
                error = lowerBound - claim.upperBound
            }
            if let error {
                result.append(
                    CalibrationObservation(
                        day: Day(set.date), exerciseID: set.exerciseID, rating: rating,
                        error: error, source: source, tier: exercise.safetyTier))
            }
        }
        return result
    }
}

/// When a set may be taken to failure, by safety tier, trust and setup.
public enum FailurePolicy {
    /// Failure sets are costly: a cap per session.
    public static func capPerSession(experience: TrainingExperience, assessment: Bool) -> Int {
        assessment ? (experience == .novice ? 2 : 3) : (experience == .novice ? 1 : 2)
    }

    /// Whether this exercise may be repped out today.
    public static func allowsRepOut(
        _ exercise: some ExerciseTraits, trust: TrustState, experience: TrainingExperience,
        hasSafeties: Bool
    ) -> Bool {
        switch exercise.safetyTier {
        case .safeToFail:
            return true
        case .failWithSetup:
            // Deadlifts can fail safely but cost a lot; racked lifts need pins.
            let earned = experience == .experienced || trust.score >= 0.7
            let setup = exercise.pattern == .hinge || hasSafeties
            return earned && setup
        case .neverToFailure:
            return false
        }
    }

    /// Low-trust lifters stop a free-weight rep-out at form breakdown, not the bar stopping.
    public static func stopAtFormBreakdown(_ exercise: some ExerciseTraits, trust: TrustState) -> Bool {
        exercise.safetyTier != .safeToFail && (trust.isLow || exercise.pattern == .hinge)
    }

    /// Whether a session should include a rep-out to check ratings: always in the assessment and
    /// check-in weeks, and regularly while trust is low.
    public static func wantsRepOut(trust: TrustState, assessment: Bool, checkIn: Bool, sessionIndexInWeek: Int) -> Bool {
        if assessment || checkIn { return true }
        if trust.isLow { return sessionIndexInWeek % 2 == 0 }
        return false
    }
}
