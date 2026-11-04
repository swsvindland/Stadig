import FoodDatabase
import FoodIntelligence
import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack
@testable import SystemStore

/// One logger, however it's logging: every way returns to the search, and the AI's review lasts
/// until it's logged.
@MainActor
struct LoggerSessionTests {
    func review(_ model: AppModel, mode: LogMode = .describe) throws -> MealReview {
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        let nutrients = Nutrients(kcal: 100, protein: 1, carbs: 25, fat: 0)
        func seen() -> GuessedItem {
            GuessedItem(
                id: UUID(), seenName: "banana", seenBrand: nil, match: nil, alternatives: [], unit: grams, count: 120, nutrients: nutrients,
                sure: true,
                approximate: false)
        }
        var review = MealReview(
            guess: MealGuess(scene: nil, isFood: true, items: [seen(), seen()], engine: .onDevice, seconds: 1), source: .description, mode: mode,
            corrected: { $0 })
        review.items[0].food = banana
        review.items[0].unit = grams
        review.items[0].included = true
        return review
    }

    @Test func everyWayEndsBackAtTheSearch() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.query = "banana"
        session.review = try review(model)

        session.backToSearch()

        #expect(session.mode == .search)
        #expect(session.query.isEmpty)
    }

    /// Off the ribbon to add what the review missed, and that food's amount (or a quick add, or a
    /// scan) ends back at the search: the review is still there.
    @Test func aFoodAddedAwayFromTheReviewLeavesIt() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)
        session.review?.items[0].count = 200
        session.mode = .quickAdd

        session.backToSearch()

        #expect(session.review?.items[0].count == 200, "the 5 foods aren't gone, nor what was changed in them")
        session.mode = .describe
        #expect(session.review != nil)
    }

    @Test func leavingASearchForOneOfItsFoodsLeavesTheReviewToo() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)
        let unmatched = try #require(session.review?.items[1])
        session.find("banana", for: unmatched.id)
        session.mode = .quickAdd

        session.backToSearch()

        #expect(session.finding == nil, "the next food is logged, not given to the review")
        #expect(session.review?.items.count == 2)
    }

    @Test func loggingTheReviewEndsIt() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.query = "banana"
        session.review = try review(model)

        session.logReview(model)

        #expect(logged(model).count == 1, "the matched food, not the one with no match")
        #expect(session.review == nil)
        #expect(session.mode == .search)
        #expect(session.query.isEmpty)
    }

    /// The review is the only copy of what the model saw, so a failed save leaves it to try again.
    @Test func aReviewThatDidntSaveIsThereToTryAgain() throws {
        let environment = TestEnvironment()
        let model = environment.model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)
        environment.store.nextSaveFailure = CocoaError(.fileWriteOutOfSpace)

        session.logReview(model)

        #expect(model.toast?.failed == true)
        #expect(session.review != nil)
        #expect(session.mode == .describe)

        session.logReview(model)

        #expect(logged(model).count == 1)
        #expect(session.review == nil)
    }

    @Test func goingOffToSearchKeepsTheReview() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)
        let unmatched = try #require(session.review?.items[1])
        #expect(unmatched.food == nil)

        session.find("banana", for: unmatched.id)
        #expect(session.mode == .search)
        #expect(session.query == "banana")
        #expect(session.review != nil)

        let found = try model.requireFood(Foods.coffeeID)
        session.use(found)

        #expect(session.mode == .describe)
        #expect(session.query.isEmpty)
        #expect(session.finding == nil)
        #expect(session.review?.items.count == 2)
        #expect(session.review?.items[1].food?.id == Foods.coffeeID)
        #expect(session.review?.items[1].included == true)
    }

    @Test func comingBackWithoutOneChangesNothing() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .camera)
        session.review = try review(model, mode: .camera)
        let unmatched = try #require(session.review?.items[1])
        session.find("banana", for: unmatched.id)

        session.stopFinding()

        #expect(session.mode == .camera)
        #expect(session.review?.items[1].food == nil)
        #expect(session.finding == nil)
    }

    /// The Scan control, pressed again with the logger back at its search.
    @Test func askedForAnotherWayItGoesThere() {
        let session = LoggerSession(mode: .search)
        session.query = "ban"

        session.go(to: .scan)

        #expect(session.mode == .scan)
        #expect(session.query.isEmpty)
    }

    @Test func askedForAnotherWayItDropsTheReview() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)

        session.go(to: .scan)

        #expect(session.review == nil)
        #expect(session.mode == .scan)
    }

    @Test func askedForTheWayItsOnEverythingStays() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)

        session.go(to: .describe)
        #expect(session.review != nil, "a request for the way it's on doesn't lose the review")

        session.mode = .search
        session.query = "ban"
        session.go(to: .search)
        #expect(session.query == "ban")
    }

    /// Off finding a food for the review: the way the review is on goes back to it.
    @Test func askedForTheWayTheReviewIsOnItGoesBackToTheReview() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .camera)
        session.review = try review(model, mode: .camera)
        let unmatched = try #require(session.review?.items[1])
        session.find("banana", for: unmatched.id)

        session.go(to: .camera)

        #expect(session.mode == .camera)
        #expect(session.review != nil)
        #expect(session.finding == nil)
        #expect(session.query.isEmpty)
    }

    /// In the pane an amount takes the logger's place, so left open it would hide what was asked for.
    @Test func anAmountOpenGivesWayToTheAsk() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .search)
        session.portion = .add(try model.requireFood(Foods.bananaID), source: .search)
        session.openMeal = UUID()
        let focus = session.focusRequest

        session.go(to: .search)

        #expect(session.portion == nil)
        #expect(session.openMeal == nil)
        #expect(session.focusRequest == focus + 1)
    }

    func logged(_ model: AppModel) -> [String] { model.entries(on: model.today).map(\.name) }

    func toast(_ model: AppModel) -> String { model.toast?.message ?? "" }

    /// Return before the rows for what's typed are in: the rows on screen are the last query's.
    @Test func returnWaitsForTheRowsOfWhatsTyped() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .search)
        session.query = "coffee brewed"
        await session.search(model)
        #expect(!session.results.isEmpty)

        session.query = "banana raw"
        session.pressedReturn(model)
        #expect(model.toast == nil, "not the coffee on screen")

        await session.search(model)

        #expect(toast(model).contains("Bananas"), "the best of what was typed: \(toast(model))")
        #expect(session.query.isEmpty)
    }

    @Test func returnOnRowsAlreadyThereLogsTheBestOfThem() async {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .search)
        session.query = "banana raw"
        await session.search(model)

        session.pressedReturn(model)

        #expect(toast(model).contains("Bananas"), "\(toast(model))")
    }

    @Test func aReturnForAQueryTypedPastIsDropped() async {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .search)
        session.query = "ban"
        session.pressedReturn(model)

        session.query = "banana raw"
        await session.search(model)

        #expect(model.toast == nil)
        #expect(session.query == "banana raw")
    }

    /// A query cleared and typed again has no rows on screen, whatever it found the first time.
    @Test func returnAfterTheSameFoodAgainWaitsForItsRows() async {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .search)
        session.query = "banana raw"
        await session.search(model)
        session.pressedReturn(model)
        await session.search(model)
        #expect(session.results.isEmpty)
        model.toast = nil

        session.query = "banana raw"
        session.pressedReturn(model)
        await session.search(model)

        #expect(toast(model).contains("Bananas"), "\(toast(model))")
    }

    @Test func returnWithNothingTypedDoesNothing() async {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .search)
        await session.search(model)

        session.pressedReturn(model)

        #expect(model.toast == nil)
    }

    @Test func returnWithNoMatchesDoesNothing() async {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .search)
        session.query = "zzqxv"
        await session.search(model)
        #expect(session.results.isEmpty)

        session.pressedReturn(model)

        #expect(model.toast == nil)
        #expect(session.query == "zzqxv", "left to be corrected")
    }

    /// While the AI's review is finding a food, Return gives it the food, as + does.
    @Test func returnWhileFindingAFoodGoesToTheReview() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)
        let unmatched = try #require(session.review?.items[1])
        session.find("banana raw", for: unmatched.id)

        session.pressedReturn(model)
        await session.search(model)

        #expect(model.toast == nil, "nothing logged")
        #expect(logged(model).isEmpty)
        #expect(session.mode == .describe)
        #expect(session.review?.items[1].food?.name.contains("Bananas") == true)
    }

    @Test func returnOnRowsThereWhileFindingAFoodGoesToTheReview() async throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)
        let unmatched = try #require(session.review?.items[1])
        session.find("banana raw", for: unmatched.id)
        await session.search(model)

        session.pressedReturn(model)

        #expect(model.toast == nil, "nothing logged")
        #expect(session.review?.items[1].food?.name.contains("Bananas") == true)
        #expect(session.mode == .describe)
    }

    @Test func aFoodsNewAmountStaysInItsUnit() throws {
        let model = TestEnvironment().model()
        model.onboard()
        var item = try #require(try review(model).items.first)
        let coffee = try model.requireFood(Foods.coffeeID)
        item.count = 150
        item.swap(to: coffee)
        #expect(item.count == 150)
        #expect(item.unit?.id == "g")
    }
}
