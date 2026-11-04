import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// Foods picked out on the Log tab and taken somewhere: moved, copied, across days, with an Undo.
@MainActor
struct SelectionAppTests {
    func food(_ name: String, kcal: Double = 200, at date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: name, amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: kcal / 20, carbs: kcal / 8, fat: kcal / 30),
            source: .search)
    }

    /// Two foods at noon and one at 7 PM yesterday, on a model looking at yesterday.
    func model() -> (AppModel, Day) {
        let model = TestEnvironment().model()
        model.onboard()
        let day = model.today.adding(days: -1)
        model.log([
            food("Soup", at: day.at(hour: 12, minute: 0)), food("Bread", at: day.at(hour: 12, minute: 10)),
            food("Salmon", at: day.at(hour: 19, minute: 0)),
        ])
        model.toast = nil
        model.show(day: day)
        return (model, day)
    }

    func hour(_ model: AppModel, _ day: Day, _ hour: Int) -> HourGroup {
        DayHours.groups(on: day, entries: model.allEntries(on: day)).first { $0.hour == hour } ?? HourGroup(start: Date(), end: Date(), hour: hour)
    }

    @Test func anHoursNameSelectsItAndAPartlySelectedHourSelectsTheRest() {
        let (model, day) = model()
        let noon = hour(model, day, 12)
        model.toggleSelection(noon.entries[0])
        #expect(model.selection.ids.count == 1)

        model.toggleSelection(noon)
        #expect(model.selection.ids.count == 2)

        model.toggleSelection(noon)
        #expect(model.selection.isEmpty)
    }

    @Test func aMoveEndsTheSelectionAndUndoPutsItBack() throws {
        let (model, day) = model()
        model.toggleSelection(hour(model, day, 12))
        let target = day.adding(days: -2)
        let before = model.selectedEntries

        model.placeSelection(.sameTimes(on: target), named: model.dayName(target))

        #expect(model.selection.isEmpty)
        #expect(model.allEntries(on: target).map(\.name) == ["Soup", "Bread"])
        #expect(model.allEntries(on: day).map(\.name) == ["Salmon"])
        let toast = try #require(model.toast)
        #expect(toast.message.hasPrefix("Moved 2 foods to "))

        model.undo(toast)

        #expect(model.allEntries(on: day).map(\.name) == ["Soup", "Bread", "Salmon"])
        #expect(model.allEntries(on: day).prefix(2).map(\.date) == before.map(\.date))
        #expect(model.allEntries(on: target).isEmpty)
    }

    @Test func aMoveKeepsWhenTheFoodWasFirstLogged() {
        let (model, day) = model()
        let chosen = hour(model, day, 12).entries
        model.toggleSelection(hour(model, day, 12))
        model.placeSelection(.sameTimes(on: day.adding(days: -1)), named: "then")
        #expect(model.allEntries(on: day.adding(days: -1)).map(\.firstLogged) == chosen.map(\.firstLogged))
    }

    @Test func aCopyKeepsTheSelectionForTheNextDay() {
        let (model, day) = model()
        model.selection.intent = .copy
        model.toggleSelection(hour(model, day, 12))
        let first = day.adding(days: -2)
        let second = day.adding(days: -3)

        model.placeSelection(.sameTimes(on: first), named: model.dayName(first))
        model.placeSelection(.sameTimes(on: second), named: model.dayName(second))

        #expect(model.selection.ids.count == 2)
        #expect(model.allEntries(on: first).count == 2)
        #expect(model.allEntries(on: second).count == 2)
        #expect(model.allEntries(on: day).count == 3)
        #expect(model.toast?.message.hasPrefix("Copied 2 foods to ") == true)
    }

    @Test func theSelectionSurvivesAChangeOfDay() {
        let (model, day) = model()
        model.toggleSelection(hour(model, day, 12))
        model.selectedDay = day.adding(days: -4)
        #expect(model.selection.ids.count == 2)
        #expect(model.selectedEntries.map(\.name) == ["Soup", "Bread"])
    }

    @Test func toAnHourKeepsTheGaps() {
        let (model, day) = model()
        model.toggleSelection(hour(model, day, 12))
        let target = day.adding(days: -2).at(hour: 18, minute: 0)
        model.placeSelection(.starting(target), named: "then")
        #expect(model.allEntries(on: day.adding(days: -2)).map(\.date) == [target, target.addingTimeInterval(600)])
    }

    @Test func manyDatesAtOnce() {
        let (model, day) = model()
        model.selection.intent = .copy
        model.toggleSelection(hour(model, day, 19))
        let days = [day.adding(days: -2), day.adding(days: -3), day.adding(days: -4)]
        model.placeSelection(on: days)
        for target in days { #expect(model.allEntries(on: target).map(\.name) == ["Salmon"]) }
        #expect(model.toast?.message.hasPrefix("Copied 1 food to 3 days") == true)
    }

    @Test func aMoveToManyDatesLeavesCopiesOnTheRest() {
        let (model, day) = model()
        model.toggleSelection(hour(model, day, 19))
        let days = [day.adding(days: -3), day.adding(days: -2)]
        model.placeSelection(on: days)
        #expect(model.allEntries(on: day).map(\.name) == ["Soup", "Bread"])
        for target in days { #expect(model.allEntries(on: target).map(\.name) == ["Salmon"]) }
        #expect(model.selection.isEmpty)
    }

    @Test func aFoodDeletedElsewhereLeavesTheSelection() {
        let (model, day) = model()
        let noon = hour(model, day, 12)
        model.toggleSelection(noon)
        model.delete(entries: [noon.entries[0].id])
        #expect(model.selection.ids == [noon.entries[1].id])
    }

    @Test func leavingTheLogLetsGo() {
        let (model, day) = model()
        model.toggleSelection(hour(model, day, 12))
        model.tab = .plan
        #expect(model.selection.isEmpty)
    }

    @Test func aSelectionHoldsTheDayThroughAWhileAway() {
        let (model, day) = model()
        model.toggleSelection(hour(model, day, 12))
        let left = Date()
        model.wentToBackground(at: left)
        model.cameToFront(at: left.addingTimeInterval(AppModel.awayLimit * 2))
        #expect(model.selectedDay == day)
    }

    @Test func deletingTheSelectionUndoes() throws {
        let (model, day) = model()
        model.toggleSelection(hour(model, day, 12))
        model.deleteSelection()
        #expect(model.selection.isEmpty)
        #expect(model.allEntries(on: day).map(\.name) == ["Salmon"])
        model.undo(try #require(model.toast))
        #expect(model.allEntries(on: day).count == 3)
    }

    @Test func shiftSelectsFromTheNearestSelected() {
        let (model, day) = model()
        let foods = model.allEntries(on: day)
        model.toggleSelection(foods[0])
        model.extendSelection(to: foods[2])
        #expect(model.selection.ids.count == 3)
    }

    @Test func aMoveThatEndsAFastSaysSo() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.setTracksMealTiming(true)
        model.acknowledgeFastingScreen()
        let earlier = Date().addingTimeInterval(-20 * 3600)
        model.log([food("Dinner", kcal: 700, at: earlier)])
        model.toast = nil
        model.startFast(goalHours: 16)
        model.toast = nil
        #expect(model.analysis?.fast != nil)
        let snack = food("Lunch", kcal: 500, at: Date().addingTimeInterval(5 * 3600))
        model.log([snack])
        model.toast = nil
        let entry = try #require(model.foodLog.upcoming.first)

        model.toggleSelection(entry)
        model.placeSelection(.starting(Date().addingTimeInterval(-60)), named: "now")

        #expect(model.toast?.message.contains("ended your") == true)
    }
}
