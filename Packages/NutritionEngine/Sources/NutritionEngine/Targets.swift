import Foundation
import SystemCore

/// What today asks for. Some days ask for nothing at all.
public struct DailyTargets: Hashable, Codable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// The assessment: eat as usual and log; no deficit or surplus.
        case assessment
        /// The planned phase.
        case phase
        /// Calories back to maintenance during a system-wide deload in a cut.
        case dietBreak
        /// Crunch mode: protein first, maintenance calories, rough logging is fine.
        case crunch
        /// Ill: eat what you can, fluids, some protein. Nothing is flagged.
        case illness
        /// Away: no logging expected.
        case vacation
    }

    public var mode: Mode
    /// Nil when there's no calorie target today.
    public var kcal: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var note: String

    public init(mode: Mode, kcal: Double?, protein: Double?, carbs: Double?, fat: Double?, note: String) {
        self.mode = mode
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.note = note
    }

    /// Whether the day's intake met the targets: protein at least 90%, calories within 10%.
    public func hits(_ intake: Nutrients) -> (protein: Bool?, calories: Bool?) {
        let p = protein.map { intake.protein >= $0 * 0.9 }
        let c = kcal.map { abs(intake.kcal - $0) <= $0 * 0.1 }
        return (p, c)
    }
}

public enum Targets {
    /// The most a target moves from one week to the next.
    public static let weeklyStep = 150.0

    /// Weight protein is scaled to: actual weight, or a healthy weight for the height when
    /// waist-to-height is high, so targets stay sensible.
    public static func referenceWeight(kg: Double, heightCm: Double?, waistToHeight: Double?) -> Double {
        guard let h = heightCm, let wth = waistToHeight, wth >= 0.55 else { return kg }
        let meters = h / 100
        return min(kg, 25 * meters * meters)
    }

    public static func proteinPerKg(_ kind: PhaseKind?) -> Double {
        switch kind?.energy {
        case .deficit: 2.0
        case .surplus: 1.7
        default: kind == .recomp ? 2.0 : 1.8
        }
    }

    /// Whether a check-in was made for this phase: on or after the day it began. A check-in from an
    /// earlier phase only lends its maintenance.
    static func belongs(_ checkIn: CheckIn, to phase: PlannedPhase?) -> Bool {
        phase.map { checkIn.day >= $0.start } ?? true
    }

    /// Calories for the phase from maintenance, capped at a 25% deficit and a 500 kcal surplus.
    public static func calories(maintenance: Double, phase: PlannedPhase?, weightKg: Double) -> Double {
        guard let phase else { return maintenance }
        let delta = phase.ratePerWeek * weightKg * Energy.kcalPerKg / 7
        let capped = clamp(delta, -maintenance * 0.25, 500)
        return ((maintenance + capped) / 10).rounded() * 10
    }

    /// Splits calories into protein, fat (at least 0.6 g/kg and about 27% of calories) and carbs.
    public static func macros(kcal: Double, referenceKg: Double, phase: PhaseKind?) -> (protein: Double, carbs: Double, fat: Double) {
        let protein = (referenceKg * proteinPerKg(phase) / 5).rounded() * 5
        let fat = (max(referenceKg * 0.6, kcal * 0.27 / 9) / 5).rounded() * 5
        let carbs = max(0, ((kcal - protein * 4 - fat * 9) / 4 / 5).rounded() * 5)
        return (protein, carbs, fat)
    }

    /// Today's targets from the plan, the latest check-in and what life is doing.
    public static func today(day: Day, assessing: Bool, plan: PhasePlan?, override: PhaseKind?, maintenance: MaintenanceEstimate,
                             checkIn: CheckIn?, weightKg: Double, heightCm: Double?, waistToHeight: Double?,
                             life: LifeModeEffects, deload: Bool) -> DailyTargets {
        let reference = referenceWeight(kg: weightKg, heightCm: heightCm, waistToHeight: waistToHeight)
        var phase = plan?.phase(on: day)
        if let override, override != phase?.kind {
            phase = PlannedPhase(kind: override, weeks: 8, start: day)
        }

        if life.active.contains(where: { if case .vacation = $0.kind { true } else { false } }) {
            return DailyTargets(mode: .vacation, kcal: nil, protein: nil, carbs: nil, fat: nil,
                                note: "Enjoy the trip. No logging expected, and the first days back won't count against the scale.")
        }
        if life.active.contains(where: { if case .illness = $0.kind { true } else { false } }) {
            let protein = (reference * 1.2 / 5).rounded() * 5
            return DailyTargets(mode: .illness, kcal: nil, protein: protein, carbs: nil, fat: nil,
                                note: "Eat what you can: fluids first, some protein if it's easy. A soup day is fine.")
        }
        if life.minimumEffectiveDose {
            let kcal = (maintenance.kcal / 10).rounded() * 10
            let m = macros(kcal: kcal, referenceKg: reference, phase: .maintenance)
            return DailyTargets(mode: .crunch, kcal: kcal, protein: m.protein, carbs: nil, fat: nil,
                                note: "Busy stretch: protein first, maintenance calories. Rough restaurant estimates are fine.")
        }
        if assessing {
            let m = macros(kcal: maintenance.kcal, referenceKg: reference, phase: .maintenance)
            return DailyTargets(mode: .assessment, kcal: nil, protein: m.protein, carbs: nil, fat: nil,
                                note: "Eat as you normally do and log everything. No deficit or surplus yet.")
        }
        if deload, phase?.kind.energy == .deficit {
            let kcal = ((checkIn?.expenditure ?? maintenance.kcal) / 10).rounded() * 10
            let m = macros(kcal: kcal, referenceKg: reference, phase: .dietBreak)
            return DailyTargets(mode: .dietBreak, kcal: kcal, protein: m.protein, carbs: m.carbs, fat: m.fat,
                                note: "Deload week, so calories go back to maintenance. A stalled scale now is water and expected; the cut resumes next week.")
        }

        // The weekly check-in sets the numbers. Without one, or with one from before this phase began
        // (a late check-in, or the day a diet break starts), they come from the phase and the
        // maintenance the check-in was built on.
        let kcal: Double
        let m: (protein: Double, carbs: Double, fat: Double)
        if let checkIn, override == nil, belongs(checkIn, to: phase) {
            kcal = checkIn.kcal
            m = (checkIn.protein, checkIn.carbs, checkIn.fat)
        } else {
            kcal = calories(maintenance: checkIn?.expenditure ?? maintenance.kcal, phase: phase, weightKg: weightKg)
            m = macros(kcal: kcal, referenceKg: reference, phase: phase?.kind)
        }
        let note: String = switch phase?.kind {
        case .cut, .miniCut: "In a cut. The scale is read as a trend across the block, not day to day."
        case .reverseDiet: "Calories rise a little each week while weight stays roughly stable."
        case .leanBulk: "A slow surplus. Gaining faster than planned eases it back."
        case .recomp: "Around maintenance with plenty of protein."
        case .dietBreak: "A diet break at maintenance."
        default: "Maintenance."
        }
        return DailyTargets(mode: .phase, kcal: kcal, protein: m.protein, carbs: m.carbs, fat: m.fat, note: note)
    }
}
