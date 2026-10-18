import Foundation

/// The three-tap rating after every set. There is no numeric RPE: people misjudge effort anyway,
/// so true failure tests calibrate how far each person's colours can be believed.
public enum SetRating: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Easy: three or more reps left.
    case green
    /// Just right: about zero to two reps left.
    case orange
    /// Missed the target reps.
    case red

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .green: "Easy"
        case .orange: "Just right"
        case .red: "Missed"
        }
    }

    public var detail: String {
        switch self {
        case .green: "3+ reps left"
        case .orange: "0–2 reps left"
        case .red: "Fell short"
        }
    }

    /// An SF Symbol name, so the rating never relies on colour alone.
    public var symbol: String {
        switch self {
        case .green: "chevron.up.circle.fill"
        case .orange: "checkmark.circle.fill"
        case .red: "xmark.circle.fill"
        }
    }

    /// Reps in reserve the rating stands for, before any calibration.
    public var nominalRIR: Double {
        switch self {
        case .green: 3
        case .orange: 1
        case .red: 0
        }
    }

    /// The reserve the rating claims, in reps. Green is open-ended.
    public var claimedReserve: ClosedRange<Double> {
        switch self {
        case .green: 3...30
        case .orange: 0...2
        case .red: 0...0
        }
    }
}

public enum SetKind: String, Codable, Sendable, CaseIterable {
    /// Ramp-up sets; they double as the warm-up in short sessions and never count as work.
    case warmup
    case working
    /// Week one: "pick a weight you think you can do for 10", rated, adjusted until it's right.
    case findingWeight
    /// A controlled rep-out to genuine (or, for free weights, technical) failure.
    case repOut
    /// The reduced sets of a deload week.
    case deload

    public var countsAsWork: Bool { self != .warmup }

    public var label: String {
        switch self {
        case .warmup: "Warm-up"
        case .working: "Working"
        case .findingWeight: "Finding weight"
        case .repOut: "Rep-out"
        case .deload: "Deload"
        }
    }
}

/// One set as it happened. Loads are in kg and mean what the exercise's ``LoadBasis`` says.
public struct LoggedSet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseID: String
    public var date: Date
    public var kind: SetKind
    public var loadKg: Double
    public var reps: Int
    public var targetReps: Int?
    public var rating: SetRating?
    /// Body weight when it matters (bodyweight-plus and assisted exercises).
    public var bodyweightKg: Double?
    /// A rep-out stopped at form breakdown rather than the bar stopping.
    public var stoppedAtFormBreakdown: Bool
    /// Seconds rested before this set.
    public var restBeforeSeconds: Int?
    /// Heart rate at the end of the set, and how far it fell in the following minute.
    public var heartRatePeak: Double?
    public var heartRateDrop60: Double?
    /// Duration for timed work (holds, carries, conditioning intervals).
    public var seconds: Int?

    public init(
        id: UUID = UUID(), exerciseID: String, date: Date = Date(), kind: SetKind = .working, loadKg: Double,
        reps: Int, targetReps: Int? = nil, rating: SetRating? = nil, bodyweightKg: Double? = nil,
        stoppedAtFormBreakdown: Bool = false, restBeforeSeconds: Int? = nil, heartRatePeak: Double? = nil,
        heartRateDrop60: Double? = nil, seconds: Int? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.date = date
        self.kind = kind
        self.loadKg = loadKg
        self.reps = reps
        self.targetReps = targetReps
        self.rating = rating
        self.bodyweightKg = bodyweightKg
        self.stoppedAtFormBreakdown = stoppedAtFormBreakdown
        self.restBeforeSeconds = restBeforeSeconds
        self.heartRatePeak = heartRatePeak
        self.heartRateDrop60 = heartRateDrop60
        self.seconds = seconds
    }

    /// Whether the set reached failure: a rep-out, or a miss.
    public var reachedFailure: Bool { kind == .repOut || rating == .red }
}

/// The loads a gym can actually make for an exercise. The core never assumes plates or stacks;
/// the app passes its gym in.
public protocol LoadIncrements: Sendable {
    /// The nearest makeable load at or below (`down`) or nearest to the target, in kg.
    func round(_ kg: Double, down: Bool) -> Double
    /// The next makeable load above (`direction` > 0) or below the current one, in kg.
    func step(_ kg: Double, direction: Int) -> Double
}

/// Fixed steps from zero: enough for tests and for equipment with an even stack.
public struct FixedIncrements: LoadIncrements {
    public var stepKg: Double
    public var maxKg: Double?

    public init(stepKg: Double, maxKg: Double? = nil) {
        self.stepKg = stepKg
        self.maxKg = maxKg
    }

    public func round(_ kg: Double, down: Bool) -> Double {
        guard kg > 0 else { return 0 }
        let steps = kg / stepKg
        var value = (down ? (steps + 1e-9).rounded(.down) : steps.rounded()) * stepKg
        if let maxKg { value = min(value, maxKg) }
        return max(down ? 0 : stepKg, value)
    }

    public func step(_ kg: Double, direction: Int) -> Double {
        let current = round(kg, down: false)
        var next = current + Double(direction.signum()) * stepKg
        if let maxKg { next = min(next, maxKg) }
        return max(0, next)
    }
}

/// Estimated one-rep maxes.
public enum OneRepMax {
    /// Epley, counting reps in reserve as reps that could have been done. Beyond about 12 reps to
    /// failure the estimate grows loose; callers treat it as a trend, not a number to test.
    public static func epley(_ loadKg: Double, reps: Int, rir: Double = 0) -> Double {
        guard loadKg > 0, reps > 0 else { return 0 }
        let toFailure = Double(reps) + max(0, rir)
        return toFailure <= 1 ? loadKg : loadKg * (1 + toFailure / 30)
    }

    /// Reps doable to failure at a load, the inverse of ``epley(_:reps:rir:)``.
    public static func repsToFailure(e1rm: Double, at loadKg: Double) -> Double {
        guard loadKg > 0, e1rm > 0 else { return 0 }
        if loadKg >= e1rm { return loadKg > e1rm * 1.0001 ? 0 : 1 }
        return max(1, 30 * (e1rm / loadKg - 1))
    }

    /// The load for a number of reps with some left in reserve.
    public static func load(e1rm: Double, reps: Int, rir: Double) -> Double {
        let toFailure = Double(reps) + max(0, rir)
        return toFailure <= 1 ? e1rm : e1rm / (1 + toFailure / 30)
    }

    /// The load that counts for strength: the bar for external loads, the body plus or minus the
    /// added load for bodyweight and assisted work. Dumbbells count per hand.
    public static func effectiveLoad(_ loadKg: Double, basis: LoadBasis, bodyweightKg: Double?) -> Double {
        switch basis {
        case .external, .perHand: return loadKg
        case .bodyweightPlus: return (bodyweightKg ?? 0) + loadKg
        case .assisted: return max(0, (bodyweightKg ?? 0) - loadKg)
        case .none: return 0
        }
    }

    /// The logged load that produces an effective load (inverse of ``effectiveLoad``).
    public static func loggedLoad(forEffective effective: Double, basis: LoadBasis, bodyweightKg: Double?) -> Double {
        switch basis {
        case .external, .perHand, .none: return effective
        case .bodyweightPlus: return max(0, effective - (bodyweightKg ?? 0))
        case .assisted: return max(0, (bodyweightKg ?? 0) - effective)
        }
    }
}
