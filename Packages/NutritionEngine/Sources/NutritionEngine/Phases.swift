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
    /// The last day, when a review ended the phase partway through a week. Nil for plans saved
    /// before it existed, and for phases that ran whole weeks.
    public var endedEarly: Day?

    public init(id: UUID = UUID(), kind: PhaseKind, ratePerWeek: Double? = nil, weeks: Int, start: Day, endedEarly: Day? = nil) {
        self.id = id
        self.kind = kind
        self.ratePerWeek = ratePerWeek ?? kind.typicalRate
        self.weeks = max(1, weeks)
        self.start = start
        self.endedEarly = endedEarly
    }

    public var end: Day { endedEarly ?? start.adding(days: weeks * 7 - 1) }
    public var range: DayRange { DayRange(start, end) }

    public var summary: String {
        let pct = abs(ratePerWeek * 100)
        let rate =
            ratePerWeek == 0
            ? "at maintenance" : "\(ratePerWeek < 0 ? "losing" : "gaining") \(pct.formatted(.number.precision(.fractionLength(0...2))))% a week"
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

    public init(
        id: UUID = UUID(), phases: [PlannedPhase], headline: String, reasons: [String], confidence: String?, arc: String,
        created: Date = Date(), updatedAt: Date = Date()
    ) {
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
    /// Lift Track's read on whether fat loss or building would do more for proportions.
    public var physique: PhysiqueDirection?

    public init(
        profile: SharedProfile, history: DietHistory, today: Day, weightKg: Double, weeklyChange: Double?,
        maintenance: MaintenanceEstimate, waistCm: Double? = nil, bodyFatPercent: Double? = nil,
        strengthScore: Double? = nil, strengthTrend: Trajectory? = nil, physique: PhysiqueDirection? = nil
    ) {
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
        self.physique = physique
    }

    public var waistToHeight: Double? {
        guard let waistCm, let h = profile.heightCm, h > 0 else { return nil }
        return waistCm / h
    }

    /// Leanness from the best signal available: waist-to-height first, then body fat. At Lift
    /// Track's lean floor (10% body fat for men, 20% for women) it's lean whatever the waist says,
    /// so nothing plans a cut below it.
    public var leanness: Leanness {
        if physique?.atLeanFloor == true { return .lean }
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
        // Lift Track's proportions count only for the goals they serve.
        let proportions = goals.isDisjoint(with: [.leaner, .biggerAndStronger, .healthier]) ? nil : input.physique
        // The waist is what holds the ratios back: lose fat before any gain.
        let fatFirst = (proportions.map { $0.fatLoss >= 0.3 && !$0.atLeanFloor } ?? false) && leanness != .lean && leanness != .unknown
        // Lean, with muscle the ratios still need.
        let buildGap = (proportions.map { $0.build >= 0.3 } ?? false) && leanness == .lean
        let room = proportions?.ffmiBand
        func percent(_ rate: Double) -> String { (rate * 100).formatted(.number.precision(.fractionLength(0...2))) }

        if input.history == .longCut || (input.history == .recentCut && lowMaintenance), leanness != .high {
            add(.reverseDiet, rate: 0.001, weeks: 6)
            add(.maintenance, weeks: 2)
            let cutNext = fatFirst || (wantsLean && leanness == .higher)
            add(cutNext ? .miniCut : .leanBulk, weeks: cutNext ? 5 : 12)
            headline =
                lowMaintenance
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
                } else if fatFirst {
                    add(.miniCut, rate: -0.0075, weeks: 5)
                    if wantsSize {
                        add(.leanBulk, rate: 0.0025, weeks: 16)
                        headline = "A focused mini-cut of about \(phases[0].weeks) weeks first, then a slow lean bulk from a leaner start."
                    } else {
                        add(.maintenance, weeks: 4)
                        headline = "A focused mini-cut of about \(phases[0].weeks) weeks, then maintenance to hold it."
                    }
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
                if room == .nearCeiling, !wantsSize {
                    add(buildGap ? .recomp : .maintenance, weeks: buildGap ? 12 : 8)
                    headline =
                        buildGap
                        ? "A recomp: you're lean and near your natural ceiling, so build at maintenance."
                        : "Maintenance: you're lean and near your natural ceiling."
                    reasons.append("Near the natural ceiling a surplus mostly adds fat, so calories stay at maintenance.")
                } else if wantsSize || !wantsLean {
                    // Less room to build, a smaller surplus.
                    let rate = room == .someRoom || room == .nearCeiling ? 0.0015 : (novice ? 0.005 : 0.0025)
                    add(.leanBulk, rate: rate, weeks: 16)
                    headline = "A lean bulk: about \(percent(rate))% of body weight a week."
                    reasons.append("You're lean, so the most useful thing is to gain slowly while training hard.")
                } else if buildGap {
                    add(.recomp, weeks: 12)
                    headline = "A recomp: you're lean, so the muscle your proportions need is built at maintenance."
                    reasons.append("Eating at maintenance with plenty of protein builds muscle without giving up the leanness you're after.")
                } else {
                    add(.maintenance, weeks: 8)
                    headline = "Maintenance: you're already lean."
                }
            case .unknown:
                add(wantsLean ? .cut : (wantsSize ? .leanBulk : .maintenance), rate: wantsLean ? -0.005 : (wantsSize ? 0.0025 : 0), weeks: 4)
                headline =
                    wantsLean
                    ? "A gentle cut for 4 weeks while we learn more."
                    : (wantsSize ? "A slow gain for 4 weeks while we learn more." : "Maintenance for 4 weeks while we learn more.")
                reasons.append("A waist measurement (in Lift Track or here) would make this recommendation much sharper.")
            }
        }

        if fatFirst, let proportions {
            if proportions.fatLossReasons.isEmpty {
                reasons.append(
                    "Lift Track's measurements show the waist holds your proportions back more than muscle does, so fat loss comes before any gain.")
            } else {
                let named = proportions.fatLossReasons.prefix(2)
                reasons.append(contentsOf: named)
                reasons.append(
                    "At a leaner waist \(named.count == 1 ? "it reaches its target" : "these reach their targets"), so fat loss comes before any gain."
                )
            }
        }
        if buildGap, let proportions, phases.first.map({ $0.kind == .leanBulk || $0.kind == .recomp }) == true {
            reasons.append(contentsOf: proportions.buildReasons.prefix(2))
            if let ffmi = proportions.normalizedFFMI, let room {
                let ffmiText = ffmi.formatted(.number.precision(.fractionLength(1)))
                let roomText =
                    switch room {
                    case .lotsOfRoom: "An FFMI of \(ffmiText) leaves lots of room to build."
                    case .someRoom: "An FFMI of \(ffmiText) leaves some room to build, so the surplus is kept small."
                    case .nearCeiling: "An FFMI of \(ffmiText) is near the natural ceiling, so gains come slowly."
                    }
                reasons.append(roomText)
            }
        }
        if input.physique?.atLeanFloor == true, wantsLean {
            reasons.append("Body fat is already at the lean floor, so no cut is planned below it.")
        }
        if let change = input.weeklyChange, abs(change) > 0.1 {
            let pct = change / input.weightKg * 100
            reasons.append(
                "Over the assessment you've been \(change < 0 ? "losing" : "gaining") about \(abs(pct).formatted(.number.precision(.fractionLength(1))))% a week while eating as usual."
            )
        }
        reasons.append(
            "Maintenance is about \(Int(input.maintenance.kcal)) kcal (\(Int(input.maintenance.low))–\(Int(input.maintenance.high))). Targets adjust each week as the estimate sharpens."
        )
        if input.strengthScore != nil, phases.first?.kind.energy == .deficit {
            reasons.append("Lift Track holds volume and protects heavy lifts during the cut; a strength drop ends it early.")
        }
        let confidence: String? = thin ? "Early read: the first phase is kept short and conservative until the data firms up." : nil
        let arc: String =
            switch phases.first?.kind.energy {
            case .deficit: "Get leaner first, then build with slow gains, with a short cut later in the year if needed."
            case .surplus: "Build through the winter months with slow gains, then a short cut, then maintenance over summer."
            default: "Hold steady, then alternate slow gains and short cuts while you keep getting stronger."
            }
        return PhasePlan(phases: phases, headline: headline, reasons: reasons, confidence: confidence, arc: arc)
    }

    /// Changes worth making at a block boundary, by rule. Nil keeps the plan.
    public static func review(_ plan: PhasePlan, input: PlannerInput) -> PhasePlan? {
        // Before the plan, or past its end: plan again.
        guard let current = plan.phase(on: input.today), input.today <= current.end,
            let index = plan.phases.firstIndex(where: { $0.id == current.id })
        else { return recommend(input) }
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
            if reason != nil { endEarly(&plan, at: index, today: input.today, then: PlannedPhase(kind: .dietBreak, weeks: 2, start: input.today)) }
        case .surplus:
            if let rate = rateNow, rate > current.ratePerWeek * 1.6, rate > 0.003 {
                plan.phases[index].ratePerWeek = current.ratePerWeek * 0.7
                reason = "Weight is rising faster than planned, so the surplus comes down a little."
            } else if input.leanness == .higher || input.leanness == .high {
                reason = "Waist has grown past the target range, so a short mini-cut comes next."
                endEarly(
                    &plan, at: index, today: input.today,
                    then: PlannedPhase(kind: .miniCut, ratePerWeek: -0.0075, weeks: 5, start: input.today))
            }
        case .maintenance:
            break
        }
        guard let reason else { return nil }
        if plan.reasons.first != reason { plan.reasons.insert(reason, at: 0) }
        plan.headline = reason
        plan.updatedAt = Date()
        return plan
    }

    /// Ends the phase at `index` yesterday, then `next` (starting today, at its full length), so a
    /// review mid-week doesn't start the diet break in the past. The days already spent stay in the
    /// plan as they happened; a phase that hadn't begun is dropped.
    static func endEarly(_ plan: inout PhasePlan, at index: Int, today: Day, then next: PlannedPhase) {
        var phases = Array(plan.phases.prefix(index))
        var current = plan.phases[index]
        let spent = current.start.days(until: today)
        if spent > 0 {
            current.weeks = max(1, Int((Double(spent) / 7).rounded(.up)))
            current.endedEarly = spent % 7 == 0 ? nil : today.adding(days: -1)
            phases.append(current)
        }
        plan.phases = phases + [next]
    }
}
