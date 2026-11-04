import Foundation
import MealPlanner
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack
@testable import SystemStore

/// A save the store couldn't make, as on a full disk: what was being logged isn't logged, and
/// nothing says it was.
@MainActor
struct FailedSaveTests {
    func lunch(at date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: "Lunch", amountLabel: "1 serving", nutrients: Nutrients(kcal: 600, protein: 30, carbs: 70, fat: 20), source: .search)
    }

    /// A set-up model whose next save fails.
    func failing() -> (AppModel, RecordStore) {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        environment.store.nextSaveFailure = CocoaError(.fileWriteOutOfSpace)
        return (model, environment.store)
    }

    @Test func foodThatDidntSaveIsntShownAndTheToastSaysSo() throws {
        let (model, store) = failing()
        let day = model.today.adding(days: -1)
        let entry = lunch(at: day.at(hour: 12, minute: 0))

        #expect(model.log([entry]) == false)

        #expect(model.allEntries(on: day).isEmpty, "a day's rows")
        #expect(model.foodLog.all.isEmpty, "what the ring and the Log tab read")
        let toast = try #require(model.toast)
        #expect(toast.message == "Couldn't save Lunch")
        #expect(toast.failed)
        #expect(!toast.canUndo, "there's nothing to take back")
        #expect(store.all(FoodEntry.self).isEmpty)
    }

    @Test func theNextLogWorksAsUsual() throws {
        let (model, _) = failing()
        let day = model.today.adding(days: -1)
        model.log([lunch(at: day.at(hour: 12, minute: 0))])

        #expect(model.log([lunch(at: day.at(hour: 12, minute: 0))]))

        #expect(model.allEntries(on: day).count == 1)
        let toast = try #require(model.toast)
        #expect(!toast.failed)
        #expect(toast.canUndo)
    }

    @Test func siriDoesntSayItLoggedFoodThatDidntSave() async {
        let (model, _) = failing()
        let reply = await model.logDescribed("banana")
        #expect(reply.hasPrefix("Couldn't save"))
        #expect(model.foodLog.all.isEmpty)
    }

    @Test func aMoveWhoseCopiesDidntSaveMovesNothing() throws {
        let (model, store) = failing()
        store.nextSaveFailure = nil
        let day = model.today.adding(days: -1)
        let entry = lunch(at: day.at(hour: 12, minute: 0))
        model.log([entry])
        model.toggleSelection(entry)
        store.nextSaveFailure = CocoaError(.fileWriteOutOfSpace)

        model.placeSelection(on: [day.adding(days: -2), day.adding(days: -1)])

        #expect(model.allEntries(on: day).map(\.name) == ["Lunch"])
        #expect(model.allEntries(on: day.adding(days: -2)).isEmpty)
        #expect(model.toast?.failed == true)
    }

    @Test func aPlannedMealThatDidntSaveStaysUnlogged() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        SampleData.seedIfEmpty(model)
        let plan = model.makeMealPlan(preferences: PlanPreferences(slots: Set(MealSlot.allCases)), start: model.today)
        let meal = try #require(plan.meals.first { $0.day == model.today })
        environment.store.nextSaveFailure = CocoaError(.fileWriteOutOfSpace)

        model.logPlanned(meal, in: plan)

        let kept = try #require(model.mealPlans.first { $0.id == plan.id })
        #expect(kept.logged[meal.id] == nil, "no id of a food that isn't there")
    }
}
