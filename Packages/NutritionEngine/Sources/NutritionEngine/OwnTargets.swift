import Foundation
import SystemCore

/// Calories and protein, carbs and fat in grams: a day's targets as the person sets them, and the
/// plan's as the targets sheet shows them beside.
public struct MacroTargets: Hashable, Codable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    /// A day's targets with all four numbers; nil for one without a calorie target (the assessment, illness).
    public init?(_ targets: DailyTargets) {
        guard let kcal = targets.kcal else { return nil }
        self.init(kcal: kcal, protein: targets.protein ?? 0, carbs: targets.carbs ?? 0, fat: targets.fat ?? 0)
    }

    /// These grams, with the calories they add up to.
    public static func grams(protein: Double, carbs: Double, fat: Double) -> MacroTargets {
        let grams = MacroTargets(kcal: 0, protein: max(0, protein), carbs: max(0, carbs), fat: max(0, fat))
        return MacroTargets(kcal: grams.gramsKcal.rounded(), protein: grams.protein, carbs: grams.carbs, fat: grams.fat)
    }

    /// The calories protein, carbs and fat add up to: 4 a gram of protein and of carbs, 9 of fat.
    public var gramsKcal: Double { protein * 4 + carbs * 4 + fat * 9 }

    /// Each macro's share of the calories they add up to, 0 to 1, adding up to 1.
    public var shares: (protein: Double, carbs: Double, fat: Double) {
        let total = gramsKcal
        guard total > 0 else { return (0, 0, 0) }
        return (protein * 4 / total, carbs * 4 / total, fat * 9 / total)
    }

    /// Whether the calories are what the grams add up to, give or take the whole grams they're
    /// rounded to (a gram of fat is 9 kcal) or 1%.
    public var inStep: Bool { abs(kcal - gramsKcal) <= max(10, kcal * 0.01) }

    /// The calories set to `kcal`, the grams following them: protein stays (it's set by body
    /// weight, and it's what protects muscle), and carbs and fat share what's left in the
    /// proportion they had, to the whole gram. With neither, fat takes about 27% of the calories,
    /// as the plan's split does. The calories stay as typed: a rounded gram either way is a few kcal.
    public func calories(_ kcal: Double) -> MacroTargets {
        let kcal = max(0, kcal)
        let rest = max(0, kcal - protein * 4)
        let had = carbs * 4 + fat * 9
        let fatShare = had > 0 ? fat * 9 / had : min(1, kcal * 0.27 / max(1, rest))
        let fat = (rest * fatShare / 9).rounded()
        let carbs = max(0, ((rest - fat * 9) / 4).rounded())
        return MacroTargets(kcal: kcal.rounded(), protein: protein, carbs: carbs, fat: fat)
    }

    /// The plan's split of `kcal` for someone of `referenceKg` (protein for the phase, fat at least
    /// 0.6 g/kg and about 27%, the rest carbs): the assessment's maintenance as the starting point
    /// split it.
    public static func split(_ kcal: Double, referenceKg: Double, phase: PhaseKind?) -> MacroTargets {
        let m = Targets.macros(kcal: kcal, referenceKg: referenceKg, phase: phase)
        return MacroTargets(kcal: kcal, protein: m.protein, carbs: m.carbs, fat: m.fat)
    }
}

/// The person's own targets: numbers from a coach, a dietitian or their own plan, set in the
/// targets sheet (onboarding's "Set my own targets", Plan's Adjust) in place of the plan's.
///
/// They're kept as a check-in of the person's (`CheckIn.Status.manual`), in force from its day like
/// any other, so each day is judged by the targets it had and they sync as check-ins do. Nothing
/// changes them but the person: the weekly check-in still reviews the data and moves the plan's
/// maintenance, but keeps the person's numbers, carrying the plan's own underneath (`CheckIn.plan`)
/// so Plan can say what the plan would set and going back picks up where the plan would be. A life
/// mode the person turns on (vacation, illness, crunch) still changes the day; a deload's diet break,
/// which the plan would make by itself, doesn't. Starting or changing the plan goes back to the
/// plan's targets.
public enum OwnTargets {
    /// The calories the sheet takes: under 1,000 kcal a day is a diet for a doctor to run, and over
    /// 6,000 is a typo.
    public static let kcalRange: ClosedRange<Double> = 1_000...6_000

    /// A step of the sheet's − and +.
    public static let kcalStep = 50.0
    public static let gramStep = 5.0

    /// One step of − or + from `value`, onto the steps' grid: 2,098 kcal goes up to 2,100 and down to
    /// 2,050, as a coach's numbers are round. Never below nothing.
    public static func stepped(_ value: Double, by direction: Double, step: Double) -> Double {
        let onGrid = abs(value / step - (value / step).rounded()) < 1e-9
        let next =
            direction > 0 ? (onGrid ? value / step + 1 : (value / step).rounded(.up)) : (onGrid ? value / step - 1 : (value / step).rounded(.down))
        return max(0, next * step)
    }

    /// Why these numbers can't be saved, in a line; nil when they can.
    public static func problem(_ t: MacroTargets) -> String? {
        if t.protein * 4 > t.kcal + 10, t.kcal >= kcalRange.lowerBound {
            return "Protein alone is \(Int(t.protein * 4).formatted()) kcal, more than the calories."
        }
        if t.kcal < kcalRange.lowerBound { return "At least \(Int(kcalRange.lowerBound).formatted()) kcal a day." }
        if t.kcal > kcalRange.upperBound { return "At most \(Int(kcalRange.upperBound).formatted()) kcal a day." }
        if !t.inStep { return "Protein, carbs and fat come to \(Int(t.gramsKcal.rounded()).formatted()) kcal." }
        return nil
    }

    /// Where the sheet's reference numbers come from.
    public enum Source: String, Sendable {
        /// The plan's targets for today.
        case plan
        /// The assessment's maintenance so far, split as the plan would: the assessment itself sets
        /// no calories.
        case maintenance
        /// Onboarding's starting point: the formula's maintenance, before there's any data.
        case startingPoint
    }

    /// The person's own targets as they stand today.
    public struct InForce: Hashable, Sendable {
        public var numbers: MacroTargets
        /// The first day of this run of them.
        public var since: Day
    }

    /// The person's own targets in force on `day`, from the check-ins (oldest first) and today's
    /// due one: nil when the plan's are.
    public static func inForce(_ checkIns: [CheckIn], due: CheckIn?, on day: Day) -> InForce? {
        let earlier = checkIns.filter { $0.day <= day }
        let all = due.map { due in earlier.filter { $0.day < due.day } + [due] } ?? earlier
        guard let current = all.last, current.isOwn else { return nil }
        let since = all.reversed().prefix { $0.isOwn }.last?.day ?? current.day
        return InForce(numbers: current.own, since: since)
    }

    /// The check-in that puts the person's numbers in force from `day`, replacing any made that day.
    /// `expenditure` carries on the plan's maintenance (the check-in in force's, else the estimate),
    /// and `plan` the plan's own targets for the day, when it has calories, so its weekly steps
    /// carry on from them.
    public static func record(_ numbers: MacroTargets, on day: Day, expenditure: Double, plan: MacroTargets?) -> CheckIn {
        CheckIn(
            id: CheckIn.id(for: day), day: day, expenditure: (expenditure / 10).rounded() * 10, kcal: numbers.kcal,
            protein: numbers.protein, carbs: numbers.carbs, fat: numbers.fat, status: .manual,
            reason: "Set by you. Each weekly check-in keeps learning your maintenance and leaves these as they are.", plan: plan)
    }

    /// Setting the person's numbers from today, over what the analysis has in force.
    public static func record(_ numbers: MacroTargets, _ a: MacroAnalysis, today: Day) -> CheckIn {
        let current = a.dueCheckIn ?? a.checkIn
        return record(
            numbers, on: today, expenditure: current?.expenditure ?? a.maintenance.kcal,
            plan: a.planSource == .plan ? a.planNumbers : nil)
    }

    /// A week's review while the person's own targets are on: their numbers kept, with the
    /// maintenance the plan's review moved to and the targets it would have set.
    static func kept(_ own: CheckIn, planned: CheckIn) -> CheckIn {
        CheckIn(
            id: planned.id, day: planned.day, expenditure: planned.expenditure, kcal: own.kcal, protein: own.protein,
            carbs: own.carbs, fat: own.fat, status: .manual,
            reason:
                "Your own targets hold. With maintenance at about \(Int(planned.expenditure).formatted()) kcal, the plan would set \(Int(planned.kcal).formatted()).",
            plan: planned.own)
    }

    /// What going back to the plan's targets does today.
    public enum Back: Hashable, Sendable {
        /// The plan's targets from today, as a check-in of the plan's.
        case save(CheckIn)
        /// Before a plan (the assessment, which sets no calories): the person's numbers go, and the
        /// days they ran count as the assessment's, judged on protein alone.
        case remove([UUID])
        /// They weren't on.
        case nothing
    }

    /// Going back to the plan's targets from `today`: with a plan running, its numbers for today as
    /// the sheet showed them, from where its weekly steps had got to; in the assessment, the
    /// assessment again.
    public static func back(_ a: MacroAnalysis, checkIns: [CheckIn], today: Day) -> Back {
        guard a.own != nil else { return .nothing }
        guard a.plan != nil, a.planSource == .plan else { return .remove(checkIns.filter(\.isOwn).map(\.id)) }
        let current = a.dueCheckIn ?? a.checkIn
        let numbers = a.planNumbers
        let expenditure = ((current?.expenditure ?? a.maintenance.kcal) / 10).rounded() * 10
        return .save(
            CheckIn(
                id: CheckIn.id(for: today), day: today, expenditure: expenditure, kcal: numbers.kcal, protein: numbers.protein,
                carbs: numbers.carbs, fat: numbers.fat, status: .updated,
                reason: "Back to the plan's targets, from maintenance of about \(Int(expenditure).formatted()) kcal."))
    }

    /// The weekly change in weight, kg, that `kcal` a day aims for from maintenance: nothing within
    /// 5% of maintenance (holding), else the gap at 7,700 kcal a kg.
    public static func aim(kcal: Double, maintenance: Double) -> Double {
        guard maintenance > 0, abs(kcal - maintenance) > maintenance * 0.05 else { return 0 }
        return (kcal - maintenance) * 7 / Energy.kcalPerKg
    }
}

extension CheckIn {
    /// Whether this check-in holds the person's own targets rather than the plan's.
    public var isOwn: Bool { status == .manual }

    /// The numbers in force, as the targets sheet edits them.
    public var own: MacroTargets { MacroTargets(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    /// The plan's side of this check-in: itself, or with the person's own targets on, the plan's
    /// targets carried underneath (nil when there were none, in the assessment).
    var planned: CheckIn? {
        guard isOwn else { return self }
        guard let plan else { return nil }
        return CheckIn(
            id: id, day: day, expenditure: expenditure, kcal: plan.kcal, protein: plan.protein, carbs: plan.carbs, fat: plan.fat,
            status: .updated, reason: reason, updatedAt: updatedAt)
    }
}
