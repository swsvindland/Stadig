import Foundation
import MealPlanner
import NutritionEngine
import SystemCore

/// What's needed to take a move on the week desk back: its toast (whose Undo it is) and the foods
/// as the move left them, to tell that it's still in force.
struct WeekUndo {
    let toast: Toast
    let moved: [FoodEntry]
}

extension AppModel {
    /// What the week desk draws a week from: its log, eaten and for later, the meal plan's dishes
    /// not logged yet, the doses taken, and each day's targets as that day has them.
    func weekLog(_ week: Day) -> WeekLog {
        let days = WeekDesk.days(of: week)
        var targets: [Day: DailyTargets] = [:]
        for day in days { targets[day] = self.targets(on: day) }
        return WeekLog(
            entries: days.flatMap { allEntries(on: $0) }, planned: plannedDishes(on: days),
            doses: supplementLogs.filter { days.contains($0.day) }, targets: targets, maintenance: analysis?.maintenance.kcal,
            saved: savedMeals)
    }

    func weekBoard(_ week: Day, now: Date) -> WeekBoard { WeekDesk.board(weekLog(week), week: week, now: now) }

    /// The desk with a meal held over another day, before anything is saved.
    func weekMove(_ meal: WeekMeal, to day: Day, week: Day, now: Date) -> WeekMove? {
        WeekDesk.move(meal, to: day, in: weekLog(week), week: week, now: now)
    }

    /// The trend over the four weeks to the week's end, or to today in the week under way.
    func weekWeight(_ week: Day) -> WeekWeight? {
        guard let trend = analysis?.trend else { return nil }
        return WeekDesk.weight(trend, through: min(week.startOfWeek.adding(days: 6), today))
    }

    /// The meal plan's dishes on these days, from the plan in force on each, at their meal's usual
    /// time, leaving out those logged (the log has them).
    private func plannedDishes(on days: [Day]) -> [WeekPlanned] {
        var logged: [UUID: Set<String>] = [:]
        return days.flatMap { day -> [WeekPlanned] in
            guard let plan = mealPlan(covering: day) else { return [] }
            let done = logged[plan.id] ?? loggedMeals(in: plan)
            logged[plan.id] = done
            return plan.meals(on: day).filter { !done.contains($0.id) }.compactMap { meal in
                guard let recipe = plan.recipe(meal.recipeID) else { return nil }
                return WeekPlanned(
                    id: meal.id, time: day.at(minutes: Int((meal.slot.hour * 60).rounded())), name: recipe.title,
                    foods: recipe.items.map(\.name), nutrients: recipe.nutrients)
            }
        }
    }

    /// Moves a meal on the desk to another day, each food at its own time of day: the Log tab's move
    /// (`placeSelection`), so its toast, Undo, Health and fasts are the same. The Log tab's own
    /// selection is left as it was. Nil when nothing moved.
    @discardableResult
    func moveMeal(_ meal: WeekMeal, to day: Day) -> WeekUndo? {
        guard meal.canMove, day != meal.day else { return nil }
        let ids = Set(meal.entries.map(\.id))
        // Still in the log: a sync since the desk was drawn may have deleted them.
        guard foodLog.all.contains(where: { ids.contains($0.id) }) else { return nil }
        let kept = selection
        selection = LogSelection(ids: ids, intent: .move)
        placeSelection(on: [day])
        selection = kept
        guard let toast, !toast.restore.isEmpty else { return nil }
        return WeekUndo(toast: toast, moved: foodLog.all.filter { ids.contains($0.id) })
    }

    /// Puts a move back (⌘Z), if it's still in force: not after the toast's Undo, or once its foods
    /// have moved on again.
    @discardableResult
    func undoMove(_ move: WeekUndo) -> Bool {
        guard !move.moved.isEmpty, move.moved.allSatisfy({ current($0) != nil }) else { return false }
        undo(move.toast)
        return true
    }

    /// Over the desk's title: where the plan is in the week under way, else which week it is.
    func weekEyebrow(_ week: Day) -> String {
        let weeks = today.startOfWeek.days(until: week.startOfWeek) / 7
        switch weeks {
        case 0:
            guard let phase = analysis?.phase else { return "This week" }
            return "\(phase.kind.label), week \(phase.week(on: today)) of \(phase.weeks)"
        case -1: return "Last week"
        case 1: return "Next week"
        case ..<0: return "\(-weeks) weeks ago"
        default: return "In \(weeks) weeks"
        }
    }
}
