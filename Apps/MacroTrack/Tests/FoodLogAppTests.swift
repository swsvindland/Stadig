import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// Food logged for later, in the app: on the day's rows from the start, counted from its time.
@MainActor
struct FoodLogAppTests {
    func food(_ name: String, kcal: Double, at date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: name, amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: kcal / 20, carbs: kcal / 8, fat: kcal / 30),
            source: .search)
    }

    /// Later today, or tomorrow when it's late enough that no later today is left.
    func laterDate(_ model: AppModel) -> Date { Date().addingTimeInterval(3 * 3600) }

    @Test func laterFoodIsOnTheRowsButNotCounted() {
        let model = TestEnvironment().model()
        model.onboard()
        let date = laterDate(model)
        model.log([food("Dinner", kcal: 800, at: date)])

        #expect(model.entries.isEmpty)
        #expect(model.foodLog.upcoming.map(\.name) == ["Dinner"])
        #expect(model.allEntries(on: Day(date)).map(\.name) == ["Dinner"])
        #expect(model.entries(on: Day(date)).isEmpty)
        #expect((model.analysis?.intakeByDay[Day(date)]?.kcal ?? 0) == 0)
        #expect(model.dayIntake(on: Day(date)).later.kcal == 800)
    }

    @Test func aLaterFoodCanBeRemoved() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let date = laterDate(model)
        model.log([food("Dinner", kcal: 800, at: date)])
        let entry = try #require(model.foodLog.upcoming.first)

        model.delete(entries: [entry.id])

        #expect(model.foodLog.all.isEmpty)
        #expect(model.toast?.message == "Deleted Dinner")
    }

    @Test func aLaterFoodCanBeEdited() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let date = laterDate(model)
        model.log([food("Dinner", kcal: 800, at: date)])
        var entry = try #require(model.foodLog.upcoming.first)
        entry.nutrients.kcal = 900
        model.update(entry)
        #expect(model.foodLog.upcoming.first?.nutrients.kcal == 900)
        #expect(model.foodLog.upcoming.first?.firstLogged == entry.firstLogged)
    }

    @Test func aMealLoggedNowIsNotSplitAcrossTheTick() {
        let model = TestEnvironment().model()
        model.onboard()
        let now = Date()
        let meal = (0..<4).map { food("Food \($0)", kcal: 100, at: now.addingTimeInterval(Double($0))) }

        model.log(meal)

        #expect(model.foodLog.upcoming.isEmpty)
        #expect(model.analysis?.todayIntake.kcal == 400)
    }

    @Test func aFoodCountsWhenItsTimeComes() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        // Past `log`, which would call a time this close now.
        model.store.save(food("Coffee", kcal: 100, at: Date().addingTimeInterval(0.4)))
        model.reload()
        #expect(model.entries.isEmpty)
        #expect(model.foodLog.nextChange != nil)

        // Generous: with every suite running, the main actor can be seconds behind.
        #expect(await eventually(timeout: .seconds(60)) { model.entries.count == 1 })

        #expect(model.foodLog.upcoming.isEmpty)
        #expect(model.analysis?.todayIntake.kcal == 100)
    }

    @Test func refreshingPicksUpAFoodWhoseTimeHasPassed() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.store.save(food("Coffee", kcal: 100, at: Date().addingTimeInterval(0.05)))
        model.reload()
        try await Task.sleep(for: .milliseconds(100))
        model.refreshDay()
        #expect(model.entries.count == 1)
    }

    @Test func removingALaterFoodStopsTheTimer() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.log([food("Dinner", kcal: 800, at: laterDate(model))])
        #expect(model.foodLog.nextChange != nil)
        model.delete(entries: model.foodLog.upcoming.map(\.id))
        #expect(model.foodLog.nextChange == nil)
    }

    @Test func theCSVHoldsOnlyWhatsHappened() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.log([food("Toast", kcal: 200, at: Date().addingTimeInterval(-3600)), food("Dinner", kcal: 800, at: laterDate(model))])
        let urls = try model.exportCSV()
        let log = try #require(urls.first { $0.lastPathComponent.contains("diary") })
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("Toast"))
        #expect(!text.contains("Dinner"))
    }

    @Test func aModelWithALaterFoodGoesAway() async {
        weak var weakModel: AppModel?
        do {
            let model = TestEnvironment().model()
            model.onboard()
            model.log([food("Dinner", kcal: 800, at: laterDate(model))])
            weakModel = model
        }
        #expect(await eventually(timeout: .seconds(60)) { weakModel == nil })
    }
}
