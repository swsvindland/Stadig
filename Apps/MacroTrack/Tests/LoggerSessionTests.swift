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

    /// With the search cleared, Log again's + is the answer to the review, not a food on the day.
    @Test func whileFindingAFoodLogAgainAnswersTheReview() throws {
        let model = TestEnvironment().model()
        model.onboard()
        model.log([try model.entry(foodID: Foods.coffeeID, grams: 237)])
        model.log([
            FoodEntry(
                date: Date(), name: "Bar snack", amountLabel: "1", nutrients: Nutrients(kcal: 90, protein: 1, carbs: 2, fat: 8), source: .quickAdd)
        ])
        let session = LoggerSession(mode: .describe)
        session.review = try review(model)
        let unmatched = try #require(session.review?.items[1])
        #expect(session.again(model.logAgain).count == model.logAgain.count)

        session.find("", for: unmatched.id)
        let offered = session.again(model.logAgain)
        #expect(offered.map(\.template.foodID) == [Foods.coffeeID], "what's no one food can't answer it")
        let onTheDay = logged(model)
        session.addAgain(try #require(offered.first), model: model)

        #expect(session.finding == nil)
        #expect(session.review?.items[1].food?.id == Foods.coffeeID)
        #expect(logged(model) == onTheDay, "nothing went on the day")
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
    /// The ribbon's Photo says camera whatever the device has, the menu says photo library on a
    /// Mac, and a photo dropped on an iPad says that too. They're doors to one way of logging, so
    /// which of them started a review can't decide whether asking keeps it.
    @Test(arguments: [(LogMode.camera, LogMode.photoLibrary), (.photoLibrary, .camera)])
    func askedForTheOtherDoorToThePhotoItKeepsTheReview(started: LogMode, asked: LogMode) throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: started)
        session.review = try review(model, mode: started)

        session.go(to: asked)
        #expect(session.review != nil, "on the review")

        session.backToSearch()
        session.go(to: asked)
        #expect(session.review != nil, "and from the search")
        #expect(session.mode.isPhoto, "back at it")
    }

    @Test func askedForTheOtherDoorToThePhotoItGoesThereWithNoReview() {
        let session = LoggerSession(mode: .camera)
        session.go(to: .photoLibrary)
        #expect(session.mode == .photoLibrary)
    }

    @Test func askedForThePhotoALeftDescriptionStaysDropped() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .search)
        session.review = try review(model, mode: .describe)
        session.go(to: .camera)
        #expect(session.review == nil)
        #expect(session.mode == .camera)
    }

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

    /// Holds a read open until the test lets it go, whether or not it's been stopped: the model may
    /// be slow to notice.
    final class Gate {
        private var opened = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !opened else { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func open() {
            opened = true
            for read in waiting { read.resume() }
            waiting = []
        }
    }

    func guess(_ name: String) -> MealGuess {
        let seen = GuessedItem(
            id: UUID(), seenName: name, seenBrand: nil, match: nil, alternatives: [], unit: nil, count: 1, nutrients: .zero, sure: false,
            approximate: true)
        return MealGuess(scene: nil, isFood: true, items: [seen], engine: .onDevice, seconds: 1)
    }

    @Test func aReadLandsAsAReviewOfTheWayItStartedOn() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .describe)
        let found = guess("toast")

        session.startRead(.description, model) { .foods(found) }

        #expect(session.reading)
        await session.read?.value
        #expect(!session.reading)
        #expect(session.read == nil)
        #expect(session.review?.mode == .describe)
        #expect(session.review?.source == .description)
        #expect(session.review?.items.first?.seen.seenName == "toast")
    }

    /// A photo being read, then Describe on the ribbon, a description read and foods unticked: the
    /// photo's read finishes, and changes nothing.
    @Test func aReadLeftForAnotherWayDoesntReplaceTheReviewThere() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .camera)
        let gate = Gate()
        let seen = guess("photo's foods")
        session.startRead(.photo, model) {
            await gate.wait()
            return .foods(seen)
        }
        let photo = try #require(session.read)

        session.mode = .describe

        #expect(photo.isCancelled, "the model is stopped, and the quota with it")
        #expect(!session.reading)
        let described = guess("description's foods")
        session.startRead(.description, model) { .foods(described) }
        await session.read?.value
        session.review?.items[0].included = false

        gate.open()
        await photo.value

        #expect(session.review?.source == .description)
        #expect(session.review?.items.first?.seen.seenName == "description's foods")
        #expect(session.review?.items.first?.included == false, "the person's changes stand")
    }

    /// Find foods, then the ribbon's Search: the meal given up on doesn't turn up later, in place of
    /// Photo's or Describe's own screen, on a review that thinks it belongs to the search.
    @Test func aReadLeftForTheSearchLeavesNoReview() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .describe)
        let gate = Gate()
        let seen = guess("toast")
        session.startRead(.description, model) {
            await gate.wait()
            return .foods(seen)
        }
        let read = try #require(session.read)

        session.mode = .search
        gate.open()
        await read.value

        #expect(read.isCancelled)
        #expect(session.review == nil)
    }

    @Test func everyWayBackToTheSearchStopsARead() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .describe)
        session.startRead(.description, model) { .nothing("") }
        let read = try #require(session.read)

        session.backToSearch()

        #expect(read.isCancelled)
    }

    /// Done while it's looking: the host stops it as it goes.
    @Test func closingTheLoggerStopsARead() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .camera)
        let gate = Gate()
        let seen = guess("toast")
        session.startRead(.photo, model) {
            await gate.wait()
            return .foods(seen)
        }
        let read = try #require(session.read)

        session.stopRead()
        gate.open()
        await read.value

        #expect(read.isCancelled)
        #expect(session.review == nil)
        #expect(!session.reading)
    }

    @Test func aSecondReadTakesTheFirstsPlace() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .camera)
        let gate = Gate()
        let first = guess("first")
        let second = guess("second")
        session.startRead(.photo, model) {
            await gate.wait()
            return .foods(first)
        }
        let earlier = try #require(session.read)

        session.startRead(.photo, model) { .foods(second) }
        await session.read?.value
        gate.open()
        await earlier.value

        #expect(earlier.isCancelled)
        #expect(session.review?.items.first?.seen.seenName == "second")
    }

    /// A question of which door, not of leaving: a picked photo being read, and the Photo chip tapped.
    @Test func goingBetweenTheCameraAndThePhotoLibraryDoesntStopARead() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .photoLibrary)
        let found = guess("toast")
        session.startRead(.photo, model) { .foods(found) }

        session.mode = .camera

        #expect(session.reading)
        await session.read?.value
        #expect(session.review != nil)
    }

    /// Asked for the way it's on from outside, as a widget can: what's there stays, a read included.
    @Test func askedForTheWayItsOnAReadCarriesOn() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .describe)
        let found = guess("toast")
        session.startRead(.description, model) { .foods(found) }

        session.go(to: .describe)

        #expect(session.reading)
        await session.read?.value
        #expect(session.review != nil)
    }

    @Test func aReadsProblemShowsUntilItsWayIsLeft() async throws {
        let model = TestEnvironment().model()
        let session = LoggerSession(mode: .camera)
        session.startRead(.photo, model) { .nothing("That looks like a dog, not food.") }
        await session.read?.value
        #expect(session.readProblem == "That looks like a dog, not food.")
        #expect(session.review == nil)
        #expect(!session.reading)

        session.mode = .describe

        #expect(session.readProblem == nil, "not shown under Describe")
    }

    /// A review with two rows of the food, as a meal can have, the second unticked.
    func twoRows(of food: Food, unit: PortionUnit, count: Double) -> MealReview {
        func seen() -> GuessedItem {
            GuessedItem(
                id: UUID(), seenName: food.name, seenBrand: nil, match: FoodMatch(food: food, score: 1, personal: true), alternatives: [], unit: unit,
                count: count, nutrients: food.nutrients, sure: true, approximate: false)
        }
        var review = MealReview(
            guess: MealGuess(scene: nil, isFood: true, items: [seen(), seen()], engine: .onDevice, seconds: 1), source: .description,
            mode: .describe, corrected: { $0 })
        review.items[1].included = false
        return review
    }

    /// Describe a meal that matches one of the person's own foods at 300 kcal, tap its amount, and
    /// the pencil makes it 360. Their own food is changed in place, so only the review's copy can
    /// carry that to the entry.
    @Test func aCorrectionToTheirOwnFoodReachesTheReviewAndTheEntry() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let stew = model.save(
            customFood: Food(
                id: "stew", name: "Beef stew", basis: .serving, nutrients: Nutrients(kcal: 300, protein: 25, carbs: 20, fat: 13), source: .custom))
        let serving = try #require(FoodUnits.units(for: stew).first)
        session.review = twoRows(of: stew, unit: serving, count: 1)
        let edited = try #require(stew.correcting(kcal: 360, protein: 25, carbs: 20, fat: 13, count: 1, unit: serving))

        session.useCorrection(model.saveCorrection(edited))

        #expect(session.review?.items.map(\.nutrients.kcal) == [360, 360], "every row of it")
        #expect(session.review?.chosen.count == 1, "and what was unticked stays unticked")
        session.logReview(model)
        #expect(model.entries(on: model.today).map(\.nutrients.kcal) == [360], "what the button said")
    }

    /// `log` would have applied a catalog food's correction anyway, under a button saying the old total.
    @Test func aCorrectionToACatalogFoodReachesTheReview() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        session.review = twoRows(of: banana, unit: grams, count: 100)
        let edited = try #require(banana.correcting(kcal: 120, protein: 1, carbs: 28, fat: 0, count: 100, unit: grams))

        session.useCorrection(model.saveCorrection(edited))

        #expect(session.review?.chosen.map(\.nutrients.kcal) == [120])
        session.logReview(model)
        #expect(model.entries(on: model.today).map(\.nutrients.kcal) == [120])
    }

    /// 100 kcal of a food is 100 kcal after a correction too, so it's a different amount of it.
    @Test func aFoodCountedInCaloriesKeepsItsCalories() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        let calories = try #require(FoodUnits.units(for: banana).first { $0.kind == .energy })
        session.review = twoRows(of: banana, unit: calories, count: 100)
        let edited = try #require(banana.correcting(kcal: 200, protein: 2, carbs: 50, fat: 0, count: 100, unit: grams))

        session.useCorrection(edited)

        let kcal = try #require(session.review?.items[0].nutrients.kcal)
        #expect(abs(kcal - 100) < 0.5, "\(kcal)")
    }

    /// Bananas in calories, as a row and as the amount picked for it. They have to agree: the row is
    /// what shows if the panel's closed, and the amount is what goes back if it's used.
    @Test func aRowAndItsAmountTakeACorrectionAlike() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        let calories = try #require(FoodUnits.units(for: banana).first { $0.kind == .energy })
        session.review = twoRows(of: banana, unit: calories, count: 120)
        let item = try #require(session.review?.items[0])
        var draft = model.draft(for: AmountRequest(purpose: .pick(item: item.id, count: item.count, unit: calories), food: banana))
        let edited = model.saveCorrection(try #require(banana.correcting(kcal: 200, protein: 2, carbs: 50, fat: 0, count: 100, unit: grams)))

        draft.use(edited)
        session.useCorrection(edited)

        let row = try #require(session.review?.items[0])
        #expect(draft.amount.count == row.count)
        #expect(draft.amount.count == 120)
        #expect(draft.amount.unit?.id == row.unit?.id)
        #expect(abs(draft.nutrients.kcal - row.nutrients.kcal) < 0.5)
    }

    /// Corrected to no calories it can't be counted in them any more, in a row or an amount.
    @Test func aFoodCorrectedToNoCaloriesLeavesItsRowsCalorieUnit() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        let calories = try #require(FoodUnits.units(for: banana).first { $0.kind == .energy })
        session.review = twoRows(of: banana, unit: calories, count: 120)
        let item = try #require(session.review?.items[0])
        var draft = model.draft(for: AmountRequest(purpose: .pick(item: item.id, count: item.count, unit: calories), food: banana))
        let edited = model.saveCorrection(try #require(banana.correcting(kcal: 0, protein: 0, carbs: 0, fat: 0, count: 100, unit: grams)))

        draft.use(edited)
        session.useCorrection(edited)

        let row = try #require(session.review?.items[0])
        #expect(row.unit?.id == "g")
        #expect(row.count == FoodUnits.convert(120, from: calories, to: grams), "the same bananas")
        #expect(row.nutrients.kcal == 0)
        #expect(draft.amount.unit?.id == row.unit?.id)
        #expect(draft.amount.count == row.count)
    }

    /// A food corrected somewhere the session can't hear: from the hours beside the pane, from the
    /// meal under the logger, or on another device. What the person sees goes by the food as it is.
    @Test func foodsReadAgainTakeWhatChangedElsewhere() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let stew = model.save(
            customFood: Food(
                id: "stew", name: "Beef stew", basis: .serving, nutrients: Nutrients(kcal: 300, protein: 25, carbs: 20, fat: 13), source: .custom))
        let serving = try #require(FoodUnits.units(for: stew).first)
        session.review = twoRows(of: stew, unit: serving, count: 1)
        session.review?.items[0].count = 2
        let changes = model.foodsChanged

        model.saveCorrection(try #require(stew.correcting(kcal: 360, protein: 25, carbs: 20, fat: 13, count: 1, unit: serving)))
        #expect(model.foodsChanged != changes, "what tells a logger to read them")
        session.refreshFoods(model)

        #expect(session.review?.items.map(\.nutrients.kcal) == [720, 360], "and at the amounts they were")
        #expect(session.review?.items[0].count == 2)
    }

    @Test func aCorrectionTakenAwayElsewhereReachesTheReviewToo() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        let edited = model.saveCorrection(try #require(banana.correcting(kcal: 120, protein: 1, carbs: 28, fat: 0, count: 100, unit: grams)))
        session.review = twoRows(of: edited, unit: grams, count: 100)

        model.removeCorrection(of: banana.id)
        session.refreshFoods(model)

        #expect(session.review?.items[0].nutrients.kcal == banana.nutrients.kcal)
    }

    /// What the model thought a food might be is from when it read the photo. Picking one of those
    /// after correcting it has to give the food as it is now, or the Log total says the old numbers.
    @Test func aSwapToACorrectedFoodTakesItsNewNumbers() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        let coffee = try model.requireFood(Foods.coffeeID)
        session.review = twoRows(of: coffee, unit: grams, count: 100)
        let item = try #require(session.review?.items[0].id)
        model.saveCorrection(try #require(banana.correcting(kcal: 120, protein: 1, carbs: 28, fat: 0, count: 100, unit: grams)))

        session.swap(item, to: banana, model)

        #expect(session.review?.items[0].nutrients.kcal == 120)
    }

    @Test func aCorrectionToAnotherFoodLeavesTheReviewAlone() throws {
        let model = TestEnvironment().model()
        model.onboard()
        let session = LoggerSession(mode: .describe)
        let banana = try model.requireFood(Foods.bananaID)
        let grams = try model.requireUnit(banana, "g")
        session.review = twoRows(of: banana, unit: grams, count: 100)
        let before = session.review?.items.map(\.nutrients.kcal)
        var coffee = try model.requireFood(Foods.coffeeID)
        coffee.nutrients.kcal = 500

        session.useCorrection(coffee)

        #expect(session.review?.items.map(\.nutrients.kcal) == before)
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
