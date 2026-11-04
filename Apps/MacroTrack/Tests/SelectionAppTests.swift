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

    /// A wide pane stays open beside the selection bar and every row's swipe, so what it opened can
    /// change under it. Saving the copy it opened with would undo a move or bring back a delete.
    @Test func aMovedFoodIsNoLongerTheOneOpened() throws {
        let (model, day) = model()
        let opened = try #require(model.allEntries(on: day).first)
        #expect(model.current(opened) == opened)

        model.select(opened, intent: .move)
        model.placeSelection(.sameTimes(on: model.today.adding(days: 1)), named: "tomorrow")

        #expect(model.current(opened) == nil)
    }

    @Test func aDeletedFoodIsNoLongerTheOneOpened() throws {
        let (model, day) = model()
        let opened = try #require(model.allEntries(on: day).first)

        model.delete(entries: [opened.id])

        #expect(model.current(opened) == nil)
    }

    /// Changed where it stands, from another device, it's the same food with the new numbers.
    @Test func aFoodChangedInPlaceIsReadAgain() throws {
        let (model, day) = model()
        let opened = try #require(model.allEntries(on: day).first)
        var changed = opened
        changed.nutrients = Nutrients(kcal: 999, protein: 1, carbs: 1, fat: 1)

        model.update(changed)

        #expect(model.current(opened)?.nutrients.kcal == 999)
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

    @Test func undoAfterAMoveToManyDatesTakesTheCopiesToo() throws {
        let (model, day) = model()
        let salmon = hour(model, day, 19).entries[0]
        model.toggleSelection(salmon)
        let days = [day.adding(days: -2), day.adding(days: -3), day.adding(days: -4)]
        model.placeSelection(on: days)
        let toast = try #require(model.toast)
        #expect(toast.message.hasPrefix("Moved 1 food to 3 days"))

        model.undo(toast)

        #expect(model.allEntries(on: day).map(\.name) == ["Soup", "Bread", "Salmon"])
        #expect(model.allEntries(on: day).last?.date == salmon.date)
        for target in days { #expect(model.allEntries(on: target).isEmpty) }
        #expect(model.toast == nil)
    }

    @Test func aMoveToOneDateHasNothingElseToTakeBack() {
        let (model, day) = model()
        model.log([food("Old", at: day.at(hour: 8, minute: 0))])
        model.toggleSelection(hour(model, day, 19))
        model.placeSelection(on: [day.adding(days: -2)])
        #expect(model.toast?.undo.isEmpty == true, "not the Undo of the toast before it")
    }

    /// The copy lands in the running fast, so it's the move as a whole that ended it.
    @Test func aCopyLeftByAMoveThatEndsAFastSaysSo() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.setTracksMealTiming(true)
        model.acknowledgeFastingScreen()
        let now = Date()
        model.log([food("Dinner", kcal: 700, at: now.addingTimeInterval(-20 * 3600))])
        model.toast = nil
        model.startFast(goalHours: 16)
        model.toast = nil
        // Earlier today, however early today is.
        let start = Calendar.current.startOfDay(for: now)
        let time = start.addingTimeInterval(now.timeIntervalSince(start) / 2)
        let entry = food("Lunch", kcal: 500, at: model.today.adding(days: -3).at(sameTimeAs: time))
        model.log([entry])
        model.toast = nil

        model.toggleSelection(entry)
        model.placeSelection(on: [model.today.adding(days: -2), model.today])

        let toast = try #require(model.toast)
        #expect(toast.message.contains("ended your"), "\(toast.message)")
        model.undo(toast)
        let fast = try #require(model.fasts.last)
        #expect(model.fastRun(fast)?.isRunning == true)
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
