import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// Catching up a day that wasn't logged as it happened: the times this person usually eats and
/// what they last ate then, and Log Again, saved meals and "Same as yesterday" ranked for the time
/// being logged at rather than the clock.
@Suite("Usual meals")
struct UsualMealTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    let calendar = Self.calendar
    /// A Thursday, three weeks into the log.
    let today = Day(year: 2026, month: 3, day: 26)
    var yesterday: Day { today.adding(days: -1) }

    func at(_ day: Day, _ hour: Int, _ minute: Int = 0) -> Date { day.at(hour: hour, minute: minute, calendar: calendar) }

    func food(_ name: String, _ date: Date, kcal: Double = 300) -> FoodEntry {
        FoodEntry(
            date: date, day: Day(date, calendar: calendar), name: name, foodID: "usda:\(name.lowercased())", amountLabel: "1 serving",
            nutrients: Nutrients(kcal: kcal, protein: kcal / 10, carbs: kcal / 8, fat: kcal / 30), source: .search, updatedAt: date)
    }

    /// Three weeks to today, yesterday left empty: breakfast around 8 (7:40 to 8:20), lunch around
    /// 12:30 (11:50 to 1:10), almonds at 3:30 on four days a week, dinner at 7, black coffee at 10
    /// every day and a late snack once a week. Lunch is a sandwich, and on the last few days a salad.
    func weeks(through last: Day? = nil) -> [FoodEntry] {
        var entries: [FoodEntry] = []
        for back in 0..<21 {
            let day = (last ?? today).adding(days: -back)
            guard day != yesterday else { continue }
            let wobble = [-20, -10, 0, 10, 20, 0, -10][back % 7]
            entries += [food("Oats", at(day, 8, 0).addingTimeInterval(Double(wobble) * 60)), food("Milk", at(day, 8, 2), kcal: 90)]
            entries.append(food("Coffee", at(day, 10), kcal: 5))
            let lunch = at(day, 12, 30).addingTimeInterval(Double(wobble * 2) * 60)
            entries += back < 4 ? [food("Salad", lunch), food("Chicken", lunch.addingTimeInterval(60))] : [food("Sandwich", lunch)]
            if back % 7 < 4 { entries.append(food("Almonds", at(day, 15, 30), kcal: 170)) }
            entries += [food("Salmon", at(day, 19)), food("Potato", at(day, 19, 3), kcal: 200)]
            if back % 7 == 5 { entries.append(food("Ice cream", at(day, 22, 15), kcal: 250)) }
        }
        return entries
    }

    @Test("the usual times are where meals are on a quarter of the days or more, each with the latest meal eaten then")
    func usualTimes() {
        let usual = UsualMeals.on(yesterday, entries: weeks(), today: today, calendar: calendar)
        // Coffee isn't a meal, and ice cream once a week isn't usual.
        #expect(usual.map(\.time) == [at(yesterday, 8), at(yesterday, 12, 30), at(yesterday, 15, 30), at(yesterday, 19)])
        #expect(usual.map(\.days) == [20, 20, 11, 20])
        #expect(usual.allSatisfy { !$0.logged })
        // Today's lunch is the latest: the salad, not the sandwich of the weeks before.
        #expect(usual[1].latest.entries.map(\.name) == ["Salad", "Chicken"])
        #expect(Day(usual[1].latest.start, calendar: calendar) == today)
        #expect(usual[2].latest.entries.map(\.name) == ["Almonds"])
        #expect(usual[3].latest.nutrients.kcal == 500)
    }

    @Test("a day with a meal within the hour of a usual time has it logged; the rest are still to catch up")
    func logged() {
        let lunch = [food("Burrito", at(yesterday, 13, 20), kcal: 700)]
        let usual = UsualMeals.on(yesterday, entries: weeks() + lunch, today: today, calendar: calendar)
        #expect(usual.map(\.logged) == [false, true, false, false])
        // What it ate isn't learned from: the day being caught up is left out.
        #expect(usual[1].days == 20 && usual[1].latest.entries.map(\.name) == ["Salad", "Chicken"])
        // Coffee alone doesn't count as breakfast.
        let coffee = [food("Coffee", at(yesterday, 8, 5), kcal: 5)]
        #expect(!UsualMeals.on(yesterday, entries: weeks() + coffee, today: today, calendar: calendar)[0].logged)
    }

    @Test("lunch at noon and snacks at 2 and 4 stay three times, not one long lunch")
    func closeTogether() {
        var entries: [FoodEntry] = []
        for back in 0..<14 where back != 1 {
            let day = today.adding(days: -back)
            entries += [food("Wrap", at(day, 12)), food("Yogurt", at(day, 14), kcal: 150), food("Bar", at(day, 16), kcal: 200)]
        }
        let usual = UsualMeals.on(yesterday, entries: entries, today: today, calendar: calendar)
        #expect(usual.map(\.time) == [at(yesterday, 12), at(yesterday, 14), at(yesterday, 16)])
        #expect(usual.map { $0.latest.entries.map(\.name) } == [["Wrap"], ["Yogurt"], ["Bar"]])
    }

    @Test("a snack either side of midnight is one usual time around midnight, not noon")
    func aroundMidnight() {
        var entries: [FoodEntry] = []
        for back in 2..<16 {
            let day = today.adding(days: -back)
            entries.append(back.isMultiple(of: 2) ? food("Toast", at(day, 23, 40)) : food("Toast", at(day, 0, 20)))
        }
        let usual = UsualMeals.on(yesterday, entries: entries, today: today, calendar: calendar)
        #expect(usual.count == 1)
        let minutes = calendar.dateComponents([.hour, .minute], from: usual[0].time)
        #expect(minutes.hour == 0 && minutes.minute == 0)
    }

    @Test("a new log has no usual times until a time comes up on two days")
    func newLog() {
        #expect(UsualMeals.on(yesterday, entries: [], today: today, calendar: calendar).isEmpty)
        let once = [food("Oats", at(today, 8))]
        #expect(UsualMeals.on(yesterday, entries: once, today: today, calendar: calendar).isEmpty)
        let twice = once + [food("Oats", at(today.adding(days: -3), 8, 20))]
        #expect(UsualMeals.on(yesterday, entries: twice, today: today, calendar: calendar).map(\.time) == [at(yesterday, 8, 10)])
        // Over four weeks ago is forgotten.
        let old = [food("Oats", at(today.adding(days: -40), 8)), food("Oats", at(today.adding(days: -41), 8))]
        #expect(UsualMeals.on(yesterday, entries: old, today: today, calendar: calendar).isEmpty)
    }

    @Test("Log again ranks for the time being logged at, with days ago counted from now")
    func logAgainAtATime() {
        let entries = weeks()
        let nine = at(today, 21)
        // At 9 PM, dinner; for yesterday's lunch, lunch.
        let dinner = Set(LogAgain.rank(entries, now: nine, calendar: calendar).prefix(2).map(\.template.name))
        #expect(dinner == ["Salmon", "Potato"])
        let noon = LogAgain.rank(entries, now: nine, at: at(yesterday, 12, 30), calendar: calendar)
        #expect(["Salad", "Chicken", "Sandwich"].contains(noon.first?.template.name ?? ""))
        #expect(!noon.prefix(3).contains { $0.template.name == "Salmon" || $0.template.name == "Potato" })
        // Unchanged when the time is now.
        #expect(LogAgain.rank(entries, now: nine, at: nine, calendar: calendar) == LogAgain.rank(entries, now: nine, calendar: calendar))
    }

    @Test("Log again keeps one order for foods with the same score, so a list doesn't reshuffle between calls")
    func logAgainTies() {
        // Eaten at the same moment, so every one scores the same.
        let entries = (10..<30).map { food("Food \($0)", at(today, 12)) }
        let ids = LogAgain.rank(entries, now: at(today, 13), calendar: calendar).map(\.id)
        #expect(ids.count == 12)
        #expect(ids == ids.sorted())
    }

    @Test("saved meals rank for the time being logged at, and one eaten around then that day isn't usual again")
    func mealsAtATime() {
        let entries = weeks()
        let lunch = SavedMeal(name: "Sandwich", from: [food("Sandwich", at(today.adding(days: -10), 12, 30))])
        let dinner = SavedMeal(name: "Salmon dinner", from: [food("Salmon", at(today, 19)), food("Potato", at(today, 19, 3))])
        let nine = at(today, 21)
        #expect(SavedMeals.rank([lunch, dinner], entries: entries, now: nine, calendar: calendar).map(\.meal.name) == ["Salmon dinner", "Sandwich"])
        let noon = SavedMeals.rank([lunch, dinner], entries: entries, now: nine, at: at(yesterday, 12, 30), calendar: calendar)
        #expect(noon.map(\.meal.name) == ["Sandwich", "Salmon dinner"])
        #expect(noon[0].usualNow)
        // Logged for yesterday's lunch, it's eaten then.
        let logged = entries + lunch.entries(at: at(yesterday, 12, 40))
        #expect(!SavedMeals.rank([lunch], entries: logged, now: nine, at: at(yesterday, 12, 30), calendar: calendar)[0].usualNow)
    }

    @Test("same as usual for a time on a past day: the latest other day's, today's included, until that day has a meal then")
    func usualAtATime() {
        let entries = weeks()
        let usual = LogAgain.usual(at: at(yesterday, 12, 30), entries: entries, today: today, calendar: calendar)
        #expect(usual?.entries.map(\.name) == ["Salad", "Chicken"])
        #expect(Day(usual?.start ?? .distantPast, calendar: calendar) == today)
        // For today, only the days before it, as "Same as yesterday" always was.
        let now = LogAgain.usual(at: at(today, 12, 30), entries: entries.filter { $0.day != today }, today: today, calendar: calendar)
        #expect(Day(now?.start ?? .distantPast, calendar: calendar) == today.adding(days: -2))
        let logged = entries + [food("Burrito", at(yesterday, 12, 15), kcal: 700)]
        #expect(LogAgain.usual(at: at(yesterday, 12, 30), entries: logged, today: today, calendar: calendar) == nil)
    }

    @Test("a saved meal planned near now isn't offered as well, and what's planned doesn't make it usual")
    func savedMealPlannedNearNow() {
        let eaten = [food("Turkey", at(today.adding(days: -2), 12, 15)), food("Turkey", at(today.adding(days: -3), 12, 10))]
        let lunch = SavedMeal(name: "Turkey sandwich", from: [eaten[0]])
        let elevenThirty = at(today, 11, 30)
        #expect(SavedMeals.rank([lunch], entries: eaten, now: elevenThirty, calendar: calendar)[0].usualNow)

        let planned = food("Turkey", at(today, 12, 15))
        #expect(!SavedMeals.rank([lunch], entries: eaten, logged: [planned], now: elevenThirty, calendar: calendar)[0].usualNow)
        // Planned for this evening it's no reason to hold back the lunch it is now.
        let tonight = food("Turkey", at(today, 19))
        #expect(SavedMeals.rank([lunch], entries: eaten, logged: [tonight], now: elevenThirty, calendar: calendar)[0].usualNow)
    }

    @Test("same as usual for a time on a day to come: a meal planned near it counts, and planned food is never the suggestion")
    func usualNearAPlannedMeal() {
        // What's been eaten: the app keeps food for later out of what it suggests from.
        let entries = weeks()
        let ahead = today.adding(days: 2)
        let usual = LogAgain.usual(at: at(ahead, 12, 30), entries: entries, today: today, calendar: calendar)
        #expect(usual?.entries.map(\.name) == ["Salad", "Chicken"])
        let planned = [food("Soup", at(ahead, 12, 45)), food("Bread", at(ahead, 12, 46))]
        #expect(LogAgain.usual(at: at(ahead, 12, 30), entries: entries, logged: planned, today: today, calendar: calendar) == nil)
        // With what's planned further off, the row stays, and still offers what was eaten.
        let snack = [food("Almonds", at(ahead, 16))]
        #expect(LogAgain.usual(at: at(ahead, 12, 30), entries: entries, logged: snack, today: today, calendar: calendar) == usual)
    }

    @Test func theHubLearnsTheDayByItsParts() {
        // Today has its breakfast, at 7:40 so still early, lunch, almonds and dinner in the fixture;
        // the hub is told so. What's usual is the 8 o'clock of all the days, not today's.
        let rhythm = UsualMeals.rhythm(entries: weeks(), today: today, now: at(today, 20), calendar: calendar)
        #expect(rhythm.day == today)
        #expect(rhythm.usual.first == .morning)
        #expect(rhythm.usual.contains(.midday))
        #expect(rhythm.usual.last == .evening)
        #expect(rhythm.eaten.first == .early)
        #expect(rhythm.eaten.last == .evening)
    }
}
