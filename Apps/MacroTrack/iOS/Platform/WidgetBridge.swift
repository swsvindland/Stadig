import Foundation
import NutritionEngine
import SystemCore
import WidgetKit

/// Keeps the widgets' snapshot current.
enum WidgetBridge {
    @MainActor
    static func update(_ model: AppModel) {
        guard let analysis = model.analysis else { return }
        let t = analysis.targets
        let eaten = analysis.todayIntake
        var snapshot = MacroSnapshot(
            day: model.today.iso, kcal: eaten.kcal, kcalTarget: t.kcal, protein: eaten.protein,
            proteinTarget: t.protein, carbs: eaten.carbs, carbsTarget: t.carbs, fat: eaten.fat, fatTarget: t.fat)
        snapshot.weighedToday = model.weighIns.contains { $0.day == model.today }
        let later = model.foodLog.later(through: model.today.adding(days: 1), since: analysis.fast?.fast.start)
        snapshot.later = later.isEmpty ? nil : later
        snapshot.badge =
            switch t.mode {
            case .assessment: analysis.assessment.map { "Day \($0.day) of \($0.totalDays)" } ?? "Assessment"
            case .dietBreak: "Diet break"
            case .crunch: "Crunch"
            case .illness: "Ill"
            case .vacation: "Vacation"
            case .phase: analysis.phase?.kind.label
            }
        if model.tracksMealTiming {
            snapshot.tracksMealTiming = true
            snapshot.fastStart = analysis.fast?.fast.start
            snapshot.fastGoalHours = analysis.fast?.fast.goalHours
            snapshot.lastMealEnd = analysis.lastMeal?.end
        }
        if snapshot.save(to: model.widgetURL), model.usesSystemServices { WidgetCenter.shared.reloadAllTimelines() }
    }
}
