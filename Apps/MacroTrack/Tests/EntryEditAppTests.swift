import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// Edits to the log: saved together, undone together, and never forgetting when a food went in.
@MainActor
struct EntryEditAppTests {
    func food(_ name: String, kcal: Double, at date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: name, amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: kcal / 20, carbs: kcal / 8, fat: kcal / 30),
            source: .search)
    }

    func logged(_ model: AppModel) -> [FoodEntry] {
        let day = model.today.adding(days: -1)
        model.log([food("Oats", kcal: 300, at: day.at(hour: 8, minute: 0)), food("Soup", kcal: 400, at: day.at(hour: 13, minute: 0))])
        model.toast = nil
        return model.entries(on: day)
    }

    @Test func aBatchSavesTogetherAndUndoesTogether() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let before = logged(model)
        let target = model.today.adding(days: -3)
        let moved = before.map { entry in
            var entry = entry
            entry.date = target.at(sameTimeAs: entry.date)
            return entry
        }

        model.update(moved, message: "Moved 2 foods")

        #expect(model.entries(on: target).map(\.name) == ["Oats", "Soup"])
        #expect(model.entries(on: model.today.adding(days: -1)).isEmpty)
        let toast = try #require(model.toast)
        #expect(toast.canUndo)

        model.undo(toast)

        #expect(model.entries(on: target).isEmpty)
        let back = model.entries(on: model.today.adding(days: -1))
        #expect(back.map(\.date) == before.map(\.date))
        #expect(back.map(\.firstLogged) == before.map(\.firstLogged))
        #expect(model.toast == nil)
    }

    @Test func anEditKeepsTheFirstLogged() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let entry = try #require(logged(model).first)
        var bigger = entry
        bigger.nutrients.kcal = 500
        model.update(bigger)
        let stored = try #require(model.entries(on: entry.day).first)
        #expect(stored.nutrients.kcal == 500)
        #expect(stored.firstLogged == entry.firstLogged)
        #expect(stored.updatedAt > entry.updatedAt)
    }

    @Test func movingAFoodMovesItsDay() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let entry = try #require(logged(model).first)
        var moved = entry
        moved.date = model.today.adding(days: -2).at(hour: 9, minute: 0)
        model.update(moved)
        #expect(model.entries(on: model.today.adding(days: -2)).map(\.name) == ["Oats"])
    }

    @Test func undoingADeleteKeepsTheFirstLogged() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let before = logged(model)
        model.delete(entries: before.map(\.id))
        #expect(model.entries(on: before[0].day).isEmpty)
        let toast = try #require(model.toast)

        model.undo(toast)

        let back = model.entries(on: before[0].day)
        #expect(back.map(\.id) == before.map(\.id))
        #expect(back.map(\.firstLogged) == before.map(\.firstLogged))
    }

    @Test func aDaysIntakeSplitsAtNow() {
        let model = TestEnvironment().model()
        model.onboard()
        let day = model.today.adding(days: -1)
        model.log([food("Oats", kcal: 300, at: day.at(hour: 8, minute: 0)), food("Soup", kcal: 400, at: day.at(hour: 13, minute: 0))])
        let split = model.dayIntake(on: day, now: day.at(hour: 12, minute: 0))
        #expect(split.eaten.kcal == 300)
        #expect(split.later.kcal == 400)
        #expect(split.all.kcal == 700)
    }
}
