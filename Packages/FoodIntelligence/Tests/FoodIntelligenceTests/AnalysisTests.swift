import FoodDatabase
import SystemCore
import Testing
@testable import FoodIntelligence

@Suite("Analysis")
struct AnalysisTests {
    let lettuce = [food("Lettuce, cos or romaine, raw", kcal: 17, portions: [("1 leaf", 6)]),
                   food("Lettuce, iceberg, raw", kcal: 40, portions: [("1 leaf", 8)]),
                   food("Lettuce, green leaf, raw", kcal: 60, portions: [("1 leaf", 10)])]

    func run(_ model: ScriptedModel, _ catalog: FakeCatalog, description: String = "my meal", photo: Bool = false,
             personal: [PersonalFood] = []) async throws -> MealDraft {
        try await MealAnalysis.run(description: description, image: photo ? blankImage() : nil, personal: personal, reader: model,
                                   picker: model, catalog: catalog)
    }

    @Test func nutrientsComeFromTheCatalogFoodAndItsPortion() async throws {
        let egg = food("Egg, whole, cooked, scrambled", kcal: 149, portions: [("1 large", 61)])
        let model = ScriptedModel(reply([item("Scrambled eggs", 2, "piece", 100)]))
        let draft = try await run(model, FakeCatalog([egg]), description: "two scrambled eggs")
        let guess = try #require(draft.items.first)
        #expect(guess.match?.food == egg)
        #expect(guess.count == 2)
        #expect(guess.unit?.label == "large")
        #expect(abs(guess.nutrients.kcal - 149 * 1.22) < 0.01)
        #expect(guess.sure)
        #expect(!guess.approximate, "two eggs, as said, are two large eggs")
        #expect(draft.isFood)
        // One request: the ranking was clear.
        #expect(model.requests.withLock { $0.count } == 1)
    }

    @Test func aPickSettlesANearTieAndMovesItsEntryToTheFront() async throws {
        let scored = [match(lettuce[0], 3), match(lettuce[1], 2.8), match(lettuce[2], 2.6)]
        let model = ScriptedModel(reply([item("lettuce", 1, "leaf", 10)])) { _ in [Pick(food: 1, entry: 2)] }
        let draft = try await run(model, FakeCatalog(scripted: ["lettuce": scored]))
        let requests = model.requests.withLock { $0 }
        #expect(requests.count == 2)
        #expect(requests[1].0 == Prompts.pickInstructions)
        #expect(!requests[1].2, "the second pass is text only")
        let guess = try #require(draft.items.first)
        #expect(guess.match?.food == lettuce[1])
        #expect(guess.alternatives.map(\.food) == [lettuce[0], lettuce[2]])
        #expect(guess.count == 1)
        #expect(guess.unit?.label == "leaf")
    }

    @Test func aFailedPickKeepsTheRankedFirstChoice() async throws {
        let scored = [match(lettuce[0], 3), match(lettuce[1], 2.8)]
        let model = ScriptedModel(reply([item("lettuce", 1, "leaf", 10)]))
        let draft = try await run(model, FakeCatalog(scripted: ["lettuce": scored]))
        #expect(draft.items.first?.match?.food == lettuce[0])
        #expect(model.requests.withLock { $0.count } == 2)
    }

    @Test func aWeakMatchIsOfferedButNotSure() async throws {
        let salmon = food("Fish, salmon, Atlantic, raw", kcal: 142)
        let model = ScriptedModel(reply([item("uni sashimi", 4, "piece", 120)]))
        let draft = try await run(model, FakeCatalog(scripted: ["uni sashimi": [match(salmon, 1.1)]]))
        let guess = try #require(draft.items.first)
        #expect(guess.match?.food == salmon)
        #expect(!guess.sure)
        #expect(guess.approximate)
        #expect(model.requests.withLock { $0.count } == 1, "a weak match isn't asked about")
    }

    @Test func unmatchedFoodsHaveNoNutrients() async throws {
        let draft = try await run(ScriptedModel(reply([item("dragonfruit sorbet", 1, "scoop", 70)])), FakeCatalog())
        let guess = try #require(draft.items.first)
        #expect(guess.match == nil)
        #expect(guess.nutrients == .zero)
        #expect(guess.alternatives.isEmpty)
        #expect(!guess.sure)
    }

    @Test func aPhotoWithoutFoodIsReportedWithoutSearching() async throws {
        let catalog = FakeCatalog([food("Hamburger")])
        let model = ScriptedModel(reply([item("Hamburger", 1, "burger", 200)], scene: "a person standing in a kitchen", food: false))
        let draft = try await run(model, catalog, description: "", photo: true)
        #expect(!draft.isFood)
        #expect(draft.items.isEmpty)
        #expect(draft.scene == "a person standing in a kitchen")
        #expect(catalog.asked.withLock { $0.isEmpty })
        let request = try #require(model.requests.withLock { $0.first })
        #expect(request.0 == Prompts.mealInstructions)
        #expect(request.1.hasPrefix("Say what this photo shows"))
        #expect(request.2)
    }

    @Test func thePersonsNoteTravelsWithThePhoto() async throws {
        let model = ScriptedModel(reply([item("Pepperoni pizza", 3, "slice", 330)], scene: "a pizza box", food: true))
        _ = try await run(model, FakeCatalog(), description: "large pepperoni from dominos, ate 3 slices", photo: true)
        #expect(model.requests.withLock { $0[0].1 }.contains(#"The person says: "large pepperoni from dominos, ate 3 slices""#))
    }

    @Test func anAmountSaidOfOneFoodLeavesTheOtherAnEstimate() async throws {
        let toast = food("Bread, toasted", kcal: 290, portions: [("1 slice", 30)])
        let bacon = food("Bacon, cooked", kcal: 540, portions: [("1 slice", 8)])
        let model = ScriptedModel(reply([item("Toast", 1, "slice", 30), item("Bacon", 2, "slice", 16)]))
        let draft = try await run(model, FakeCatalog(scripted: ["toast": [match(toast, 3)], "bacon": [match(bacon, 3)]]),
                                  description: "toast and 2 slices of bacon")
        #expect(draft.items.map(\.approximate) == [true, false], "the person said how much bacon, not how much toast")
    }

    @Test func aLongDescriptionReachesTheModelWhole() async throws {
        // A dictated day, with its last foods past the 500th character.
        let day = "for breakfast I had two scrambled eggs on sourdough toast with butter and a flat white, then mid morning "
            + "an apple and a handful of almonds, for lunch a chicken caesar salad with croutons and parmesan and a diet coke, "
            + "in the afternoon a protein bar and a coffee with oat milk, for dinner salmon with rice and broccoli and a glass "
            + "of white wine, and after dinner a square of dark chocolate, some strawberries with whipped cream, a few crackers "
            + "with cheddar cheese and a cup of chamomile tea with honey, and before bed a banana and a protein shake"
        #expect(try #require(day.range(of: "a banana")).lowerBound.utf16Offset(in: day) > 500)
        let model = ScriptedModel(reply([item("banana", 1, "piece", 118), item("protein shake", 1, "cup", 300)]))
        _ = try await run(model, FakeCatalog(), description: day)
        let prompt = try #require(model.requests.withLock { $0.first?.1 })
        #expect(prompt.contains("a banana and a protein shake"), "\(prompt)")
        #expect(Prompts.meal(description: String(repeating: "egg ", count: 600), photo: false).count > Prompts.descriptionLimit)
        // A photo's note is a few words.
        #expect(Prompts.meal(description: String(repeating: "egg ", count: 600), photo: true).count < Prompts.noteLimit + 100)
    }

    @Test func thePersonsOwnFoodsArePreferred() async throws {
        let oats = food("My overnight oats", id: "custom:oats", basis: .serving, kcal: 380, portions: [("1 jar", 1)], source: .custom)
        let model = ScriptedModel(reply([item("overnight oats", 1, "jar", 300)]))
        let draft = try await run(model, FakeCatalog([food("Oats", kcal: 389)]), description: "my overnight oats",
                                  personal: [PersonalFood(food: oats, score: 5)])
        let guess = try #require(draft.items.first)
        #expect(guess.match?.food.id == "custom:oats")
        #expect(guess.match?.personal == true)
        #expect(guess.count == 1)
        #expect(guess.nutrients.kcal == 380)
    }

    @Test func aNamedChainsItemIsOneEntryWithAPlainPizzaToSwapTo() async throws {
        let dominos = food("DOMINO'S 14\" Pepperoni Pizza, Classic Hand-Tossed Crust", kcal: 273, portions: [("1 slice", 113)])
        let plain = food("Pizza, pepperoni topping, regular crust", kcal: 298, portions: [("1 slice", 111)])
        let scripted = ["domino's|pepperoni pizza": [match(dominos, 6)]]
        let model = ScriptedModel(reply([item("Pepperoni pizza", 3, "slice", 300, brand: "Domino's"), item("Pepperoni", 12, "slice", 30)]))
        let catalog = FakeCatalog([plain], scripted: scripted)
        let draft = try await run(model, catalog, description: "large pepperoni from dominos, ate 3 slices")
        #expect(draft.items.count == 1)
        let pizza = try #require(draft.items.first)
        #expect(pizza.seenBrand == "Domino's")
        #expect(pizza.match?.food == dominos)
        #expect(pizza.count == 3)
        #expect(pizza.unit?.amount == 113)
        #expect(abs(pizza.nutrients.kcal - 273 * 3.39) < 0.01)
        #expect(!pizza.approximate, "3 slices, as said")
        #expect(pizza.alternatives.contains { $0.food == plain }, "a misread brand is one tap from a plain pizza")
    }
}
