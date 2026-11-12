import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// Words Today matched to no food, worked out on the thread: which rows stay, which foods wait for
/// "Looks right", and what confirming one does to the entry.
struct ThreadEstimateTests {
    let calendar = Calendar.current
    let day = Day(year: 2026, month: 11, day: 11)

    func entry(_ name: String, at hour: Int, on day: Day? = nil, estimate: Bool = true) -> FoodEntry {
        let date = (day ?? self.day).at(hour: hour, minute: 5)
        return FoodEntry(
            date: date, name: name, amountLabel: estimate ? "≈ 1 bowl · 450 g" : "1 bowl · 450 g",
            nutrients: Nutrients(kcal: 540, protein: 28, carbs: 55, fat: 22), source: .description, confidence: estimate ? 0.5 : nil,
            updatedAt: date)
    }

    @Test func aLoggedEstimateKeepsOnlyTheFoodsStillInTheLog() {
        let rice = entry("Rice", at: 15)
        let beans = entry("Beans", at: 15)
        let estimates = [ThreadEstimate(words: "burrito bowl", asked: day.at(hour: 15, minute: 5), state: .logged([rice.id, beans.id]))]

        // Beans deleted: rice still waits.
        let kept = ThreadEstimates.current(estimates, entries: [rice], today: day, calendar: calendar)
        #expect(kept.first?.state == .logged([rice.id]))
        #expect(ThreadEstimates.unconfirmed(kept) == [rice.id])
        #expect(kept.first?.logs(any: [rice]) == true)
        #expect(kept.first?.logs(any: [beans]) == false, "deleted, so no longer its food")

        // Undo took both: the estimate goes with them.
        #expect(ThreadEstimates.current(estimates, entries: [], today: day, calendar: calendar).isEmpty)
    }

    @Test func rowsStayUntilTheDayIsOver() {
        let working = ThreadEstimate(words: "pad thai", asked: day.at(hour: 23, minute: 59))
        let failed = ThreadEstimate(words: "the usual", asked: day.at(hour: 12, minute: 0), state: .failed("No food in “the usual”."))
        #expect(ThreadEstimates.current([working, failed], entries: [], today: day, calendar: calendar).count == 2)
        #expect(working.isRow && failed.isRow)
        // The next day's thread starts clear.
        #expect(ThreadEstimates.current([working, failed], entries: [], today: day.adding(days: 1), calendar: calendar).isEmpty)
    }

    @Test func confirmingTakesOnlyThoseFoodsOffTheEstimate() {
        let ids = [UUID(), UUID()]
        let estimate = ThreadEstimate(words: "burrito bowl", asked: day.at(hour: 15, minute: 5), state: .logged(ids))
        let working = ThreadEstimate(words: "pad thai", asked: day.at(hour: 15, minute: 6))

        let part = ThreadEstimates.confirming([ids[0]], in: [estimate, working])
        #expect(part.map(\.state) == [.logged([ids[1]]), .working])
        let all = ThreadEstimates.confirming(Set(ids), in: [estimate, working])
        #expect(all.map(\.id) == [working.id], "nothing left waiting: the estimate is done")
    }

    @Test func looksRightKeepsTheNumbersAndDropsTheEstimate() {
        let bowl = entry("Burrito bowl", at: 15)
        let now = day.at(hour: 15, minute: 10)
        let confirmed = bowl.confirmed(at: now, calendar: calendar)
        #expect(!confirmed.isEstimate)
        #expect(confirmed.amountLabel == "1 bowl · 450 g")
        #expect(confirmed.nutrients == bowl.nutrients)
        #expect(confirmed.date == bowl.date && confirmed.day == bowl.day)
        #expect(confirmed.firstLogged == bowl.firstLogged, "still logged when it was")
        #expect(confirmed.updatedAt > bowl.updatedAt)
        // A label without the mark is left as it is.
        #expect(entry("Rice", at: 15, estimate: false).confirmed(at: now).amountLabel == "1 bowl · 450 g")
    }

    @Test(arguments: [
        "whatever was in the fridge", "something sweet", "stuff from the freezer", "a sandwich and something else", "random bits",
        "a big dinner", "lunch out", "fast food", "leftovers", "dinner at a restaurant", "snack at work", "takeout",
        "the usual lunch",
    ])
    func wordsThatNameNoFoodAreVague(_ words: String) {
        #expect(VagueWords.isVague(words), "\(words)")
    }

    @Test(arguments: [
        "burrito bowl", "leftover pizza", "chicken dinner", "pizza for dinner", "a slice of birthday cake", "pad thai from work",
        "fast food burger", "stuffed peppers", "dinner rolls", "",
    ])
    func wordsThatNameAFoodAreNot(_ words: String) {
        #expect(!VagueWords.isVague(words), "\(words)")
    }

    @Test func aVagueEstimateAsksFirstAndStaysARowUntilLogged() {
        let rice = entry("Rice", at: 19)
        let vague = ThreadEstimate(words: "whatever was in the fridge", asked: day.at(hour: 19, minute: 5))
        #expect(vague.asksFirst)
        #expect(!ThreadEstimate(words: "burrito bowl", asked: day.at(hour: 19, minute: 5)).asksFirst)

        var proposed = vague
        proposed.state = .proposed([rice])
        // Not logged: a row of its own, nothing waiting for "Looks right", and kept until the day ends.
        #expect(proposed.isRow)
        #expect(proposed.proposal == [rice])
        #expect(!proposed.logs(any: [rice]))
        #expect(ThreadEstimates.unconfirmed([proposed]).isEmpty)
        #expect(ThreadEstimates.current([proposed], entries: [], today: day, calendar: calendar) == [proposed])
        #expect(ThreadEstimates.current([proposed], entries: [], today: day.adding(days: 1), calendar: calendar).isEmpty)
    }
}
