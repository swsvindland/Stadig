import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// When meals happen: the bands, which moments are meals, the 4 AM day, overnight fasts only over
/// fully logged days, and the week's one piece of advice.
@Suite("Meal timing")
struct MealTimingTests {
    /// A fixed zone, so the clock change below is New York's.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    let calendar = Self.calendar
    let monday = Day(year: 2026, month: 3, day: 2)

    func at(_ day: Day, _ hour: Int, _ minute: Int = 0) -> Date { day.at(hour: hour, minute: minute, calendar: calendar) }

    func food(_ date: Date, kcal: Double = 600, protein: Double = 30) -> FoodEntry {
        FoodEntry(
            date: date, day: Day(date, calendar: calendar), name: "Food", amountLabel: "1",
            nutrients: Nutrients(kcal: kcal, protein: protein, carbs: kcal / 8, fat: kcal / 30), source: .search, updatedAt: date)
    }

    /// Meals at these hours on each day.
    func eating(_ days: [Day], at hours: [Double], kcal: Double = 600, protein: Double = 30) -> [FoodEntry] {
        days.flatMap { day in
            hours.map { food(at(day, Int($0), Int(($0 - $0.rounded(.down)) * 60)), kcal: kcal, protein: protein) }
        }
    }

    func bedtime(_ day: Day) -> Date { at(day, 22, 30) }

    @Test("gaps fall in bands: under 2 hours, 2–3, 3–5 and over 5")
    func bands() {
        #expect(GapBand.of(119 * 60) == .close)
        #expect(GapBand.of(2 * 3600) == .short)
        #expect(GapBand.of(3 * 3600) == .spaced)
        #expect(GapBand.of(5 * 3600) == .spaced)
        #expect(GapBand.of(5 * 3600 + 60) == .long)
        #expect(MealTiming.hours(10.5 * 3600) == "10½ h" && MealTiming.hours(13 * 3600) == "13 h" && MealTiming.hours(12.9 * 3600) == "13 h")
    }

    @Test("black coffee and a splash of milk aren't meals; foods within 45 minutes are one")
    func meals() {
        let entries = [
            food(at(monday, 7), kcal: 5, protein: 0), food(at(monday, 7, 10), kcal: 40, protein: 2),
            food(at(monday, 9)), food(at(monday, 9, 30), kcal: 120), food(at(monday, 13)),
        ]
        let meals = MealTiming.meals(entries)
        #expect(meals.count == 2)
        #expect(meals[0].start == at(monday, 9) && meals[0].end == at(monday, 9, 30))
        #expect(MealTiming.lastMeal(before: at(monday, 12), entries: entries)?.start == at(monday, 9))
        #expect(MealTiming.lastMeal(before: at(monday, 8), entries: entries) == nil)
    }

    @Test("a snack after midnight belongs to the evening before; 4 AM starts the day")
    func eatingDay() {
        let tuesday = monday.adding(days: 1)
        #expect(MealTiming.eatingDay(of: at(tuesday, 0, 30), calendar: calendar) == monday)
        #expect(MealTiming.eatingDay(of: at(tuesday, 3, 59), calendar: calendar) == monday)
        #expect(MealTiming.eatingDay(of: at(tuesday, 4), calendar: calendar) == tuesday)
        // The midnight snack ends Monday's eating, so Tuesday's overnight fast runs from it.
        let entries = eating([monday, tuesday], at: [8, 12.5, 19]) + [food(at(tuesday, 0, 30), kcal: 300)]
        let days = MealTiming.days(
            entries, in: DayRange(monday, tuesday), known: [monday, tuesday], bedtime: bedtime, proteinPerMeal: nil, calendar: calendar)
        #expect(days[0].meals.count == 4)
        #expect(days[1].overnight?.from == at(tuesday, 0, 30) && days[1].overnight?.duration == 7.5 * 3600.0)
        #expect(days[0].lastMealToBed == -2 * 3600.0)
    }

    @Test("a day's gaps, overnight fast, eating window and protein meals")
    func day() throws {
        let tuesday = monday.adding(days: 1)
        let entries =
            eating([monday], at: [8, 12, 19.5]) + [food(at(tuesday, 7, 30))] + [food(at(tuesday, 9), kcal: 200, protein: 5)]
            + [food(at(tuesday, 12, 30), protein: 40)] + [food(at(tuesday, 18, 45), protein: 45)]
        let days = MealTiming.days(
            entries, in: DayRange(tuesday, tuesday), known: [monday, tuesday], bedtime: bedtime, proteinPerMeal: 35, calendar: calendar)
        let day = try #require(days.first)
        #expect(day.meals.count == 4)
        #expect(day.gaps.map(\.band) == [.close, .spaced, .long])
        #expect(day.overnight?.duration == 12 * 3600.0)
        #expect(day.window == 11.25 * 3600.0)
        #expect(day.lastMealToBed == 3.75 * 3600.0)
        #expect(day.proteinMeals == 2)
    }

    @Test("an overnight fast needs both days logged in full; an unknown day isn't read at all")
    func trust() {
        let tuesday = monday.adding(days: 1)
        let entries = eating([monday, tuesday], at: [8, 13, 19])
        let partialMonday = MealTiming.days(
            entries, in: DayRange(tuesday, tuesday), known: [tuesday], bedtime: bedtime, proteinPerMeal: nil, calendar: calendar)
        #expect(partialMonday.first?.overnight == nil && partialMonday.first?.gaps.count == 2)
        let unknownTuesday = MealTiming.days(
            entries, in: DayRange(monday, tuesday), known: [monday], bedtime: bedtime, proteinPerMeal: nil, calendar: calendar)
        #expect(unknownTuesday.map(\.day) == [monday])
        // A fasted day between, logged as such, keeps the fast before Wednesday's breakfast readable.
        let wednesday = tuesday.adding(days: 1)
        let fasted = eating([monday, wednesday], at: [8, 13, 19])
        let across = MealTiming.days(
            fasted, in: DayRange(wednesday, wednesday), known: [monday, tuesday, wednesday], bedtime: bedtime, proteinPerMeal: nil,
            calendar: calendar)
        #expect(across.first?.overnight?.duration == 37 * 3600.0)
    }

    @Test("the overnight fast across the spring clock change is the hours that passed")
    func clockChange() {
        // New York's clocks went forward at 2 AM on 8 March 2026: dinner at 8 PM to breakfast at 8 AM is 11 hours.
        let saturday = Day(year: 2026, month: 3, day: 7)
        let sunday = saturday.adding(days: 1)
        let entries = eating([saturday], at: [20]) + eating([sunday], at: [8])
        let days = MealTiming.days(
            entries, in: DayRange(sunday, sunday), known: [saturday, sunday], bedtime: bedtime, proteinPerMeal: nil, calendar: calendar)
        #expect(days.first?.overnight?.duration == 11 * 3600.0)
        // And back in November, 13.
        let november = Day(year: 2026, month: 10, day: 31)
        let back = eating([november], at: [20]) + eating([november.adding(days: 1)], at: [8])
        let autumn = MealTiming.days(
            back, in: DayRange(november.adding(days: 1), november.adding(days: 1)), known: [november, november.adding(days: 1)],
            bedtime: bedtime, proteinPerMeal: nil, calendar: calendar)
        #expect(autumn.first?.overnight?.duration == 13 * 3600.0)
    }

    func report(_ entries: [FoodEntry], known: Set<Day>? = nil, phase: PhaseKind? = .maintenance) -> MealTimingReport {
        let today = monday.adding(days: 7)
        let week = Set(DayRange(monday.adding(days: -1), today).days)
        return MealTiming.report(
            entries, today: today, known: known ?? week, bedtime: bedtime, phase: phase, referenceKg: 80, calendar: calendar)
    }

    var week: [Day] { (0..<7).map { monday.adding(days: $0) } }

    @Test("grazing comes first: most gaps under 2 hours")
    func grazing() throws {
        let r = report(eating(week, at: [8, 9.5, 11, 13, 14.5, 18.5]))
        #expect(r.hasEnough && r.days.count == 7)
        #expect(r.gapCounts[.close] == 21 && r.gapCount == 35)
        #expect(try #require(r.mealsPerDay) == 6)
        #expect(r.advice?.kind == .grazing)
    }

    @Test("meals 3–5 hours apart, 12½ hours overnight and done 3 hours before bed: nothing to change")
    func spaced() {
        let r = report(eating(week + [monday.adding(days: -1)], at: [8, 12, 16, 19.5]))
        #expect(r.share(.spaced) == 1)
        #expect(r.typicalOvernight == 12.5 * 3600.0)
        #expect(r.typicalWindow == 11.5 * 3600.0 && r.typicalLastMealToBed == 3 * 3600.0)
        #expect(r.advice == nil)
        #expect(r.proteinPerMeal == nil)
    }

    @Test("building muscle, two big meals a day falls short of protein meals; outside a building phase it's fine")
    func proteinMeals() {
        let entries = eating(week + [monday.adding(days: -1)], at: [11, 18], kcal: 1200, protein: 60)
        let building = report(entries, phase: .leanBulk)
        #expect(building.proteinPerMeal == 30)
        #expect(building.proteinMealsPerDay == 2)
        #expect(building.advice?.kind == .proteinMeals)
        #expect(report(entries, phase: .cut).advice == nil)
    }

    @Test("a short overnight fast, then a late last meal, get a word")
    func overnightAndBed() {
        let short = report(eating(week + [monday.adding(days: -1)], at: [7, 11, 15, 21.5]))
        #expect(short.advice?.kind == .shortOvernight)
        #expect(short.advice?.title == "Overnight fast about 9½ h")
        let late = report(eating(week + [monday.adding(days: -1)], at: [10, 14, 17.5, 21]))
        #expect(late.typicalOvernight == 13 * 3600.0)
        #expect(late.advice?.kind == .lateLastMeal)
    }

    @Test("partly logged days say nothing, and under three trusted days the week waits")
    func notEnough() {
        let entries = eating(week, at: [8, 9, 10, 11])
        let known: Set<Day> = [monday, monday.adding(days: 1)]
        let r = report(entries, known: known)
        #expect(r.days.count == 2 && !r.hasEnough && r.advice == nil)
    }
}
