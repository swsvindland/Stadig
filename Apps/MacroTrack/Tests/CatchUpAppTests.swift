import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// Catching up a day that wasn't logged as it happened: a past day's usual times, each logged from
/// what was last eaten then (one, or all at once) with Undo, and the logger's suggestions following
/// the time it logs at rather than the clock.
@MainActor
struct CatchUpAppTests {
    func food(_ name: String, kcal: Double, at date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: name, amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: kcal / 20, carbs: kcal / 8, fat: kcal / 30),
            source: .search)
    }

    /// A week to the day before yesterday: oats and coffee at 8, soup at 1, salmon at 7.
    func week(_ model: AppModel) {
        var entries: [FoodEntry] = []
        for back in 2...8 {
            let day = model.today.adding(days: -back)
            entries += [
                food("Oats", kcal: 300, at: day.at(hour: 8, minute: 0)), food("Coffee", kcal: 5, at: day.at(hour: 8, minute: 2)),
                food("Soup", kcal: 400, at: day.at(hour: 13, minute: 0)), food("Salmon", kcal: 600, at: day.at(hour: 19, minute: 0)),
            ]
        }
        model.log(entries)
        model.toast = nil
    }

    @Test func aPastDayCatchesUpFromItsUsualTimesWithUndo() throws {
        let model = TestEnvironment().model()
        model.onboard()
        week(model)
        let yesterday = model.today.adding(days: -1)
        #expect(model.catchUp.isEmpty, "today isn't caught up: it's logged as it goes")

        model.selectedDay = yesterday
        #expect(model.catchUp.map(\.time) == [8, 13, 19].map { yesterday.at(hour: $0, minute: 0) })
        #expect(model.usualLogTimes() == model.catchUp.map(\.time))

        // Breakfast as usual, at its time on that day.
        let breakfast = try #require(model.catchUp.first)
        model.catchUp(breakfast)
        #expect(model.entries(on: yesterday).map(\.name) == ["Oats", "Coffee"])
        #expect(model.entries(on: yesterday).first?.date == yesterday.at(hour: 8, minute: 0))
        #expect(model.toast?.message.hasPrefix("Logged Oats and coffee · ") == true)
        #expect(model.catchUp.map(\.time) == [13, 19].map { yesterday.at(hour: $0, minute: 0) })
        model.undo(try #require(model.toast))
        #expect(model.entries(on: yesterday).isEmpty)
        #expect(model.catchUp.count == 3)

        // The whole day at once, and back with one Undo.
        model.catchUpAll()
        #expect(model.entries(on: yesterday).map(\.name) == ["Oats", "Coffee", "Soup", "Salmon"])
        #expect(model.toast?.message.hasPrefix("Logged 3 meals · ") == true)
        #expect(model.catchUp.isEmpty)
        model.undo(try #require(model.toast))
        #expect(model.entries(on: yesterday).isEmpty)

        // A day marked done has nothing left to catch up.
        model.setState(.complete, for: yesterday)
        #expect(model.catchUp.isEmpty)
        model.setState(nil, for: yesterday)
        #expect(model.catchUp.count == 3)
    }

    @Test func sameAsLeavesAMealAlreadyPlannedThen() throws {
        let model = TestEnvironment().model()
        model.onboard()
        week(model)
        let ahead = model.today.adding(days: 1)
        model.selectedDay = ahead
        model.openLogger(.search)
        model.loggerTime = ahead.at(hour: 8, minute: 0)
        let usual = try #require(model.loggerUsual)
        #expect(usual.entries.map(\.name) == ["Oats", "Coffee"])

        // Once it's planned there, one more tap would only log it twice.
        model.logAgain(usual)
        #expect(model.allEntries(on: ahead).count == 2)
        #expect(model.loggerUsual == nil)

        // What's planned isn't what's offered either: the day after still gets what was eaten.
        model.logger = nil
        let after = ahead.adding(days: 1)
        model.selectedDay = after
        model.openLogger(.search)
        model.loggerTime = after.at(hour: 8, minute: 0)
        #expect(Day(try #require(model.loggerUsual).start) == model.today.adding(days: -2))
    }

    @Test func theLoggerSuggestsForTheTimeItLogsAt() throws {
        let model = TestEnvironment().model()
        model.onboard()
        week(model)
        let breakfast = model.entries(on: model.today.adding(days: -2)).filter { $0.name != "Soup" && $0.name != "Salmon" }
        let dinner = model.entries(on: model.today.adding(days: -2)).filter { $0.name == "Salmon" }
        model.saveMeal(named: "Oat breakfast", from: breakfast)
        model.saveMeal(named: "Salmon dinner", from: dinner)

        // Now, the clock's own.
        model.openLogger(.search)
        #expect(model.timedSuggestions == nil)
        #expect(model.loggerLogAgain == model.logAgain)

        // Lunch for 1 PM and breakfast for 8, whatever the clock says.
        model.loggerTime = model.today.at(hour: 13, minute: 0)
        #expect(model.loggerLogAgain.first?.template.name == "Soup")
        model.loggerTime = model.today.at(hour: 8, minute: 0)
        #expect(["Oats", "Coffee"].contains(model.loggerLogAgain.first?.template.name ?? ""))
        #expect(model.loggerMeals.first?.meal.name == "Oat breakfast")
        #expect(model.loggerUsual?.entries.map(\.name) == ["Oats", "Coffee"])
        model.loggerTime = model.today.at(hour: 19, minute: 0)
        #expect(model.loggerMeals.first?.meal.name == "Salmon dinner")

        // Closing the logger drops its time, and with it the timed suggestions.
        model.logger = nil
        #expect(model.timedSuggestions == nil)

        // A past day logs at the same time of day there, and ranks for it; a usual time picked
        // there ranks for that.
        model.selectedDay = model.today.adding(days: -1)
        model.openLogger(.search)
        #expect(model.timedSuggestions?.time == model.logDate())
        let yesterday = model.selectedDay
        model.loggerTime = model.usualLogTimes()[1]
        #expect(model.loggerLogAgain.first?.template.name == "Soup")
        // "Same as" there, until that day has its breakfast.
        model.loggerTime = model.usualLogTimes()[0]
        let usual = try #require(model.loggerUsual)
        model.logAgain(usual)
        #expect(model.entries(on: yesterday).map(\.date) == [0.0, 1.0].map { yesterday.at(hour: 8, minute: 0).addingTimeInterval($0) })
        #expect(model.loggerUsual == nil)
    }
}
