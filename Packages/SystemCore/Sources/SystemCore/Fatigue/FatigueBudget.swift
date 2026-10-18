import Foundation

/// How the person felt after a session: the quick feedback that feeds the Fatigue Budget.
public struct SessionFeedback: Hashable, Codable, Sendable {
    /// 0 none, 1 a little, 2 sore, 3 very sore — how sore they were coming in.
    public var soreness: Int
    public var jointPain: [Joint]
    /// 1 drained … 5 great.
    public var energy: Int

    public init(soreness: Int = 1, jointPain: [Joint] = [], energy: Int = 3) {
        self.soreness = clamp(soreness, 0, 3)
        self.jointPain = jointPain
        self.energy = clamp(energy, 1, 5)
    }

    /// Whether this session left them beat up.
    public var beatUp: Bool { soreness >= 3 || !jointPain.isEmpty || energy <= 1 || (soreness >= 2 && energy <= 2) }
}

/// One night and morning: the recovery signals from the watch.
public struct RecoveryDay: Hashable, Codable, Sendable {
    public var day: Day
    public var sleepHours: Double?
    public var hrv: Double?
    public var restingHeartRate: Double?

    public init(day: Day, sleepHours: Double? = nil, hrv: Double? = nil, restingHeartRate: Double? = nil) {
        self.day = day
        self.sleepHours = sleepHours
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
    }
}

public struct FatigueEvent: Hashable, Codable, Sendable {
    public var day: Day
    public var load: FatigueLoad
    public var feedback: SessionFeedback?

    public init(day: Day, load: FatigueLoad, feedback: SessionFeedback? = nil) {
        self.day = day
        self.load = load
        self.feedback = feedback
    }
}

public enum FatigueStatus: String, Codable, Sendable, Comparable {
    case fresh, productive, strained, overreached

    public static func < (a: FatigueStatus, b: FatigueStatus) -> Bool {
        [FatigueStatus.fresh, .productive, .strained, .overreached].firstIndex(of: a)! < [FatigueStatus.fresh, .productive, .strained, .overreached]
            .firstIndex(of: b)!
    }
}

public enum FatigueAction: String, Codable, Sendable {
    case none
    /// Beat up and stalled: spend less systemic budget before cutting total work.
    case reduceSystemic
    /// Signals have stacked up: deload now rather than wait for the calendar.
    case deloadEarly
}

/// The hidden stat. Never shown as a level; inferred from training load, feedback, recovery and
/// performance, and used to plan.
public struct FatigueAssessment: Hashable, Codable, Sendable {
    public var status: FatigueStatus
    /// Acute (7-day) over chronic (28-day) systemic load.
    public var loadRatio: Double
    public var acute: Double
    public var chronic: Double
    /// Plain-language signals that moved it.
    public var signals: [String]
    public var action: FatigueAction
    /// Multiplies the next block's systemic budget.
    public var budgetFactor: Double

    public init(
        status: FatigueStatus, loadRatio: Double, acute: Double, chronic: Double, signals: [String], action: FatigueAction,
        budgetFactor: Double
    ) {
        self.status = status
        self.loadRatio = loadRatio
        self.acute = acute
        self.chronic = chronic
        self.signals = signals
        self.action = action
        self.budgetFactor = budgetFactor
    }
}

public enum FatigueBudget {
    /// The fatigue a set adds: systemic and local costs, more for sets near or at failure.
    public static func cost(of set: LoggedSet, exercise: some ExerciseTraits) -> FatigueLoad {
        guard set.kind.countsAsWork else { return .zero }
        let reserve = set.rating?.nominalRIR ?? 2
        var intensity: Double =
            switch reserve {
            case ..<0.5: 1.15
            case ..<1.5: 1.05
            case ..<2.5: 1.0
            default: 0.85
            }
        if set.reachedFailure { intensity *= exercise.fatigue.failureMultiplier }
        if set.kind == .deload { intensity *= 0.6 }
        var local: [Muscle.Region: Double] = [:]
        for share in exercise.muscles { local[share.muscle.region, default: 0] += share.weight * exercise.fatigue.local * intensity }
        return FatigueLoad(systemic: exercise.fatigue.systemic * intensity, local: local)
    }

    /// Conditioning: minutes at a zone.
    public static func conditioningCost(minutes: Int, zone: Int) -> FatigueLoad {
        let perMinute: [Int: Double] = [1: 0.02, 2: 0.035, 3: 0.06, 4: 0.1, 5: 0.15]
        let systemic = Double(minutes) * (perMinute[clamp(zone, 1, 5)] ?? 0.05)
        return FatigueLoad(systemic: systemic, local: [.legs: systemic * 0.8])
    }

    /// Infers the budget's state from the last four weeks.
    public static func assess(
        events: [FatigueEvent], recovery: [RecoveryDay], lifeStress: [Day: Double],
        performanceTrend: Double?, today: Day
    ) -> FatigueAssessment {
        let start = today.adding(days: -27)
        var daily = [Double](repeating: 0, count: 28)
        for event in events where event.day >= start && event.day <= today {
            daily[start.days(until: event.day)] += event.load.systemic
        }
        for (day, stress) in lifeStress where day >= start && day <= today { daily[start.days(until: day)] += stress * 2 }
        let acute = daily.suffix(7).reduce(0, +) / 7
        let chronic = daily.reduce(0, +) / 28
        let ratio = chronic > 0.01 ? acute / chronic : (acute > 0 ? 1.5 : 1)

        var signals: [String] = []
        var points = 0.0

        if ratio > 1.5, chronic > 0.5 {
            signals.append("Training load jumped this week.")
            points += 1
        }
        let recent = events.filter { $0.day > today.adding(days: -14) }.compactMap(\.feedback)
        let beatUpCount = recent.filter(\.beatUp).count
        let beatUp = recent.count >= 2 && Double(beatUpCount) / Double(recent.count) >= 0.5
        if beatUp {
            signals.append("You've felt beat up after most recent sessions.")
            points += 2
        }
        let pain = Set(recent.flatMap(\.jointPain))
        if !pain.isEmpty {
            signals.append("Joint pain logged: \(pain.map(\.label).sorted().joined(separator: ", ")).")
            points += 0.5
        }
        let week = recovery.filter { $0.day > today.adding(days: -7) }
        let baseline = recovery.filter { $0.day > today.adding(days: -35) && $0.day <= today.adding(days: -7) }
        if let sleep = week.compactMap(\.sleepHours).mean, sleep < 6.5 {
            signals.append(String(format: "Sleep has averaged %.1f hours this week.", sleep))
            points += sleep < 5.5 ? 1.5 : 1
        }
        if let hrv = week.compactMap(\.hrv).mean, let base = baseline.compactMap(\.hrv).mean, base > 0, hrv < base * 0.88 {
            signals.append("HRV is below your usual.")
            points += 1
        }
        if let rhr = week.compactMap(\.restingHeartRate).mean, let base = baseline.compactMap(\.restingHeartRate).mean, rhr > base + 4 {
            signals.append("Resting heart rate is up.")
            points += 1
        }
        if let trend = performanceTrend, trend < -0.01 {
            signals.append("Performance is trending down.")
            points += 1.5
        }
        if lifeStress.contains(where: { $0.key > today.adding(days: -7) }) {
            signals.append("Work or travel stress this week.")
            points += 0.5
        }

        let status: FatigueStatus =
            switch points {
            case ..<0.5: ratio < 0.8 ? .fresh : .productive
            case ..<2: .productive
            case ..<3.5: .strained
            default: .overreached
            }
        let stalled = (performanceTrend ?? 0) <= 0.002
        let action: FatigueAction
        if status == .overreached || (status == .strained && (performanceTrend ?? 0) < -0.01) {
            action = .deloadEarly
        } else if (beatUp || status >= .strained) && stalled {
            action = .reduceSystemic
        } else {
            action = .none
        }
        let factor: Double =
            switch status {
            case .fresh: 1.05
            case .productive: 1
            case .strained: 0.85
            case .overreached: 0.7
            }
        return FatigueAssessment(
            status: status, loadRatio: ratio, acute: acute, chronic: chronic, signals: signals,
            action: action, budgetFactor: factor)
    }

    /// Weekly systemic budget for planning, in hard-set units of a heavy compound.
    public static func weeklySystemicBudget(
        experience: TrainingExperience, daysPerWeek: Int, phase: PhaseEffects,
        assessment: FatigueAssessment?, outside: FatigueLoad
    ) -> Double {
        // About what a full session of compounds and accessories costs.
        let perDay: Double =
            switch experience {
            case .novice: 8.5
            case .intermediate: 9.5
            case .experienced: 10.5
            }
        let base = perDay * Double(daysPerWeek) * phase.volumeTolerance * (assessment?.budgetFactor ?? 1)
        // Outside training spends from the same budget, but never all of it.
        return max(base * 0.45, base - outside.systemic * 0.8)
    }

    /// Relative change in estimated strength across lifts over the last few weeks, per week.
    public static func performanceTrend(_ series: [[(day: Day, e1rm: Double)]], today: Day) -> Double? {
        let slopes: [Double] = series.compactMap { points in
            let recent = points.filter { $0.day > today.adding(days: -35) }
            guard recent.count >= 3, let first = recent.first, first.e1rm > 0 else { return nil }
            let weeks = recent.map { Double(first.day.days(until: $0.day)) / 7 }
            return leastSquaresSlope(x: weeks, y: recent.map { $0.e1rm / first.e1rm })
        }
        return slopes.mean
    }
}
