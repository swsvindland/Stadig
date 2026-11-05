import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

extension TimeZone {
    static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt
}

extension Calendar {
    /// Gregorian in a time zone: how these tests build fixed dates.
    static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

struct DayOrderTests {
    let day = Day(year: 2027, month: 6, day: 15)

    func food(_ name: String, at hour: Int, kcal: Double, protein: Double) -> FoodEntry {
        FoodEntry(
            date: day.at(hour: hour, minute: 0, calendar: .gregorian(.newYork)), day: day, name: name, amountLabel: "1",
            nutrients: Nutrients(kcal: kcal, protein: protein, carbs: 1, fat: 1), source: .search)
    }

    @Test func aListHasTheMostFirstAndTiesInDateOrder() throws {
        let foods = [
            food("Oats", at: 8, kcal: 300, protein: 10), food("Pasta", at: 19, kcal: 800, protein: 20), food("Soup", at: 12, kcal: 300, protein: 30),
        ]
        #expect(try #require(DayOrder.calories.listed(foods)).map(\.name) == ["Pasta", "Oats", "Soup"])
        #expect(try #require(DayOrder.protein.listed(foods)).map(\.name) == ["Soup", "Pasta", "Oats"])
    }

    @Test func timeAndAnEmptyDayKeepTheHours() {
        #expect(DayOrder.time.listed([food("Oats", at: 8, kcal: 300, protein: 10)]) == nil)
        #expect(DayOrder.fat.listed([]) == nil)
    }
}

struct DayHoursTests {
    let calendar = Calendar.gregorian(.newYork)
    let day = Day(year: 2027, month: 6, day: 15)

    func food(_ hour: Int, _ minute: Int = 0, on day: Day? = nil) -> FoodEntry {
        let on = day ?? self.day
        let date = on.at(hour: hour, minute: minute, calendar: calendar)
        return FoodEntry(
            date: date, day: on, name: "Food \(hour)", amountLabel: "1", nutrients: Nutrients(kcal: 100, protein: 1, carbs: 1, fat: 1),
            source: .search)
    }

    @Test func aDayHasEveryHourInOrder() {
        let groups = DayHours.groups(on: day, entries: [], calendar: calendar)
        #expect(groups.map(\.hour) == Array(0...23))
        #expect(groups.first?.start == day.date(calendar: calendar))
        #expect(groups.last?.end == day.adding(days: 1).date(calendar: calendar))
    }

    @Test func foodsLandInTheirHoursInOrder() {
        let groups = DayHours.groups(on: day, entries: [food(12, 40), food(12, 10), food(8)], calendar: calendar)
        #expect(groups[8].entries.count == 1)
        #expect(
            groups[12].entries.map(\.date) == [day.at(hour: 12, minute: 10, calendar: calendar), day.at(hour: 12, minute: 40, calendar: calendar)])
        #expect(groups.filter { !$0.entries.isEmpty }.count == 2)
    }

    @Test func theClocksGoingForwardLeaveOutAnHour() {
        // New York, 2027-03-14: 2 AM doesn't happen.
        let groups = DayHours.groups(on: Day(year: 2027, month: 3, day: 14), entries: [], calendar: calendar)
        #expect(groups.count == 23)
        #expect(groups.map(\.hour) == [0, 1] + Array(3...23))
    }

    @Test func theClocksGoingBackRepeatAnHour() {
        // New York, 2027-11-07: 1 AM happens twice, and the two stay apart.
        let groups = DayHours.groups(on: Day(year: 2027, month: 11, day: 7), entries: [], calendar: calendar)
        #expect(groups.count == 25)
        #expect(groups.map(\.hour) == [0, 1, 1] + Array(2...23))
        #expect(Set(groups.map(\.id)).count == 25)
    }

    @Test func aHalfHourChangeStillLinesUpWithTheClock() {
        // Lord Howe, 2027-04-04: the clocks go back half an hour.
        let lordHowe = Calendar.gregorian(TimeZone(identifier: "Australia/Lord_Howe") ?? .gmt)
        let groups = DayHours.groups(on: Day(year: 2027, month: 4, day: 4), entries: [], calendar: lordHowe)
        #expect(groups.last?.end == Day(year: 2027, month: 4, day: 5).date(calendar: lordHowe))
        for group in groups.dropFirst(3) { #expect(lordHowe.component(.minute, from: group.start) == 0) }
    }

    @Test func aFoodOutsideTheDayStaysOnTheList() {
        let tokyo = Calendar.gregorian(TimeZone(identifier: "Asia/Tokyo") ?? .gmt)
        // Logged at 8 PM on the 15th in New York, on the 15th's list, read in Tokyo.
        let groups = DayHours.groups(on: day, entries: [food(20)], calendar: tokyo)
        #expect(groups.flatMap(\.entries).count == 1)
    }

    @Test func todayOpensOnTheHourItIs() {
        let groups = DayHours.groups(on: day, entries: [food(8)], calendar: calendar)
        let now = day.at(hour: 15, minute: 20, calendar: calendar)
        #expect(DayHours.opening(groups, now: now)?.hour == 15)
    }

    @Test func anotherDayOpensOnItsFirstFood() {
        let groups = DayHours.groups(on: day, entries: [food(13), food(9)], calendar: calendar)
        #expect(DayHours.opening(groups, now: day.adding(days: 2).date(calendar: calendar))?.hour == 9)
    }

    @Test func anEmptyDayOpensInTheMorning() {
        let groups = DayHours.groups(on: day, entries: [], calendar: calendar)
        #expect(DayHours.opening(groups, now: day.adding(days: -2).date(calendar: calendar))?.hour == DayHours.emptyDayHour)
    }

    @Test func addingToTheHourItIsLogsNow() throws {
        let groups = DayHours.groups(on: day, entries: [food(15)], calendar: calendar)
        let now = day.at(hour: 15, minute: 20, calendar: calendar)
        #expect(DayHours.addTime(groups[15], now: now) == now)
    }

    @Test func addingToAnHourWithFoodJoinsIt() {
        let groups = DayHours.groups(on: day, entries: [food(12, 30)], calendar: calendar)
        let now = day.at(hour: 20, minute: 0, calendar: calendar)
        #expect(DayHours.addTime(groups[12], now: now) == day.at(hour: 12, minute: 31, calendar: calendar))
    }

    @Test func addingAfterAnHoursLastMinuteStaysInTheHour() {
        let groups = DayHours.groups(on: day, entries: [food(12, 59)], calendar: calendar)
        let now = day.at(hour: 20, minute: 0, calendar: calendar)
        #expect(DayHours.addTime(groups[12], now: now) == day.at(hour: 12, minute: 59, calendar: calendar))
    }

    @Test func addingToAnEmptyHourIsItsTop() {
        let groups = DayHours.groups(on: day, entries: [], calendar: calendar)
        #expect(DayHours.addTime(groups[9], now: day.at(hour: 20, minute: 0, calendar: calendar)) == day.at(hour: 9, minute: 0, calendar: calendar))
    }

    @Test func addingBesideAFoodFromBeforeTheDayStaysOnTheDay() throws {
        // Logged at 7 AM in Tokyo on this day, which is the evening before in New York.
        var abroad = food(0)
        abroad.date = day.at(hour: 7, minute: 0, calendar: .gregorian(TimeZone(identifier: "Asia/Tokyo") ?? .gmt))
        let groups = DayHours.groups(on: day, entries: [abroad], calendar: calendar)
        #expect(groups[0].entries.map(\.id) == [abroad.id])
        let time = DayHours.addTime(groups[0], now: day.at(hour: 20, minute: 0, calendar: calendar))
        #expect(time == groups[0].start)
        #expect(Day(time, calendar: calendar) == day)
    }

    @Test func addingBesideAFoodFromAfterTheDayStaysOnTheDay() throws {
        // Logged at 11 PM in Los Angeles on this day, which is the next morning in New York.
        var abroad = food(23)
        abroad.date = day.at(hour: 23, minute: 0, calendar: .gregorian(TimeZone(identifier: "America/Los_Angeles") ?? .gmt))
        let groups = DayHours.groups(on: day, entries: [abroad], calendar: calendar)
        #expect(groups[23].entries.map(\.id) == [abroad.id])
        let time = DayHours.addTime(groups[23], now: day.at(hour: 20, minute: 0, calendar: calendar))
        #expect(Day(time, calendar: calendar) == day)
    }
}

struct PlacingTests {
    let calendar = Calendar.gregorian(.newYork)
    let day = Day(year: 2027, month: 6, day: 15)

    func food(_ hour: Int, _ minute: Int = 0, on day: Day? = nil) -> FoodEntry {
        let on = day ?? self.day
        return FoodEntry(
            date: on.at(hour: hour, minute: minute, calendar: calendar), day: on, name: "Food", amountLabel: "1",
            nutrients: Nutrients(kcal: 100, protein: 1, carbs: 1, fat: 1), source: .search)
    }

    @Test func startingKeepsTheSpacing() {
        let target = day.adding(days: 1).at(hour: 18, minute: 0, calendar: calendar)
        let dates = Placing.dates(for: [food(12, 0), food(12, 10), food(12, 30)], .starting(target), calendar: calendar)
        #expect(dates == [target, target.addingTimeInterval(600), target.addingTimeInterval(1800)])
    }

    @Test func theOrderGivenIsKept() {
        let target = day.adding(days: 1).at(hour: 18, minute: 0, calendar: calendar)
        let dates = Placing.dates(for: [food(12, 30), food(12, 0)], .starting(target), calendar: calendar)
        #expect(dates == [target.addingTimeInterval(1800), target])
    }

    @Test func aMealPastTheEndOfTheDayGoesInOrderAMinuteApart() {
        let target = day.adding(days: 1).at(hour: 23, minute: 50, calendar: calendar)
        let dates = Placing.dates(for: [food(8), food(12), food(19)], .starting(target), calendar: calendar)
        #expect(dates == [0, 60, 120].map { target.addingTimeInterval($0) })
        #expect(dates.allSatisfy { Day($0, calendar: calendar) == day.adding(days: 1) })
    }

    @Test func aMealTooLateForEvenThatMovesBackToFit() {
        let target = day.adding(days: 1).at(hour: 23, minute: 59, calendar: calendar)
        let dates = Placing.dates(for: [food(8), food(12), food(19)], .starting(target), calendar: calendar)
        #expect(dates == [57, 58, 59].map { day.adding(days: 1).at(hour: 23, minute: $0, calendar: calendar) })
    }

    @Test func sameTimesKeepEachFoodsTimeOfDay() {
        let target = day.adding(days: 3)
        let dates = Placing.dates(for: [food(8), food(19, 30)], .sameTimes(on: target), calendar: calendar)
        #expect(dates == [target.at(hour: 8, minute: 0, calendar: calendar), target.at(hour: 19, minute: 30, calendar: calendar)])
    }

    @Test func foodsFromSeveralDaysStayOnTheTargetDay() {
        let target = day.adding(days: 5).at(hour: 20, minute: 0, calendar: calendar)
        let dates = Placing.dates(for: [food(8), food(8, on: day.adding(days: 1))], .starting(target), calendar: calendar)
        #expect(dates.allSatisfy { Day($0, calendar: calendar) == day.adding(days: 5) })
    }

    @Test func toNowEndsAtNowInOrder() {
        let now = day.adding(days: 1).at(hour: 18, minute: 0, calendar: calendar)
        let dates = Placing.dates(for: [food(19), food(8), food(12)], .now(now), calendar: calendar)
        #expect(dates == [0, -2, -1].map { now.addingTimeInterval($0) })
    }

    @Test func nothingToPlaceIsNothing() {
        #expect(Placing.dates(for: [], .sameTimes(on: day), calendar: calendar).isEmpty)
    }
}
