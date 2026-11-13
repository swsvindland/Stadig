import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// The week desk: a week's meals by day, each day against its own target, the week's average day,
/// and what moving a meal to another day does.
struct WeekDeskTests {
    let calendar = Calendar.gregorian(.newYork)
    let english = Locale(identifier: "en_US")
    /// Monday 14 June 2027. "Now" is Wednesday at 3:05 PM.
    let monday = Day(year: 2027, month: 6, day: 14)
    var wednesday: Day { monday.adding(days: 2) }
    var now: Date { wednesday.at(hour: 15, minute: 5, calendar: calendar) }

    func food(
        _ name: String, _ kcal: Double, on day: Day, at hour: Int, _ minute: Int = 0, protein: Double = 20, id: UUID = UUID()
    ) -> FoodEntry {
        let date = day.at(hour: hour, minute: minute, calendar: calendar)
        return FoodEntry(
            id: id, date: date, day: day, name: name, amountLabel: "1 serving",
            nutrients: Nutrients(kcal: kcal, protein: protein, carbs: kcal / 8, fat: kcal / 30), source: .search, updatedAt: date)
    }

    func targets(_ kcal: Double = 2200, protein: Double = 165) -> [Day: DailyTargets] {
        Dictionary(
            uniqueKeysWithValues: WeekDesk.days(of: monday).map {
                ($0, DailyTargets(mode: .phase, kcal: kcal, protein: protein, carbs: 240, fat: 65, note: ""))
            })
    }

    func board(_ log: WeekLog) -> WeekBoard { WeekDesk.board(log, week: wednesday, now: now, calendar: calendar) }

    @Test func aWeekRunsFromMondayToSunday() {
        let days = WeekDesk.days(of: monday.adding(days: 4))
        #expect(days.first == monday)
        #expect(days.count == 7)
        #expect(days.last?.weekday == .sunday)
        #expect(WeekDesk.days(of: monday.adding(days: 6)).first == monday, "Sunday is the week's last day, not the next one's first")
    }

    /// Food logged together is one meal, named for its two biggest foods, or for the saved meal it is.
    @Test func mealsAreMomentsNamedForTheirFoods() throws {
        let lunch = [food("Chicken, roasted", 420, on: monday, at: 12, 40), food("Rice, white, cooked", 180, on: monday, at: 12, 41)]
        let supper = [
            food("Yogurt", 150, on: monday, at: 21, 15), food("Granola", 160, on: monday, at: 21, 16),
            food("Blueberries", 30, on: monday, at: 21, 17),
        ]
        let saved = SavedMeal(name: "Lunch box", from: lunch)
        let day = try #require(board(WeekLog(entries: supper + lunch, saved: [saved])).day(monday))

        #expect(day.meals.map(\.name) == ["Lunch box", "Yogurt, granola"])
        #expect(day.meals.map(\.kind) == [.eaten, .eaten])
        #expect(day.meals[1].markers == ["🥛", "🥣", "🫐"], "markers in the order eaten")
        #expect(day.total.kcal == 940)
        let burger = [food("Big Mac", 550, on: monday, at: 12), food("Fries", 300, on: monday, at: 12, 1)]
        #expect(WeekDesk.name(of: burger, saved: []) == "Big Mac, fries", "a name that isn't a word keeps its capitals")
    }

    @Test func markersKeepTheBiggestFoodsOnceEach() {
        let foods = [("Coffee", 5.0), ("Toast", 160), ("Butter", 100), ("Egg", 140), ("Egg, scrambled", 140), ("Banana", 105), ("Mystery", 300)]
        #expect(WeekDesk.markers(foods.map { (name: $0.0, kcal: $0.1) }) == ["🍞", "🧈", "🥚", "🍌"])
        #expect(WeekDesk.markers([(name: "Mystery", kcal: 300)]) == [FoodMarker.unknown])
        #expect(WeekDesk.markers([]).isEmpty)
    }

    /// Today: what's eaten is above the now line, and what's logged for later and the plan's dishes
    /// still to come are below it, lighter. A dish whose time has passed unlogged isn't counted.
    @Test func todaySplitsAtNow() throws {
        let lunch = food("Lunch box", 599, on: wednesday, at: 12, 35)
        let dinner = food("Turkey chilli", 801, on: wednesday, at: 19)
        let planned = [
            WeekPlanned(
                id: "snack", time: wednesday.at(hour: 15, minute: 30, calendar: calendar), name: "Yogurt bowl", foods: ["Yogurt"],
                nutrients: Nutrients(kcal: 413, protein: 30, carbs: 40, fat: 12)),
            WeekPlanned(
                id: "breakfast", time: wednesday.at(hour: 8, minute: 0, calendar: calendar), name: "Oats", foods: ["Oats"],
                nutrients: Nutrients(kcal: 400, protein: 20, carbs: 60, fat: 8)),
        ]
        let day = try #require(board(WeekLog(entries: [lunch, dinner], planned: planned, targets: targets())).day(wednesday))

        #expect(day.timing == .today)
        #expect(day.meals.map(\.name) == ["Lunch box", "Yogurt bowl", "Turkey chilli"])
        #expect(day.meals.map(\.kind) == [.eaten, .planned, .later])
        #expect(day.eatenMeals == 1)
        #expect(day.eaten.kcal == 599)
        #expect(day.ahead.kcal == 1214)
        #expect(day.standing == .left(1601), "today says what's left of what's eaten")
        #expect(!day.meals[1].canMove && day.meals[2].canMove, "only the log's meals move")
    }

    @Test func eachDayStandsAgainstItsOwnTarget() throws {
        var targets = targets()
        targets[monday.adding(days: 1)] = DailyTargets(mode: .dietBreak, kcal: 2750, protein: 165, carbs: 300, fat: 80, note: "")
        let board = board(
            WeekLog(
                entries: [
                    food("Pasta", 2115, on: monday, at: 19), food("Pizza", 2531, on: monday.adding(days: 1), at: 19),
                    food("Stew", 2047, on: monday.adding(days: 4), at: 19),
                ], targets: targets))

        #expect(board.day(monday)?.standing == .under(85))
        #expect(board.day(monday.adding(days: 1))?.standing == .under(219), "a diet break's day by its own target")
        #expect(board.day(monday.adding(days: 4))?.standing == .under(153), "a day ahead by what's logged for it")
        #expect(board.day(monday.adding(days: 3))?.standing == nil, "nothing on it")
        #expect(board.target == 2200, "the line is the target most days have")
    }

    /// The average day is the days eaten and the days planned. Today counts once the rest of it is
    /// planned; a morning's breakfast alone would drag the week down.
    @Test func theWeeksAverageIsTheDaysThatSaySomething() throws {
        let log = WeekLog(
            entries: [
                food("Pasta", 2100, on: monday, at: 19, protein: 170), food("Pizza", 2500, on: monday.adding(days: 1), at: 19, protein: 160),
                food("Toast", 400, on: wednesday, at: 8, protein: 20),
            ], targets: targets())
        let morning = try #require(board(log).average)
        #expect(morning.kcal == 2300)
        #expect(morning.protein == 165)
        #expect(morning.logged == 2 && morning.planned == 0)
        #expect(morning.kcalTarget == 2200)

        var planned = log
        planned.entries.append(food("Stew", 1500, on: wednesday, at: 19, protein: 100))
        planned.entries.append(food("Stew", 2000, on: monday.adding(days: 5), at: 19, protein: 100))
        let week = try #require(board(planned).average)
        #expect(week.logged == 2 && week.planned == 2)
        #expect(week.kcal == (2100 + 2500 + 1900 + 2000) / 4)

        #expect(board(WeekLog(entries: [])).average == nil)
        #expect(board(WeekLog(entries: [])).isEmpty)
    }

    @Test func theScaleHasRoomForMaintenanceAndTheBiggestDay() {
        #expect(WeekDesk.scaleTop(maintenance: 2750, target: 2200, biggest: 2531) == 2850)
        #expect(WeekDesk.scaleTop(maintenance: 2750, target: 2200, biggest: 3400) == 3550)
        #expect(WeekDesk.scaleTop(maintenance: nil, target: nil, biggest: 0) == 2500)
    }

    /// Held over another day, a meal moves at its own time of day, and both days and the week say
    /// what that does, before anything is saved.
    @Test func movingAMealSaysWhatChanges() throws {
        let saturday = monday.adding(days: 5)
        let thursday = monday.adding(days: 3)
        let pasta = food("Beef pasta", 771, on: thursday, at: 19, protein: 62)
        let log = WeekLog(
            entries: [
                food("Brunch", 717, on: saturday, at: 10, 30), food("Yogurt", 413, on: saturday, at: 14, 30),
                food("Skyr", 332, on: saturday, at: 21), food("Lunch", 599, on: thursday, at: 12, 30),
                food("Shake", 557, on: thursday, at: 15), pasta,
            ], targets: targets(), maintenance: 2750)
        let before = board(log)
        let meal = try #require(before.day(thursday)?.meals.last)
        let move = try #require(WeekDesk.move(meal, to: saturday, in: log, week: wednesday, now: now, calendar: calendar, locale: english))

        #expect(move.after.day(saturday)?.total.kcal == 2233)
        #expect(move.after.day(thursday)?.total.kcal == 1156)
        let landed = try #require(move.after.day(saturday)?.meals.first(where: move.holdsMoved))
        #expect(landed.start == saturday.at(hour: 19, minute: 0, calendar: calendar))
        #expect(landed.kind == .later)
        #expect(
            move.changes
                == "Saturday goes from 738 under to 33 over. Tomorrow comes down to 1,156, 1,044 under. The week still averages 1,695.")
        #expect(WeekDesk.move(meal, to: thursday, in: log, week: wednesday, now: now, calendar: calendar) == nil, "the day it's on")
    }

    @Test func movingTheOnlyMealOffADayLeavesItEmpty() throws {
        let tuesday = monday.adding(days: 1)
        let log = WeekLog(entries: [food("Pasta", 2100, on: monday, at: 19), food("Pizza", 2500, on: tuesday, at: 12)], targets: targets())
        let meal = try #require(board(log).day(tuesday)?.meals.first)
        let move = try #require(WeekDesk.move(meal, to: monday, in: log, week: wednesday, now: now, calendar: calendar, locale: english))

        #expect(move.after.day(monday)?.meals.count == 2)
        #expect(move.after.average?.kcal == 4600, "one day of it now")
        #expect(move.changes == "Monday goes from 100 under to 2,400 over. Yesterday has nothing logged. The week averages 4,600 instead of 2,300.")
    }

    /// A day that hasn't food logged on it yet, and a week without targets (the assessment): the
    /// numbers alone.
    @Test func movingWithoutTargetsSaysTheNumbers() throws {
        let log = WeekLog(entries: [food("Pasta", 900, on: monday, at: 19), food("Soup", 500, on: monday, at: 12)])
        let meal = try #require(board(log).day(monday)?.meals.last)
        let move = try #require(
            WeekDesk.move(meal, to: monday.adding(days: 6), in: log, week: wednesday, now: now, calendar: calendar, locale: english))
        #expect(move.changes == "Sunday comes up to 900. Monday comes down from 1,400 to 500. The week averages 700 instead of 1,400.")
        #expect(move.after.day(monday.adding(days: 6))?.meals.first?.kind == .later, "a day ahead hasn't happened")
    }

    @Test func aDishOnThePlanStaysWhereItIs() throws {
        let dish = WeekPlanned(
            id: "d", time: monday.adding(days: 4).at(hour: 19, minute: 0, calendar: calendar), name: "Traybake", foods: ["Chicken"],
            nutrients: Nutrients(kcal: 913, protein: 70, carbs: 60, fat: 40))
        let log = WeekLog(entries: [], planned: [dish])
        let meal = try #require(board(log).day(monday.adding(days: 4))?.meals.first)
        #expect(meal.kind == .planned && meal.markers == ["🍗"])
        #expect(WeekDesk.move(meal, to: monday.adding(days: 5), in: log, week: wednesday, now: now, calendar: calendar) == nil)
    }

    @Test func theWeightIsTheTrendOverFourWeeks() throws {
        let weighIns = (0..<40).map { offset in
            WeighIn(date: monday.adding(days: offset - 33).at(hour: 7, minute: 0, calendar: calendar), kg: 84 - Double(offset) * 0.15)
        }
        let sunday = monday.adding(days: 6)
        let trend = Weight.trend(weighIns, through: sunday)
        let weight = try #require(WeekDesk.weight(trend, through: wednesday))
        #expect(weight.points.count == 28)
        #expect(weight.points.last?.day == wednesday)
        #expect(abs(weight.trend - (trend[wednesday] ?? 0)) < 0.0001)
        #expect(weight.weekly.map { $0 < -0.9 && $0 > -1.2 } ?? false, "about 0.15 kg a day")
        #expect(WeekDesk.weight(.empty, through: wednesday) == nil)
    }
}
