import Foundation
import SystemCore

/// What onboarding shows before the first day: the formula's maintenance for the answers given, as
/// calories a day, and how protein, carbs and fat would split them. It's a first guess, and said to
/// be one: the assessment that follows has no calorie target (only protein), and learns the real
/// maintenance from three weeks of logs and weigh-ins.
public struct StartingPoint: Hashable, Sendable {
    /// The formula's maintenance, to the nearest 10 kcal.
    public var kcal: Double
    /// The protein the assessment asks for; carbs and fat are how the rest of maintenance splits.
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    /// How long the assessment runs, in days.
    public var assessmentDays: Int

    /// Each macro's share of the calories, 0 to 1, in the order protein, carbs, fat. They add up to 1.
    public var shares: (protein: Double, carbs: Double, fat: Double) {
        let total = protein * 4 + carbs * 4 + fat * 9
        guard total > 0 else { return (0, 0, 0) }
        return (protein * 4 / total, carbs * 4 / total, fat * 9 / total)
    }

    /// From the profile and a weight. The training days are the profile's (Stadig Lift's sessions
    /// take over once there are some), and Health's weigh-ins from before today can shorten the
    /// assessment to two weeks.
    public static func make(profile: SharedProfile, weightKg: Double, today: Day, weighInsBefore: Int = 0) -> StartingPoint {
        let other = Double(profile.recurring.map { $0.minutes * $0.weekdays.count }.reduce(0, +))
        let formula = Energy.formula(
            sex: profile.sex, kg: weightKg, heightCm: profile.heightCm, age: profile.age(on: today),
            trainingDays: profile.schedule.daysPerWeek, otherActiveMinutes: other)
        let kcal = (formula / 10).rounded() * 10
        let m = Targets.macros(kcal: kcal, referenceKg: weightKg, phase: .maintenance)
        return StartingPoint(
            kcal: kcal, protein: m.protein, carbs: m.carbs, fat: m.fat,
            assessmentDays: MacroAnalyst.assessmentDays(weighInsBeforeStart: weighInsBefore))
    }

}
