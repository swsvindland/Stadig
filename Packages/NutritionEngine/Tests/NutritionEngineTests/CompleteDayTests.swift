import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// A day counts as logged live when its foods went in by 4 AM the next day. Fixing a food later
/// mustn't undo that: a day that taught the estimate on Monday still does after an edit on Thursday.
struct CompleteDayTests {
    let calendar = Calendar.gregorian(.newYork)
    let day = Day(year: 2027, month: 3, day: 8)
    var today: Day { day.adding(days: 4) }

    func meal(_ hour: Int, kcal: Double, loggedAt: Date? = nil) -> FoodEntry {
        let date = day.at(hour: hour, minute: 0, calendar: calendar)
        return FoodEntry(
            date: date, day: day, name: "Meal", amountLabel: "1", nutrients: Nutrients(kcal: kcal, protein: 40, carbs: 80, fat: 30), source: .search,
            updatedAt: date, loggedAt: loggedAt)
    }

    func usable(_ entries: [FoodEntry]) -> Double? {
        let state = MacroState(
            profile: profile(), settings: MacroSettings(), entries: entries, today: today, now: today.at(hour: 12, minute: 0, calendar: calendar))
        return MacroAnalyst.analyse(state, calendar: calendar).usable[day]
    }

    @Test func aDayLoggedLiveCounts() {
        #expect(usable([meal(8, kcal: 800), meal(13, kcal: 800), meal(19, kcal: 800)]) == 2400)
    }

    @Test func aDayFilledInDaysLaterDoesNot() {
        let late = today.at(hour: 9, minute: 0, calendar: calendar)
        let entries = [meal(8, kcal: 800), meal(13, kcal: 800), meal(19, kcal: 800)].map { entry in
            var entry = entry
            entry.updatedAt = late
            return entry
        }
        #expect(usable(entries) == nil)
    }

    @Test func editingAFoodDaysLaterKeepsTheDay() {
        let thursday = today.at(hour: 9, minute: 0, calendar: calendar)
        var entries = [meal(8, kcal: 800), meal(13, kcal: 800), meal(19, kcal: 800)]
        entries[1] = entries[1].edited(at: thursday, calendar: calendar) { $0.nutrients.kcal = 850 }
        #expect(entries[1].updatedAt == thursday)
        #expect(usable(entries) == 2450)
    }

    @Test func aMondayUndoOnThursdayKeepsTheDay() {
        // Undoing a delete saves the same entries again, stamped Thursday.
        let thursday = today.at(hour: 9, minute: 0, calendar: calendar)
        let entries = [meal(8, kcal: 800), meal(13, kcal: 800), meal(19, kcal: 800)].map { $0.edited(at: thursday, calendar: calendar) }
        #expect(usable(entries) == 2400)
    }
}

struct FoodEntryEditTests {
    let calendar = Calendar.gregorian(.newYork)

    func entry(at date: Date, updatedAt: Date) -> FoodEntry {
        FoodEntry(
            date: date, name: "Oats", amountLabel: "1", nutrients: Nutrients(kcal: 300, protein: 10, carbs: 50, fat: 5), source: .search,
            updatedAt: updatedAt)
    }

    @Test func aSecondEditKeepsTheFirstLogged() {
        let first = Day(year: 2027, month: 3, day: 8).at(hour: 8, minute: 0, calendar: calendar)
        let once = entry(at: first, updatedAt: first).edited(at: first.addingTimeInterval(3600), calendar: calendar)
        let twice = once.edited(at: first.addingTimeInterval(7200), calendar: calendar)
        #expect(once.firstLogged == first)
        #expect(twice.firstLogged == first)
        #expect(twice.updatedAt == first.addingTimeInterval(7200))
    }

    @Test func theStampAlwaysMovesForward() {
        let first = Day(year: 2027, month: 3, day: 8).at(hour: 8, minute: 0, calendar: calendar)
        // A clock behind the device that wrote it: the store would ignore a save stamped earlier.
        let edited = entry(at: first, updatedAt: first).edited(at: first.addingTimeInterval(-60), calendar: calendar)
        #expect(edited.updatedAt == first.addingTimeInterval(0.001))
    }

    @Test func theDayMovesOnlyWithTheDate() {
        let tokyo = Calendar.gregorian(TimeZone(identifier: "Asia/Tokyo") ?? .gmt)
        // Logged late on the 8th in New York: the 9th in Tokyo.
        let date = Day(year: 2027, month: 3, day: 8).at(hour: 22, minute: 0, calendar: calendar)
        let logged = FoodEntry(
            date: date, day: Day(date, calendar: calendar), name: "Oats", amountLabel: "1",
            nutrients: Nutrients(kcal: 300, protein: 10, carbs: 50, fat: 5),
            source: .search, updatedAt: date)
        #expect(logged.edited(at: date, calendar: tokyo) { $0.nutrients.kcal = 320 }.day == logged.day)
        let later = date.addingTimeInterval(86_400)
        #expect(logged.edited(at: date, calendar: tokyo) { $0.date = later }.day == Day(later, calendar: tokyo))
    }

    @Test func anEntryFromBeforeItWasKeptDecodesAndReadsItsLastEdit() throws {
        let date = Day(year: 2027, month: 3, day: 8).at(hour: 8, minute: 0, calendar: calendar)
        let encoder = JSONEncoder()
        var object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(entry(at: date, updatedAt: date))) as? [String: Any])
        object["loggedAt"] = nil
        let decoded = try JSONDecoder().decode(FoodEntry.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.loggedAt == nil)
        #expect(decoded.firstLogged == date)
    }

    @Test func aCopyIsANewEntry() {
        let date = Day(year: 2027, month: 3, day: 8).at(hour: 8, minute: 0, calendar: calendar)
        let edited = entry(at: date, updatedAt: date).edited(at: date.addingTimeInterval(60), calendar: calendar)
        #expect(LogAgain.copy(edited, to: date.addingTimeInterval(86_400)).loggedAt == nil)
    }
}

struct IntakeTests {
    let food = FoodEntry(name: "Oats", amountLabel: "1", nutrients: Nutrients(kcal: 300, protein: 10, carbs: 50, fat: 5), source: .search)

    func dose(kcal: Double) -> SupplementLog {
        let facts = SupplementFacts(
            id: "custom:fish", name: "Fish oil", ingredients: [SupplementIngredient(name: "Calories", amount: kcal, unit: "kcal")], source: .custom)
        return SupplementLog(supplement: Supplement(facts: facts), doseID: nil, date: Date(), count: 1)
    }

    @Test func dosesCountOnADayWithFood() {
        #expect(Intake.total([food], doses: [dose(kcal: 10)]).kcal == 310)
    }

    @Test func dosesAloneAreNothingEaten() {
        #expect(Intake.total([], doses: [dose(kcal: 10)]) == .zero)
    }
}
