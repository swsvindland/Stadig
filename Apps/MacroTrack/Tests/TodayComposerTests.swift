import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// Today's composer over the bundled catalog: what's typed becomes foods at the amounts typed, and
/// Return logs them together, one Undo for all.
@MainActor
struct TodayComposerTests {
    func part(_ text: String) throws -> AddFoodPart {
        try #require(AddFoodText.parse(text).first)
    }

    @Test func amountsBecomeTheFoodsOwnUnits() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let banana = try model.requireFood(Foods.bananaID)
        let usual = FoodUnits.suggested(for: banana)

        let grams = TodayComposer.portion(try #require(try part("banana 120").amount), food: banana, usual: usual)
        #expect(grams.unit.id == "g")
        #expect(grams.count == 120)

        // A banana is counted: "2 bananas" is two of its usual portion, not 2 grams.
        let two = TodayComposer.portion(try #require(try part("2 banana").amount), food: banana, usual: usual)
        #expect(two.unit == usual.unit)
        #expect(two.count == 2)

        let ounces = TodayComposer.portion(try #require(try part("4 oz banana").amount), food: banana, usual: usual)
        #expect(abs(FoodUnits.amount(ounces.count, ounces.unit) - 4 * 28.3495) < 0.5)

        let doubled = TodayComposer.portion(try #require(try part("banana x2").amount), food: banana, usual: usual)
        #expect(doubled.unit == usual.unit)
        #expect(doubled.count == usual.count * 2)
    }

    @Test func returnLogsEveryPartTogetherWithOneUndo() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let composer = TodayComposer()
        composer.attach(model)
        composer.text = "banana 150, 300 kcal"

        await composer.submit()

        let today = model.entries(on: model.today)
        #expect(today.count == 2)
        let banana = try #require(today.first { $0.foodID != nil })
        #expect(banana.grams == 150)
        #expect(banana.name.localizedCaseInsensitiveContains("banana"))
        let quick = try #require(today.first { $0.source == .quickAdd })
        #expect(quick.nutrients.kcal == 300)
        // Typed order is kept, and the field is clear for the next food.
        #expect(banana.date < quick.date)
        #expect(composer.text.isEmpty)
        #expect(Set(model.toast?.undo ?? []) == Set(today.map(\.id)))

        model.undo(try #require(model.toast))
        #expect(model.entries(on: model.today).isEmpty)
    }

    @Test func typingOnWhileReturnFindsTheFoodsKeepsOnlyWhatCameAfter() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let composer = TodayComposer()
        composer.attach(model)
        composer.text = "banana 150"

        // Return, and the next food typed before the catalog has answered for the first.
        let returned = Task { await composer.submit() }
        await Task.yield()
        #expect(composer.submitting, "still finding the banana")
        composer.text = "banana 150, 300 kcal"
        await returned.value

        #expect(model.entries(on: model.today).count == 1)
        #expect(composer.text == "300 kcal", "the banana, logged, leaves the field: a second Return would log it again")
    }

    @Test func aLetterOnItsOwnIsStillBeingTyped() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let composer = TodayComposer()
        composer.attach(model)
        composer.text = "banana 100, b"

        await composer.submit()

        #expect(model.entries(on: model.today).count == 1)
        #expect(model.logger == nil, "nothing handed to the logger")
    }

    /// The Log tab's composer, on Tuesday: Return logs there at this time of day, as the bar's
    /// logger did, with the one Undo. Every other tab's logs today, whatever day Log was left on.
    @Test func theLogTabsComposerLogsToTheDayItShows() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let yesterday = model.today.adding(days: -1)
        model.show(day: yesterday)
        let composer = TodayComposer()
        composer.logsToSelectedDay = true
        composer.attach(model)
        composer.text = "banana 150, 300 kcal"

        await composer.submit()

        let logged = model.entries(on: yesterday)
        #expect(logged.count == 2)
        #expect(model.entries(on: model.today).isEmpty)
        let clock = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let banana = try #require(logged.first { $0.foodID != nil })
        #expect(Calendar.current.dateComponents([.hour, .minute], from: banana.date).hour == clock.hour)
        #expect(Set(model.toast?.undo ?? []) == Set(logged.map(\.id)))

        // Today's composer (and Plan's, and Progress's) logs today, now.
        let today = TodayComposer()
        today.attach(model)
        today.text = "banana 100"
        await today.submit()
        #expect(model.entries(on: model.today).count == 1)
    }

    @Test func theFieldSaysWhereReturnLogs() {
        let today = Day(year: 2026, month: 11, day: 12)
        #expect(TodayComposer.placeholder(for: today, today: today) == "Add food, or say what you ate")
        // Tuesday, and tomorrow (a Friday), by name.
        #expect(TodayComposer.placeholder(for: today.adding(days: -2), today: today).hasPrefix("Add food to Tue"))
        #expect(TodayComposer.placeholder(for: today.adding(days: 1), today: today).hasPrefix("Add food to Fri"))
        // Further off, a weekday could be either: the date.
        let far = TodayComposer.placeholder(for: today.adding(days: -9), today: today)
        #expect(far.hasPrefix("Add food to ") && far.contains("3"), "\(far)")
    }

    /// Without Apple's model; with it, they're worked out on the thread (`EstimateInPlaceTests`).
    @Test func wordsNothingMatchesGoOnToTheLoggerWithoutTheModel() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let composer = TodayComposer()
        composer.attach(model)
        composer.text = "qqxzv"

        await composer.submit()

        #expect(model.entries(on: model.today).isEmpty)
        #expect(model.logger != nil)
        #expect(model.takeLoggerText() == "qqxzv")
    }
}
