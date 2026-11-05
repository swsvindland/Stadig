import Foundation
import SystemCore
import Testing

@testable import HubEngine

@Suite("Hybrid weeks")
struct HybridTests {
    let utc = TimeZone(identifier: "UTC")!
    /// A Monday.
    let monday = Day(year: 2026, month: 11, day: 2)
    func at(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    /// An office day: an hour at home, the drive, six hours in, the drive, an hour at home.
    @Test func theCommuteFallsBetweenHomeAndTheOffice() throws {
        let pattern = HybridWeek.standard.pattern(anchor: monday, commute: 30)
        let tuesday = try #require(pattern.spans(on: monday.adding(days: 1)))
        let times = tuesday.sorted { $0.start < $1.start }.map { [$0.start, $0.end] }
        #expect(times == [[at(7, 30), at(8, 30)], [at(8, 30), at(9)], [at(9), at(15)], [at(15), at(15, 30)], [at(15, 30), at(16, 30)]])
        #expect(tuesday.filter { $0.kind == .commute }.count == 2)
    }

    @Test func aHomeDayHasNoCommute() throws {
        let pattern = HybridWeek.standard.pattern(anchor: monday, commute: 30)
        let thursday = try #require(pattern.spans(on: monday.adding(days: 3)))
        #expect(thursday.map(\.kind) == [.home])
    }

    @Test func eightHoursEveryDay() {
        #expect(HybridWeek.standard.weeklyMinutes == 40 * 60)
        #expect(ScheduleSummary.weeklyMinutes(HybridWeek.standard.pattern(anchor: monday, commute: 45)) == 40 * 60)
    }

    @Test func itSaysEachPieceOfTheDay() {
        let lines = ScheduleSummary.lines(HybridWeek.standard.pattern(anchor: monday))
        #expect(lines.first == "Mon to Wed: Home 8 AM to 9 AM, office 9 AM to 3 PM, home 3 PM to 4 PM")
        #expect(lines.contains("Thu to Fri: Home 9 AM to 5 PM"))
        #expect(lines.last == "40 hr a week")
    }

    /// A commute that changes after setup moves the hours at home, and survives opening the editor.
    @Test func itComesBackForEditing() throws {
        var week = HybridWeek.standard
        week.homeBefore = 120
        week.homeAfter = 0
        week.days = [.office, .home, .office, .off, .office, .off, .off]
        let opened = try #require(HybridWeek(week.pattern(anchor: monday, commute: 45)))
        #expect(opened == week)
        #expect(SchedulePreset.matching(week.pattern(anchor: monday, commute: 45)) == .hybrid)
    }

    @Test func aPlainWeekIsntOne() {
        #expect(HybridWeek(SchedulePreset.nineToFive.pattern(anchor: monday)) == nil)
        #expect(SchedulePreset.matching(SchedulePreset.nineToFive.pattern(anchor: monday)) == .nineToFive)
    }

    /// The plan treats hours at home as work, and the day's free time is what's left around them.
    @Test func thePlanFitsAroundIt() {
        let rhythm = Rhythm(pattern: HybridWeek.standard.pattern(anchor: monday, commute: 30), wake: at(6), bed: at(22, 30), clearEvenings: 0)
        let inputs = HubInputs(rhythm: rhythm, today: monday, now: monday.at(hour: 6, minute: 0, timeZone: utc), timeZone: utc)
        let day = HubPlanner.day(on: monday, inputs)
        #expect(day.items.filter { $0.kind == .work }.map(\.minutes).reduce(0, +) == 8 * 60)
        #expect(day.items.filter { $0.kind == .commute }.map(\.minutes).reduce(0, +) == 60)
        #expect(day.items.contains { $0.title == "Work at home" })
        #expect(day.items.contains { $0.title == "Office" })
    }

    @Test func readsTheExampleInWords() throws {
        let sentence = "3 days in the office, 2 days at home. The office is 6 hours, with an hour before and an hour after at home"
        let draft = try #require(ScheduleReader.read(sentence, anchor: monday))
        let week = try #require(HybridWeek(draft.pattern))
        #expect(week.days == [.office, .office, .office, .home, .home, .off, .off])
        #expect(week.officeEnd - week.officeStart == 6 * 60)
        #expect(week.homeBefore == 60)
        #expect(week.homeAfter == 60)
    }

    /// The bug this replaced: "8 hours" read as a plain day, and nothing else in the sentence mattered.
    @Test func eightHoursDoesntHideTheRest() throws {
        let sentence = "I work 8 hours a day, Tuesday and Thursday from home, the rest in the office for 6 hours with two hours at home before"
        let draft = try #require(ScheduleReader.read(sentence, anchor: monday))
        let week = try #require(HybridWeek(draft.pattern))
        #expect(week.days == [.office, .home, .office, .home, .office, .off, .off])
        #expect(week.officeEnd - week.officeStart == 6 * 60)
        #expect(week.homeBefore == 120)
        #expect(week.homeAfter == 0)
    }

    @Test func clockHoursAndNamedDays() throws {
        let draft = try #require(
            ScheduleReader.read("Monday, Wednesday and Friday in the office 10am to 4pm, Tuesday and Thursday at home", anchor: monday))
        let week = try #require(HybridWeek(draft.pattern))
        #expect(week.days == [.office, .home, .office, .home, .office, .off, .off])
        #expect(week.officeStart == at(10))
        #expect(week.officeEnd == at(16))
        #expect(week.homeBefore + week.homeAfter == 120)
    }

    @Test func tooLittleGoesToTheModel() {
        #expect(ScheduleReader.read("I'm hybrid", anchor: monday) == nil)
    }

    @Test func aModelCantPutAnImpossibleWeekOnScreen() {
        var week = HybridWeek.standard
        week.officeEnd = week.officeStart
        #expect(ScheduleReader.draft(week, anchor: monday) == nil)
        week = .standard
        week.days = Array(repeating: .off, count: 7)
        #expect(ScheduleReader.draft(week, anchor: monday) == nil)
    }
}

@Suite("Meals reaching the hub")
struct HubMealTests {
    let utc = TimeZone(identifier: "UTC")!
    let monday = Day(year: 2026, month: 11, day: 2)
    var now: Date { monday.at(hour: 18, minute: 0, timeZone: utc) }

    func inputs(meals: MealRhythm?, macro: AppSummary? = nil) -> HubInputs {
        HubInputs(
            rhythm: Rhythm(pattern: SchedulePreset.nothingFixed.pattern(anchor: monday)), macro: macro, meals: meals, today: monday, now: now,
            timeZone: utc)
    }

    @Test func whatWasEatenShowsWithNoUsualTimes() {
        let day = HubPlanner.day(on: monday, inputs(meals: MealRhythm(usual: [], day: monday, eaten: [.morning, .midday], updated: now)))
        let meals = day.items.filter { $0.kind == .meal }
        #expect(meals.map(\.part) == [.morning, .midday])
        #expect(meals.filter(\.done).count == 2)
    }

    @Test func anUnusualMealSitsBesideTheUsualOnes() {
        let day = HubPlanner.day(on: monday, inputs(meals: MealRhythm(usual: [.midday], day: monday, eaten: [.midday, .night], updated: now)))
        #expect(day.items.filter { $0.kind == .meal }.count == 2)
    }

    @Test func aDaysEatenMealsStayOnThatDay() {
        let day = HubPlanner.day(on: monday.adding(days: 1), inputs(meals: MealRhythm(usual: [], day: monday, eaten: [.morning], updated: now)))
        #expect(day.items.isEmpty)
    }

    @Test func saysWhatsMissing() {
        #expect(RhythmSummary.lines(inputs(meals: nil)).isEmpty)
        let stale = RhythmSummary.lines(inputs(meals: nil, macro: AppSummary(app: .macroTrack, updated: now)))
        #expect(stale.first?.value.contains("Update Stadig Macro") == true)
        let early = RhythmSummary.lines(inputs(meals: MealRhythm(usual: [], day: monday, eaten: [], updated: now)))
        #expect(early.first?.value.contains("few days") == true)
    }
}
