import Foundation
import SystemCore

/// One phase in the plan, with its rate and length.
public struct PlannedPhase: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PhaseKind
    /// Fraction of body weight per week (−0.005 loses 0.5% a week).
    public var ratePerWeek: Double
    public var weeks: Int
    public var start: Day

    public init(id: UUID = UUID(), kind: PhaseKind, ratePerWeek: Double? = nil, weeks: Int, start: Day) {
        self.id = id
        self.kind = kind
        self.ratePerWeek = ratePerWeek ?? kind.typicalRate
        self.weeks = max(1, weeks)
        self.start = start
    }

    public var end: Day { start.adding(days: weeks * 7 - 1) }
    public var range: DayRange { DayRange(start, end) }

    public var summary: String {
        let pct = abs(ratePerWeek * 100)
        let rate = ratePerWeek == 0 ? "at maintenance" : "\(ratePerWeek < 0 ? "losing" : "gaining") \(pct.formatted(.number.precision(.fractionLength(0...2))))% a week"
        return "\(kind.label), \(weeks) weeks, \(rate)"
    }
}

/// The plan: the phase now, what follows, and the yearly arc. One recommendation with its "Why?".
public struct PhasePlan: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var phases: [PlannedPhase]
    public var headline: String
    public var reasons: [String]
    /// Said honestly when data is thin.
    public var confidence: String?
    /// The long horizon, in a sentence.
    public var arc: String
    public var created: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), phases: [PlannedPhase], headline: String, reasons: [String], confidence: String?, arc: String,
                created: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.phases = phases
        self.headline = headline
        self.reasons = reasons
        self.confidence = confidence
        self.arc = arc
        self.created = created
        self.updatedAt = updatedAt
    }

    public func phase(on day: Day) -> PlannedPhase? {
        phases.first { $0.range.contains(day) } ?? (day > (phases.last?.end ?? day) ? phases.last : nil)
    }

    public func next(after day: Day) -> PlannedPhase? { phases.first { $0.start > day } }
}

/// What the planner knows. Every input beyond intake and weight is optional: with less, the plan
/// is shorter and says so.
public struct PlannerInput: Sendable {
    public var profile: SharedProfile
    public var history: DietHistory
    public var today: Day
    public var weightKg: Double
    /// kg a week from the trend; negative is losing.
    public var weeklyChange: Double?
    public var maintenance: MaintenanceEstimate
    public var waistCm: Double?
    public var bodyFatPercent: Double?
    /// Lift Track's overall strength score and its direction, when it's installed.
    public var strengthScore: Double?
    public var strengthTrend: Trajectory?

    public init(profile: SharedProfile, history: DietHistory, today: Day, weightKg: Double, weeklyChange: Double?,
                maintenance: MaintenanceEstimate, waistCm: Double? = nil, bodyFatPercent: Double? = nil,
                strengthScore: Double? = nil, strengthTrend: Trajectory? = nil) {
        self.profile = profile
        self.history = history
        self.today = today
        self.weightKg = weightKg
        self.weeklyChange = weeklyChange
        self.maintenance = maintenance
        self.waistCm = waistCm
        self.bodyFatPercent = bodyFatPercent
        self.strengthScore = strengthScore
        self.strengthTrend = strengthTrend
    }

    public var waistToHeight: Double? {
        guard let waistCm, let h = profile.heightCm, h > 0 else { return nil }
        return waistCm / h
    }

    /// Leanness from the best signal available: waist-to-height first, then body fat.
    public var leanness: Leanness {
        if let wth = waistToHeight {
            switch wth {
            case ..<0.46: return .lean
            case ..<0.52: return .moderate
            case ..<0.57: return .higher
            default: return .high
            }
        }
        if let bf = bodyFatPercent {
            let female = profile.sex == .female
            switch bf {
            case ..<(female ? 22 : 14): return .lean
            case ..<(female ? 28 : 19): return .moderate
            case ..<(female ? 34 : 25): return .higher
            default: return .high
            }
        }
        return .unknown
    }

    public enum Leanness: String, Sendable { case lean, moderate, higher, high, unknown }
}

public enum PhasePlanner {
    /// The goal-driven recommendation. The person states outcomes; the data picks the phase.
    public static func recommend(_ input: PlannerInput) -> PhasePlan {
        let goals = Set(input.profile.goals)
        let wantsLean = goals.contains(.leaner)
        let wantsSize = goals.contains(.biggerAndStronger) || goals.contains(.stronger)
        let novice = input.profile.experience == .novice
        let lowMaintenance = input.maintenance.basis != .formula && input.maintenance.kcal < input.maintenance.formula - 250
        let thin = input.maintenance.spread >= 350
        var reasons: [String] = []
        var phases: [PlannedPhase] = []
        let start = input.today
        let headline: String

        func add(_ kind: PhaseKind, rate: Double? = nil, weeks: Int) {
            let begin = phases.last.map { $0.end.adding(days: 1) } ?? start
            phases.append(PlannedPhase(kind: kind, ratePerWeek: rate, weeks: thin ? min(weeks, 4) : weeks, start: begin))
        }

        let leanness = input.leanness
        if (input.history == .longCut || (input.history == .recentCut && lowMaintenance)), leanness != .high {
            add(.reverseDiet, rate: 0.001, weeks: 6)
            add(.maintenance, weeks: 2)
            add(wantsLean && leanness == .higher ? .miniCut : .leanBulk, weeks: wantsLean && leanness == .higher ? 5 : 12)
            headline = lowMaintenance
                ? "Your maintenance looks lower than expected after your cut, so calories rise gradually for \(phases[0].weeks) weeks, then a slow gain."
                : "After a long cut, calories rise gradually for \(phases[0].weeks) weeks before anything else."
            reasons.append("Months of dieting can push maintenance down; raising calories slowly brings it back while weight stays roughly stable.")
        } else {
            switch leanness {
            case .high:
                add(.cut, rate: -0.0075, weeks: 12)
                add(.dietBreak, weeks: 2)
                add(.cut, rate: -0.005, weeks: 8)
                headline = "A steady cut: about 0.75% of body weight a week, with a diet break after \(phases[0].weeks) weeks."
                reasons.append("Waist measurements point to plenty of room to lose fat, and strength holds best with a steady, not crash, deficit.")
            case .higher:
                if wantsSize && !wantsLean {
                    add(.miniCut, rate: -0.0075, weeks: 5)
                    add(.leanBulk, weeks: 12)
                    headline = "A short mini-cut first, so the gain that follows starts from a leaner place."
                } else {
                    add(.cut, rate: -0.005, weeks: 10)
                    add(.maintenance, weeks: 2)
                    headline = "A moderate cut: about 0.5% of body weight a week for \(phases[0].weeks) weeks."
                }
                reasons.append("Waist-to-height is above the healthy range, so losing some fat comes first.")
            case .moderate:
                if wantsLean {
                    add(.miniCut, rate: -0.0075, weeks: 5)
                    add(.maintenance, weeks: 4)
                    headline = "A focused mini-cut of about \(phases[0].weeks) weeks, then maintenance to hold it."
                    reasons.append("You're in a healthy range already, so a short, sharp cut gets you leaner without a long grind.")
                } else if novice || (input.strengthScore ?? 100) < 40 {
                    add(.recomp, weeks: 12)
                    headline = "A recomp: eat around maintenance with plenty of protein, and let training do the work."
                    reasons.append("Newer lifters can build muscle and lose a little fat at the same time near maintenance.")
                } else if wantsSize {
                    add(.leanBulk, rate: 0.0025, weeks: 16)
                    headline = "A slow lean bulk: about 0.25% of body weight a week."
                    reasons.append("You're lean enough to gain, and a slow surplus keeps most of the gain as muscle.")
                } else {
                    add(.maintenance, weeks: 8)
                    headline = "Maintenance: hold your weight and let training drive progress."
                }
            case .lean:
                if wantsSize || !wantsLean {
                    add(.leanBulk, rate: novice ? 0.005 : 0.0025, weeks: 16)
                    headline = "A lean bulk: about \(novice ? "0.5" : "0.25")% of body weight a week."
                    reasons.append("You're lean, so the most useful thing is to gain slowly while training hard.")
                } else {
                    add(.maintenance, weeks: 8)
                    headline = "Maintenance: you're already lean."
                }
            case .unknown:
                add(wantsLean ? .cut : (wantsSize ? .leanBulk : .maintenance), rate: wantsLean ? -0.005 : (wantsSize ? 0.0025 : 0), weeks: 4)
                headline = wantsLean ? "A gentle cut for 4 weeks while we learn more." : (wantsSize ? "A slow gain for 4 weeks while we learn more." : "Maintenance for 4 weeks while we learn more.")
                reasons.append("A waist measurement (in Lift Track or here) would make this recommendation much sharper.")
            }
        }

        if let change = input.weeklyChange, abs(change) > 0.1 {
            let pct = change / input.weightKg * 100
            reasons.append("Over the assessment you've been \(change < 0 ? "losing" : "gaining") about \(abs(pct).formatted(.number.precision(.fractionLength(1))))% a week while eating as usual.")
        }
        reasons.append("Maintenance is about \(Int(input.maintenance.kcal)) kcal (\(Int(input.maintenance.low))–\(Int(input.maintenance.high))). Targets adjust each week as the estimate sharpens.")
        if input.strengthScore != nil, phases.first?.kind.energy == .deficit {
            reasons.append("Lift Track holds volume and protects heavy lifts during the cut; a strength drop ends it early.")
        }
        let confidence: String? = thin ? "Early read: the first phase is kept short and conservative until the data firms up." : nil
        let arc: String = switch phases.first?.kind.energy {
        case .deficit: "Get leaner first, then build with slow gains, with a short cut later in the year if needed."
        case .surplus: "Build through the winter months with slow gains, then a short cut, then maintenance over summer."
        default: "Hold steady, then alternate slow gains and short cuts while you keep getting stronger."
        }
        return PhasePlan(phases: phases, headline: headline, reasons: reasons, confidence: confidence, arc: arc)
    }

    /// Changes worth making at a block boundary, by rule. Nil keeps the plan.
    public static func review(_ plan: PhasePlan, input: PlannerInput) -> PhasePlan? {
        guard let current = plan.phase(on: input.today) else { return recommend(input) }
        var plan = plan
        var reason: String?
        let rateNow = input.weeklyChange.map { $0 / input.weightKg }

        switch current.kind.energy {
        case .deficit:
            if input.strengthTrend == .regressing {
                reason = "Strength is dropping during the cut, so it ends early with a diet break."
            } else if input.leanness == .lean {
                reason = "You've reached a lean range, so the cut ends here."
            }
            if let reason {
                let index = plan.phases.firstIndex { $0.id == current.id }!
                plan.phases[index].weeks = max(1, current.start.days(until: input.today) / 7)
                let breakStart = plan.phases[index].end.adding(days: 1)
                plan.phases = Array(plan.phases.prefix(index + 1)) + [PlannedPhase(kind: .dietBreak, weeks: 2, start: breakStart)]
                plan.reasons.insert(reason, at: 0)
                plan.headline = reason
            }
        case .surplus:
            if let rate = rateNow, rate > current.ratePerWeek * 1.6, rate > 0.003 {
                let index = plan.phases.firstIndex { $0.id == current.id }!
                plan.phases[index].ratePerWeek = current.ratePerWeek * 0.7
                reason = "Weight is rising faster than planned, so the surplus comes down a little."
                plan.reasons.insert(reason!, at: 0)
                plan.headline = reason!
            } else if input.leanness == .higher || input.leanness == .high {
                reason = "Waist has grown past the target range, so a short mini-cut comes next."
                let index = plan.phases.firstIndex { $0.id == current.id }!
                plan.phases[index].weeks = max(1, current.start.days(until: input.today) / 7)
                plan.phases = Array(plan.phases.prefix(index + 1)) + [PlannedPhase(kind: .miniCut, ratePerWeek: -0.0075, weeks: 5,
                                                                                    start: plan.phases[index].end.adding(days: 1))]
                plan.reasons.insert(reason!, at: 0)
                plan.headline = reason!
            }
        case .maintenance:
            break
        }
        // Past the end of the plan: plan again.
        if input.today > (plan.phases.last?.end ?? input.today) { return recommend(input) }
        guard reason != nil else { return nil }
        plan.updatedAt = Date()
        return plan
    }
}
