import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// The week desk on the model: what it draws a week from, and a meal moved to another day through
/// the Log tab's move, with its Undo and ⌘Z.
@MainActor
struct WeekDeskAppTests {
    func food(_ name: String, kcal: Double = 300, at date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: name, amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: kcal / 15, carbs: kcal / 8, fat: kcal / 30),
            source: .search)
    }

    /// Next week, so every day of it is ahead whatever the clock says.
    func nextWeek(_ model: AppModel) -> Day { model.today.startOfWeek.adding(days: 7) }

    @Test func aMealMovesAtItsOwnTimesAndTheToastPutsItBack() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let monday = nextWeek(model)
        let wednesday = monday.adding(days: 2)
        model.log([food("Pasta", kcal: 700, at: monday.at(hour: 19, minute: 0)), food("Salad", kcal: 150, at: monday.at(hour: 19, minute: 5))])
        let other = food("Toast", at: monday.at(hour: 8, minute: 0))
        model.log([other])
        // Something picked out on the Log tab stays picked out.
        model.select(other, intent: .copy)
        let meal = try #require(model.weekBoard(monday, now: Date()).day(monday)?.meals.last)
        #expect(meal.name == "Pasta, salad")

        let undo = try #require(model.moveMeal(meal, to: wednesday))

        let moved = model.allEntries(on: wednesday)
        #expect(moved.map(\.name) == ["Pasta", "Salad"])
        #expect(moved.map { Calendar.current.dateComponents([.hour, .minute], from: $0.date).minute } == [0, 5], "each at its own time")
        #expect(model.allEntries(on: monday).map(\.name) == ["Toast"])
        #expect(model.selection.ids == [other.id] && model.selection.intent == .copy)
        #expect(model.toast?.message == "Moved 2 foods to \(model.dayName(wednesday))")
        #expect(undo.moved.count == 2)

        model.undo(try #require(model.toast))
        #expect(model.allEntries(on: monday).map(\.name) == ["Toast", "Pasta", "Salad"])
        #expect(model.undoMove(undo) == false, "⌘Z after the toast's Undo has nothing to put back")
    }

    @Test func commandZPutsAMoveBackWhileItStands() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let monday = nextWeek(model)
        model.log([food("Pasta", at: monday.at(hour: 19, minute: 0))])
        let meal = try #require(model.weekBoard(monday, now: Date()).day(monday)?.meals.first)
        let undo = try #require(model.moveMeal(meal, to: monday.adding(days: 3)))
        model.toast = nil

        #expect(model.undoMove(undo))
        #expect(model.allEntries(on: monday).map(\.name) == ["Pasta"])
        #expect(model.allEntries(on: monday.adding(days: 3)).isEmpty)
        #expect(model.undoMove(undo) == false, "once")
        #expect(model.moveMeal(meal, to: monday) == nil, "the day it's on")
    }

    /// The plan's dishes are on the desk until they're logged; then the log has them, once.
    @Test func thePlansDishesShowUntilLogged() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let monday = nextWeek(model)
        let plan = model.makeMealPlan(preferences: PlanPreferences(slots: Set(MealSlot.allCases)), start: monday)
        let board = model.weekBoard(monday, now: Date())
        let tuesday = try #require(board.day(monday.adding(days: 1)))
        #expect(tuesday.meals.count == 4)
        #expect(tuesday.meals.allSatisfy { $0.kind == .planned && !$0.canMove })
        #expect(abs(tuesday.ahead.kcal - plan.planned(on: tuesday.day).kcal) < 0.5)

        let dinner = try #require(plan.meals(on: tuesday.day).last)
        model.logPlanned(dinner, in: plan)
        let after = try #require(model.weekBoard(monday, now: Date()).day(tuesday.day))
        #expect(after.meals.count == 4)
        #expect(after.meals.filter { $0.kind == .planned }.count == 3)
        #expect(after.meals.last?.kind == .later && after.meals.last?.canMove == true)
    }

    @Test func theWeekIsTheLogTabWithoutTheSidebar() {
        let model = TestEnvironment().model()
        model.onboard()
        model.go(to: .week)
        #expect(model.tab == .log)
        #expect(AppTab.week.title == "Week")
        #expect(AppTab.allCases.last == .week, "⌘9, after the eight there were")
    }
}
