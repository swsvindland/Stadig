import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// Food with a date ahead of now is an ordinary entry that counts for nothing until its time.
struct FoodLogTests {
    let calendar = Calendar.current
    let day = Day(year: 2026, month: 6, day: 15)

    /// A 6:30 PM dinner, with lunch already eaten.
    var lunch: FoodEntry {
        let date = day.at(hour: 12, minute: 30)
        return FoodEntry(
            date: date, day: day, name: "Lunch", amountLabel: "1", nutrients: Nutrients(kcal: 600, protein: 40, carbs: 60, fat: 20), source: .search,
            updatedAt: date)
    }
    var dinner: FoodEntry {
        let date = day.at(hour: 18, minute: 30)
        return FoodEntry(
            date: date, day: day, name: "Dinner", amountLabel: "1", nutrients: Nutrients(kcal: 800, protein: 50, carbs: 70, fat: 30), source: .search,
            updatedAt: day.at(hour: 12, minute: 35))
    }

    func at(_ hour: Int, _ minute: Int) -> Date { day.at(hour: hour, minute: minute) }

    func state(now: Date, fasts: [Fast] = []) -> MacroState {
        MacroState(profile: profile(), settings: MacroSettings(), entries: [lunch, dinner], fasts: fasts, today: day, now: now)
    }

    @Test func itSplitsAtTheMoment() {
        let log = FoodLog([lunch, dinner], now: at(18, 29))
        #expect(log.eaten.map(\.name) == ["Lunch"])
        #expect(log.upcoming.map(\.name) == ["Dinner"])
        #expect(log.all.count == 2)
        #expect(log.nextChange == at(18, 30))
        #expect(log.isUpcoming(dinner))
    }

    @Test func aFoodCountsFromItsMinute() {
        let log = FoodLog([lunch, dinner], now: at(18, 30))
        #expect(log.eaten.map(\.name) == ["Lunch", "Dinner"])
        #expect(log.nextChange == nil)
    }

    @Test func aFoodLoggedThisInstantHasHappened() {
        // The store rounds to the millisecond: this came back 0.4 ms ahead of the clock.
        let now = at(12, 0)
        var rounded = lunch
        rounded.date = now.addingTimeInterval(0.0004)
        for log in [FoodLog([rounded], now: now), FoodLog(sorted: [rounded], now: now)] {
            #expect(log.eaten.count == 1)
            #expect(log.upcoming.isEmpty)
            #expect(!log.isUpcoming(rounded))
            #expect(log.nextChange == nil)
        }
        let state = MacroState(profile: profile(), settings: MacroSettings(), entries: [rounded], today: day, now: now)
        #expect(MacroAnalyst.analyse(state).todayIntake.kcal == 600)
    }

    @Test func insertingKeepsDateOrderWithinTheAllowance() {
        let now = at(12, 0)
        var first = lunch
        first.id = UUID()
        first.date = now
        var second = lunch
        second.id = UUID()
        second.date = now.addingTimeInterval(0.0004)
        var third = lunch
        third.id = UUID()
        third.date = now.addingTimeInterval(0.0002)
        let log = FoodLog(sorted: [first, second], now: now).inserting([third], now: now)
        #expect(log.all.map(\.id) == [first.id, third.id, second.id])
    }

    @Test func aMomentLaterIsStillLater() {
        let now = at(12, 0)
        var soon = lunch
        soon.date = now.addingTimeInterval(0.01)
        #expect(FoodLog([soon], now: now).upcoming.count == 1)
    }

    @Test func staleOnceAFoodsTimeHasPassed() {
        let log = FoodLog([lunch, dinner], now: at(18, 29))
        #expect(!log.isStale(at: at(18, 29)))
        #expect(log.isStale(at: at(18, 31)))
        #expect(log.at(at(18, 31)).upcoming.isEmpty)
        #expect(!FoodLog([lunch], now: at(13, 0)).isStale(at: at(23, 0)))
    }

    @Test func nextChangeIsTheEarliestWhateverTheOrder() {
        var snack = dinner
        snack.date = at(15, 0)
        #expect(FoodLog([dinner, snack], now: at(13, 0)).nextChange == at(15, 0))
    }

    @Test func theRingCountsDinnerAtItsTime() {
        #expect(MacroAnalyst.analyse(state(now: at(18, 29))).todayIntake.kcal == 600)
        #expect(MacroAnalyst.analyse(state(now: at(18, 31))).todayIntake.kcal == 1400)
    }

    @Test func aFastRunsUntilDinnersTime() {
        let fast = Fast(start: at(13, 0), goalHours: 16, updatedAt: at(13, 0))
        let before = MacroAnalyst.analyse(state(now: at(18, 29), fasts: [fast]))
        #expect(before.fast != nil)
        let after = MacroAnalyst.analyse(state(now: at(18, 31), fasts: [fast]))
        #expect(after.fast == nil)
    }

    @Test func theWristFollowsTheSameMinute() {
        func eaten(_ now: Date) -> Double {
            let state = state(now: now)
            return WristToday(state: state, analysis: MacroAnalyst.analyse(state)).kcal.eaten
        }
        #expect(eaten(at(18, 29)) == 600)
        #expect(eaten(at(18, 31)) == 1400)
    }

    @Test func whatsPublishedWaitsForTheDayToHappen() {
        let planned = day.adding(days: -2)
        let foods = [8, 13, 19].map { hour in
            FoodEntry(
                date: planned.at(hour: hour, minute: 0), day: planned, name: "Planned", amountLabel: "1",
                nutrients: Nutrients(kcal: 800, protein: 40, carbs: 80, fat: 30), source: .search, updatedAt: planned.adding(days: -3).date())
        }
        func published(today: Day, now: Date) -> Bool {
            let state = MacroState(profile: profile(), settings: MacroSettings(), entries: foods, today: today, now: now)
            return MacroAnalyst.nutritionSummary(state, MacroAnalyst.analyse(state)).days.contains { $0.day == planned && $0.logged }
        }
        #expect(!published(today: planned, now: planned.at(hour: 7, minute: 0)))
        #expect(published(today: day, now: at(9, 0)))
    }

    @Test func aWholePlannedDayCountsOnceItsPassed() {
        // Logged days ahead, skipped or not: when the day's over, it's a day like any other.
        let planned = day.adding(days: -2)
        let foods = [8, 13, 19].map { hour in
            FoodEntry(
                date: planned.at(hour: hour, minute: 0), day: planned, name: "Planned", amountLabel: "1",
                nutrients: Nutrients(kcal: 800, protein: 40, carbs: 80, fat: 30), source: .search, updatedAt: planned.adding(days: -3).date())
        }
        let during = MacroState(profile: profile(), settings: MacroSettings(), entries: foods, today: planned, now: planned.at(hour: 7, minute: 0))
        #expect(MacroAnalyst.analyse(during).intakeByDay[planned] == nil)
        let after = MacroState(profile: profile(), settings: MacroSettings(), entries: foods, today: day, now: at(9, 0))
        #expect(MacroAnalyst.analyse(after).usable[planned] == 2400)
    }

    @Test func aSortedLogSplitsTheSameWay() {
        let sorted = FoodLog(sorted: [lunch, dinner], now: at(18, 29))
        #expect(sorted.eaten.map(\.name) == FoodLog([lunch, dinner], now: at(18, 29)).eaten.map(\.name))
        #expect(sorted.upcoming.map(\.name) == ["Dinner"])
        #expect(sorted.at(at(19, 0)).upcoming.isEmpty)
        #expect(FoodLog(sorted: [], now: at(12, 0)).all.isEmpty)
    }

    @Test func insertingKeepsDateOrder() {
        var snack = lunch
        snack.id = UUID()
        snack.date = at(15, 0)
        var late = lunch
        late.id = UUID()
        late.date = at(21, 0)
        let log = FoodLog(sorted: [lunch, dinner], now: at(16, 0)).inserting([snack, late], now: at(16, 0))
        #expect(log.all.map(\.date) == [at(12, 30), at(15, 0), at(18, 30), at(21, 0)])
        #expect(log.eaten.count == 2)
        #expect(log.upcoming.count == 2)
    }

    @Test func insertingIntoAnUnsortedLogKeepsEverything() {
        let log = FoodLog([dinner], now: at(19, 0)).inserting([lunch], now: at(19, 0))
        #expect(log.eaten.count == 2)
    }

    // MARK: later, outside the app

    @Test func nextMealSkipsADrink() {
        var coffee = dinner
        coffee.date = at(15, 0)
        coffee.nutrients = Nutrients(kcal: 2, protein: 0, carbs: 0, fat: 0)
        let log = FoodLog([lunch, coffee, dinner], now: at(13, 0))
        #expect(log.nextChange == at(15, 0))
        #expect(log.nextMeal == at(18, 30))
    }

    @Test func laterFoodStopsAfterTomorrow() {
        var nextWeek = dinner
        nextWeek.date = day.adding(days: 7).at(hour: 12, minute: 0)
        nextWeek.day = day.adding(days: 7)
        let later = FoodLog([dinner, nextWeek], now: at(13, 0)).later(through: day.adding(days: 1))
        #expect(later.map(\.date) == [at(18, 30)])
        #expect(later.first?.isMeal == true)
    }

    func snapshot(now: Date, fast: Fast? = nil) -> WristSnapshot {
        let state = state(now: now, fasts: fast.map { [$0] } ?? [])
        return WristSnapshot(WristToday(state: state, analysis: MacroAnalyst.analyse(state)))
    }

    @Test func aComplicationCountsLaterFoodAtItsTime() {
        let written = snapshot(now: at(13, 0))
        #expect(written.later?.count == 1)
        #expect(written.shown(at: at(18, 29)).kcal.eaten == 600)
        let after = written.shown(at: at(18, 31))
        #expect(after.kcal.eaten == 1400)
        #expect(after.protein.eaten == 90)
        #expect(after.later?.isEmpty == true)
        #expect(written.laterDates(after: at(13, 0), before: at(23, 0)) == [at(18, 30)])
    }

    @Test func aComplicationsNextDayStartsFromNothing() {
        let written = snapshot(now: at(13, 0))
        #expect(written.shown(at: day.adding(days: 1).at(hour: 1, minute: 0)).kcal.eaten == 0)
    }

    @Test func aMealLoggedForLaterEndsAComplicationsFast() {
        var written = snapshot(now: at(13, 0))
        written.fastStart = at(13, 0)
        written.fastGoalHours = 16
        #expect(written.shown(at: at(18, 29)).fast(at: at(18, 29)) != nil)
        let after = written.shown(at: at(18, 31))
        #expect(after.fast(at: at(18, 31)) == nil)
        #expect(after.lastMealEnd == at(18, 30))
    }

    @Test func aSnapshotWithLaterFoodSurvivesAndAnOlderOneReads() throws {
        let written = snapshot(now: at(13, 0))
        #expect(WristSnapshot.decoded(try written.encoded())?.later == written.later)
        var older = written
        older.later = nil
        #expect(WristSnapshot.decoded(try older.encoded())?.later == nil)
    }

    // MARK: settled

    func copies(at date: Date, count: Int) -> [FoodEntry] {
        (0..<count).map { i in
            FoodEntry(
                date: date.addingTimeInterval(Double(i)), name: "Food \(i)", amountLabel: "1",
                nutrients: Nutrients(kcal: 100, protein: 1, carbs: 1, fat: 1), source: .copied)
        }
    }

    @Test func aMealStampedJustAheadEndsAtNow() {
        let now = at(12, 0)
        let settled = LogAgain.settled(copies(at: now, count: 4), now: now)
        #expect(settled.map(\.date) == [-3, -2, -1, 0].map { now.addingTimeInterval($0) })
    }

    @Test func aMealForLaterStaysLater() {
        let now = at(12, 0)
        let later = copies(at: at(19, 0), count: 3)
        #expect(LogAgain.settled(later, now: now) == later)
    }

    @Test func aMealInThePastStaysPut() {
        let earlier = copies(at: at(8, 0), count: 3)
        #expect(LogAgain.settled(earlier, now: at(12, 0)) == earlier)
    }

    @Test func settlingOverMidnightFollowsTheDay() {
        let midnight = day.adding(days: 1).date()
        let settled = LogAgain.settled(copies(at: midnight.addingTimeInterval(-1), count: 3), now: midnight.addingTimeInterval(-1))
        #expect(settled.allSatisfy { $0.day == day })
    }
}
