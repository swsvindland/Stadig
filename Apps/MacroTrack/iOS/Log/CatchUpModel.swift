import Foundation
import NutritionEngine
import SystemCore

/// What the logger offers for a time that isn't now: the foods and meals eaten around then, and
/// what was eaten then on another recent day.
struct TimedSuggestions {
    var time: Date
    var logAgain: [LogAgainItem]
    var meals: [MealSuggestion]
    /// "Same as yesterday" for that time, while that day has nothing logged near it.
    var usual: Moment?
}

extension AppModel {
    /// Log Again in the logger, for the time it logs at.
    var loggerLogAgain: [LogAgainItem] { timedSuggestions?.logAgain ?? logAgain }

    /// Saved meals in the logger, best first for the time it logs at.
    var loggerMeals: [MealSuggestion] { timedSuggestions?.meals ?? mealSuggestions }

    /// "Same as yesterday" in the logger, for the time it logs at.
    var loggerUsual: Moment? {
        guard let timedSuggestions else { return usualNow }
        return timedSuggestions.usual
    }

    /// The selected past day's usual times with nothing logged near them yet, each a tap from what
    /// was last eaten then. None once the day is marked complete or fasted: it's been caught up.
    var catchUp: [UsualMeal] {
        let state = state(of: selectedDay)
        guard selectedDay < today, state != .complete, state != .fasting else { return [] }
        return usualTimes.filter { !$0.logged }
    }

    /// Usual times to pick in the logger: all of a past day's, and today's up to now.
    func usualLogTimes(now: Date = Date()) -> [Date] {
        usualTimes.map(\.time).filter { selectedDay < today || $0 <= now }
    }

    /// A meal by name: the saved meal it is, a food alone by its whole name ("Nuts, almonds", not
    /// "Nuts"), else its biggest foods ("Fish, potatoes and oil").
    func name(of moment: Moment) -> String {
        if let meal = SavedMeals.meal(for: moment.entries, in: savedMeals) { return meal.name }
        if moment.entries.count == 1, let only = moment.entries.first { return only.name }
        return SavedMeals.suggestedName(moment.entries)
    }

    /// What was last eaten at a usual time, logged at that time on the day being caught up.
    func catchUp(_ usual: UsualMeal) {
        let copies = LogAgain.copy(usual.latest, to: usual.time)
        log(copies, message: copies.count == 1 ? nil : "Logged \(name(of: usual.latest))")
    }

    /// Every usual time still to catch up, at once and with one Undo: a typical day.
    func catchUpAll() {
        let missing = catchUp
        guard missing.count > 1 else {
            if let only = missing.first { catchUp(only) }
            return
        }
        log(missing.flatMap { LogAgain.copy($0.latest, to: $0.time) }, message: "Logged \(missing.count) meals")
    }
}
