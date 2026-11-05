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

    /// A small food: too little alone to end a fast.
    func bite(_ hour: Int, _ minute: Int, kcal: Double = 30) -> FoodEntry {
        let date = at(hour, minute)
        return FoodEntry(
            date: date, day: day, name: "Bite", amountLabel: "1", nutrients: Nutrients(kcal: kcal, protein: 0, carbs: 0, fat: 0), source: .search,
            updatedAt: date)
    }

    @Test func aClockSetBackLeavesASplitStale() {
        let log = FoodLog([lunch, dinner], now: at(19, 0))
        #expect(log.upcoming.isEmpty)
        #expect(log.isStale(at: at(18, 0)))
        #expect(log.at(at(18, 0)).upcoming.map(\.name) == ["Dinner"])
    }

    @Test func nextMealSkipsADrink() {
        var coffee = dinner
        coffee.date = at(15, 0)
        coffee.nutrients = Nutrients(kcal: 2, protein: 0, carbs: 0, fat: 0)
        let log = FoodLog([lunch, coffee, dinner], now: at(13, 0))
        #expect(log.nextChange == at(15, 0))
        #expect(log.nextMeal(since: at(12, 45)) == at(18, 30))
    }

    @Test func smallFoodsTogetherAreAMeal() {
        let log = FoodLog([bite(18, 30), bite(18, 30)], now: at(13, 0))
        #expect(log.nextMeal(since: at(12, 45)) == at(18, 30))
        #expect(log.later(through: day, since: at(12, 45)).map(\.isMeal) == [false, true])
    }

    @Test func aRunIsAMealFromTheFoodThatMakesItOne() {
        // By 6:30 the milk is only milk; the fast is over once the chocolate has gone in too.
        let log = FoodLog([bite(19, 0), bite(18, 30), bite(19, 10, kcal: 5)], now: at(13, 0))
        #expect(log.nextMeal(since: at(12, 45)) == at(19, 0))
        #expect(log.later(through: day, since: at(12, 45)).map(\.isMeal) == [false, true, true])
    }

    @Test func smallFoodsApartAreNotAMeal() {
        let log = FoodLog([bite(15, 0), bite(18, 30)], now: at(13, 0))
        #expect(log.nextMeal(since: at(12, 45)) == nil)
        #expect(log.later(through: day, since: at(12, 45)).map(\.isMeal) == [false, false])
    }

    @Test func aRunStartsAgainAfterAGap() {
        let log = FoodLog([bite(15, 0), bite(18, 0), bite(18, 5)], now: at(13, 0))
        #expect(log.nextMeal(since: at(12, 45)) == at(18, 5))
        #expect(log.later(through: day, since: at(12, 45)).map(\.isMeal) == [false, false, true])
    }

    @Test func foodJustEatenStartsTheRun() {
        let log = FoodLog([bite(12, 50), bite(13, 20)], now: at(13, 0))
        #expect(log.nextMeal(since: at(12, 45)) == at(13, 20))
        #expect(log.later(through: day, since: nil).map(\.isMeal) == [true])
    }

    @Test func foodFromBeforeTheFastDoesntStartTheRun() {
        // `Fasting.runs` starts counting from the first food after the start.
        let log = FoodLog([bite(12, 50), bite(13, 20)], now: at(13, 0))
        #expect(log.nextMeal(since: at(12, 55)) == nil)
        #expect(log.later(through: day, since: at(12, 55)).map(\.isMeal) == [false])
    }

    @Test func aMealAlreadyEatenDoesntMakeAMintOne() {
        // Lunch is over: a mint after it isn't a second meal, and doesn't end a fast begun since.
        let log = FoodLog([lunch, bite(12, 50, kcal: 5)], now: at(12, 40))
        #expect(log.nextMeal(since: at(12, 35)) == nil)
        #expect(log.later(through: day, since: nil).map(\.isMeal) == [false])
    }

    @Test func smallFoodsAgreeWithTheFastOnceTheyveHappened() {
        // What the fast's own rule says at the moment `nextMeal` named, for the app and with it closed.
        let fast = Fast(start: at(8, 0), goalHours: 16)
        let entries = [bite(18, 30), bite(19, 0)]
        let log = FoodLog(entries, now: at(13, 0))
        #expect(log.nextMeal(since: fast.start) == at(19, 0))
        let before = FoodLog(entries, now: at(18, 59))
        #expect(Fasting.runs([fast], entries: before.eaten, now: at(18, 59)).first?.isRunning == true)
        let after = FoodLog(entries, now: at(19, 0))
        #expect(Fasting.runs([fast], entries: after.eaten, now: at(19, 0)).first?.isRunning == false)
    }

    @Test func foodChainedToTheMealBeforeAFastIsThatMealRunningOn() {
        // Dinner ends at 7, the fast starts there, and tea and a biscuit are planned just after.
        let fast = Fast(start: at(19, 0), goalHours: 16)
        let entries = [bite(19, 0, kcal: 700), bite(19, 30), bite(19, 35)]
        let log = FoodLog(entries, now: at(19, 5))
        #expect(log.nextMeal(since: fast.start) == nil)
        #expect(log.later(through: day, since: fast.start).map(\.isMeal) == [false, false])
        // Which is what the fast says once they've happened: it runs on.
        #expect(Fasting.runs([fast], entries: FoodLog(entries, now: at(19, 36)).eaten, now: at(19, 36)).first?.isRunning == true)
    }

    @Test func aDessertChainedToTheMealBeforeAFastIsThatMealToo() {
        let fast = Fast(start: at(19, 0), goalHours: 16)
        let entries = [bite(19, 0, kcal: 700), bite(19, 30, kcal: 300)]
        #expect(FoodLog(entries, now: at(19, 5)).nextMeal(since: fast.start) == nil)
        #expect(Fasting.runs([fast], entries: FoodLog(entries, now: at(19, 31)).eaten, now: at(19, 31)).first?.isRunning == true)
    }

    @Test func aMealAfterFoodChainedToTheOneBeforeAFastEndsIt() {
        let fast = Fast(start: at(19, 0), goalHours: 16)
        let entries = [bite(19, 0, kcal: 700), bite(19, 30), bite(21, 0, kcal: 600)]
        #expect(FoodLog(entries, now: at(19, 5)).nextMeal(since: fast.start) == at(21, 0))
        #expect(Fasting.runs([fast], entries: FoodLog(entries, now: at(21, 1)).eaten, now: at(21, 1)).first?.isRunning == false)
    }

    @Test func aSmallFoodBeforeAFastDoesntChainTheOnesAfterIt() {
        // No meal before the start for them to run on from, so they're a meal of their own.
        let fast = Fast(start: at(19, 0), goalHours: 16)
        let log = FoodLog([bite(18, 50), bite(19, 30), bite(19, 35)], now: at(19, 5))
        #expect(log.nextMeal(since: fast.start) == at(19, 35))
    }

    @Test func laterFoodStopsAfterTomorrow() {
        var nextWeek = dinner
        nextWeek.date = day.adding(days: 7).at(hour: 12, minute: 0)
        nextWeek.day = day.adding(days: 7)
        let later = FoodLog([dinner, nextWeek], now: at(13, 0)).later(through: day.adding(days: 1), since: nil)
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

    @Test func aComplicationsTimelineGoesOnToTomorrowsFood() {
        // Tomorrow's lunch, planned in the evening, and the Watch app doesn't run tomorrow.
        let tomorrow = day.adding(days: 1)
        let meal = tomorrow.at(hour: 12, minute: 30)
        var written = snapshot(now: at(21, 0))
        written.later = [LaterFood(date: meal, nutrients: Nutrients(kcal: 700, protein: 40, carbs: 70, fat: 20), isMeal: true)]

        let tonight = written.timeline(from: at(21, 0))
        #expect(tonight.dates == [at(21, 0), tomorrow.date()], "it isn't today's food yet")
        #expect(tonight.reload == tomorrow.date().addingTimeInterval(60), "so it's read again past midnight")

        let next = written.timeline(from: tonight.reload)
        #expect(next.dates == [tonight.reload, meal, tomorrow.adding(days: 1).date()])
        #expect(written.shown(at: tomorrow.at(hour: 12, minute: 29)).kcal.eaten == 0)
        #expect(written.shown(at: tomorrow.at(hour: 13, minute: 0)).kcal.eaten == 700)
    }

    @Test func aComplicationsTimelineFindsMidnightTheDayTheClocksChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        // 2027's spring change: a 23-hour day, where 24 hours on is already 1 AM.
        let change = Day(year: 2027, month: 3, day: 14)
        let timeline = snapshot(now: at(13, 0)).timeline(from: change.at(hour: 0, minute: 30, calendar: calendar), calendar: calendar)
        #expect(timeline.dates.last == change.adding(days: 1).date(calendar: calendar))
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

    @Test func smallFoodsLoggedForLaterEndAComplicationsFast() throws {
        let fast = Fast(start: at(13, 0), goalHours: 16)
        var settings = MacroSettings()
        settings.tracksMealTiming = true
        let state = MacroState(
            profile: profile(), settings: settings, entries: [lunch, bite(18, 30), bite(18, 35)], fasts: [fast], today: day, now: at(14, 0))
        let written = WristSnapshot(WristToday(state: state, analysis: MacroAnalyst.analyse(state)))
        #expect(written.shown(at: at(18, 32)).fast(at: at(18, 32)) != nil)
        let after = written.shown(at: at(18, 36))
        #expect(after.fast(at: at(18, 36)) == nil)
        #expect(after.lastMealEnd == at(18, 35))
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

    @Test func aMealJustAfterMidnightStaysOnToday() {
        let tomorrow = day.adding(days: 1)
        let midnight = tomorrow.date()
        let now = midnight.addingTimeInterval(1)
        let settled = LogAgain.settled(copies(at: now, count: 3), now: now)
        #expect(settled.allSatisfy { $0.day == tomorrow })
        #expect(settled.map(\.date) == [0, 0.5, 1].map { midnight.addingTimeInterval($0) })
    }

    @Test func aMealAtMidnightItselfStaysOnToday() {
        let tomorrow = day.adding(days: 1)
        let midnight = tomorrow.date()
        let settled = LogAgain.settled(copies(at: midnight, count: 3), now: midnight)
        #expect(settled.allSatisfy { $0.day == tomorrow })
        #expect(settled.map(\.date) == [midnight, midnight, midnight])
    }

    @Test func aCopyForAnEarlierDayStaysThere() {
        // Copied to today and yesterday at once: the batch ends just ahead of the clock.
        let tomorrow = day.adding(days: 1)
        let now = tomorrow.date().addingTimeInterval(5)
        var earlier = copies(at: day.date().addingTimeInterval(30), count: 1)
        earlier[0].day = day
        let settled = LogAgain.settled(earlier + copies(at: now.addingTimeInterval(25), count: 1), now: now)
        #expect(settled.map(\.day) == [day, tomorrow])
        #expect(settled.last?.date == now)
    }
}
