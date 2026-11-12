import Foundation
import NutritionEngine
import SystemCore
import SystemStore
import Testing

@testable import MacroTrack

/// The Log tab's cards: filling in a past day at the times it was eaten, adding to any meal, and
/// taking foods to another card or hour.
@MainActor
struct MealCardsAppTests {
    func food(_ name: String, kcal: Double, at date: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: name, amountLabel: "1 serving", nutrients: Nutrients(kcal: kcal, protein: 20, carbs: 30, fat: 10), source: .search)
    }

    /// A week to the day before yesterday: oats at 9, soup at noon and salmon at 5.
    func week(_ model: AppModel) {
        var entries: [FoodEntry] = []
        for back in 2...8 {
            let day = model.today.adding(days: -back)
            entries += [
                food("Oats", kcal: 300, at: day.at(hour: 9, minute: 0)), food("Soup", kcal: 400, at: day.at(hour: 12, minute: 0)),
                food("Salmon", kcal: 600, at: day.at(hour: 17, minute: 0)),
            ]
        }
        model.log(entries)
        model.toast = nil
    }

    func model() -> AppModel {
        let model = TestEnvironment().model()
        model.onboard()
        week(model)
        return model
    }

    func held(_ items: [DayItem]) -> Int { items.filter { if case .held = $0 { true } else { false } }.count }

    @Test func yesterdayHasItsUsualMealsWhereTheyGo() {
        let model = model()
        let yesterday = model.today.adding(days: -1)
        model.selectedDay = yesterday
        #expect(held(model.dayItems(on: yesterday)) == 3)
    }

    @Test func aUsualMealLoggedBecomesACardAtItsTime() throws {
        let model = model()
        let yesterday = model.today.adding(days: -1)
        model.selectedDay = yesterday
        let breakfast = try #require(model.catchUp.first)

        model.catchUp(breakfast)

        let items = model.dayItems(on: yesterday)
        #expect(held(items) == 2)
        let meal = try #require(
            items.compactMap { item -> Moment? in
                if case .meal(let meal) = item { meal } else { nil }
            }.first)
        #expect(meal.start == yesterday.at(hour: 9, minute: 0))
    }

    @Test func anHoursSlotAimsTheLoggerAtThatHourOnThatDay() {
        let model = model()
        let yesterday = model.today.adding(days: -1)
        model.selectedDay = yesterday
        let time = yesterday.at(hour: 10, minute: 0)

        model.logOrPlace(at: time)

        #expect(model.loggerTime == time)
        #expect(model.logger == .search)
    }

    @Test func aMealsPlusLandsInThatMealOnAPastDay() throws {
        let model = model()
        let day = model.today.adding(days: -2)
        model.selectedDay = day
        let lunch = try #require(Timeline.moments(model.allEntries(on: day)).first { $0.entries.first?.name == "Soup" })
        let time = DayCards.addTime(to: lunch, now: Date())

        model.log([food("Bread", kcal: 150, at: time)])

        let meals = Timeline.moments(model.allEntries(on: day))
        #expect(meals.count == 3)
        #expect(meals.first { $0.entries.first?.name == "Soup" }?.entries.map(\.name) == ["Soup", "Bread"])
    }

    @Test func pickedOutFoodsGoToAnotherCard() throws {
        let model = model()
        let day = model.today.adding(days: -2)
        model.selectedDay = day
        let meals = Timeline.moments(model.allEntries(on: day))
        let breakfast = try #require(meals.first)
        let lunch = try #require(meals.dropFirst().first)

        model.toggleSelection(breakfast)
        model.logOrPlace(at: DayCards.addTime(to: lunch, now: Date()))

        #expect(model.selection.isEmpty)
        let after = Timeline.moments(model.allEntries(on: day))
        #expect(after.count == 2)
        #expect(after.first?.entries.map(\.name) == ["Soup", "Oats"])
    }

    /// The hub's last rhythm stays on devices and in iCloud. Its sleep used to set the hours; now
    /// they're 7 AM to 8 PM until set by hand, and the file is left as it was.
    @Test func theLogsHoursLeaveTheHubsSleepAloneUntilSetByHand() throws {
        let model = model()
        #expect(model.logHours == 7...20)

        let rhythm = Data(
            #"{"schemaVersion":1,"writtenBy":"hub","writtenAt":1793613600000,"payload":{"wake":360,"bed":1350,"updated":1793613600000}}"#.utf8)
        let url = model.shared.directory.appending(path: "hub/rhythm.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rhythm.write(to: url)
        model.readShared()
        #expect(model.logHours == 7...20)

        model.updateSettings { $0.logFirstHour = 8 }
        #expect(model.logHours == 8...20)
        #expect(try Data(contentsOf: url) == rhythm)
    }

    @Test func theLogsHoursUseTheBedtimeSetHere() {
        let model = model()
        model.updateSettings { $0.doseTimes = [.bedtime: 23 * 60] }
        #expect(model.logHours == 7...22)
    }

    @Test func aWholeMealPickedOutTwiceLetsGo() throws {
        let model = model()
        let meal = try #require(Timeline.moments(model.allEntries(on: model.today.adding(days: -2))).first)
        model.toggleSelection(meal)
        #expect(model.selection.ids == Set(meal.entries.map(\.id)))
        model.toggleSelection(meal)
        #expect(model.selection.isEmpty)
    }
}
