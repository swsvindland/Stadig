import Foundation

/// What a hard set takes out of the next one at the same weight. Reps fall from set to set even
/// when the weight is right: more after a set taken close to failure, after a short rest, and on the
/// big lifts. Rest-interval studies of squats and bench at about an 8RM, every set to failure, put
/// the second set near 70% of the first after a minute's rest, 75–80% after two and 85% after
/// five; a set stopped with reps in hand costs less. Fewer reps at the same weight still build muscle,
/// so the sets after a good one keep the weight and aim a little lower, and reps that fall the way
/// fatigue says they should are never a miss.
public enum SetFatigue {
    /// The rest assumed when a set's own wasn't recorded.
    public static let typicalRest = 150

    /// How hard an exercise is on the sets after it: squats and deadlifts lose more than a machine
    /// press or a curl.
    public static func scale(of exercise: some ExerciseTraits) -> Double {
        0.6 + 0.5 * exercise.fatigue.systemic
    }

    /// The share of capacity (reps to failure at the weight) the next set loses, after a set that
    /// left `reserve` reps in hand and `restSeconds` of rest.
    public static func loss(reserve: Double, restSeconds: Int, scale: Double) -> Double {
        // Most of it comes back in the first few minutes; some lasts the session.
        let atFailure = 0.12 + 0.33 * exp(-Double(max(0, restSeconds)) / 110)
        // Each rep left in hand spares some of it, down to two fifths.
        let proximity = max(0.4, 1 - 0.15 * max(0, reserve))
        return min(0.6, atFailure * proximity * scale)
    }

    public static func loss(reserve: Double, restSeconds: Int, exercise: some ExerciseTraits) -> Double {
        loss(reserve: reserve, restSeconds: restSeconds, scale: scale(of: exercise))
    }

    /// Reps to failure left for the next set at the same weight.
    public static func capacity(after reps: Int, reserve: Double, restSeconds: Int, exercise: some ExerciseTraits) -> Double {
        (Double(max(0, reps)) + max(0, reserve)) * (1 - loss(reserve: reserve, restSeconds: restSeconds, exercise: exercise))
    }

    /// The rest a logged set had. Its time is counted from the set before's log, so it includes
    /// doing the set itself, about three seconds a rep.
    public static func rest(before set: LoggedSet) -> Int {
        guard let seconds = set.restBeforeSeconds else { return typicalRest }
        return max(0, seconds - 3 * set.reps)
    }

    /// The 1RM a capacity at a weight stands for: Epley, with the reps not yet whole.
    static func e1rm(load: Double, capacity: Double) -> Double {
        capacity <= 1 ? load : load * (1 + capacity / 30)
    }
}

/// How a set's target was worked out from the set before it at the same weight, kept so a rest cut
/// short (skipped, or ended by a recovered heart rate) can work it out again for the rest taken.
public struct FatigueBasis: Codable, Hashable, Sendable {
    /// Reps to failure the set before had in it at this weight, and the reps it left in hand.
    public var capacity: Double
    public var reserve: Double
    /// Reps the target leaves in hand.
    public var aim: Double
    /// The exercise's ``SetFatigue/scale(of:)``.
    public var scale: Double
    /// The rest the target assumes.
    public var restSeconds: Int

    public init(capacity: Double, reserve: Double, aim: Double, scale: Double, restSeconds: Int) {
        self.capacity = capacity
        self.reserve = reserve
        self.aim = aim
        self.scale = scale
        self.restSeconds = restSeconds
    }

    /// The reps to aim for after this rest (the assumed one by default).
    public func reps(restSeconds rest: Int? = nil) -> Int {
        let left = capacity * (1 - SetFatigue.loss(reserve: reserve, restSeconds: rest ?? restSeconds, scale: scale))
        return max(1, Int((left - aim).rounded()))
    }

    /// The set after this one, if this one comes out as aimed.
    public var following: FatigueBasis {
        FatigueBasis(capacity: Double(reps()) + aim, reserve: aim, aim: aim, scale: scale, restSeconds: restSeconds)
    }
}
