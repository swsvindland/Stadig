import FoodDatabase
import FoodIntelligence
import Foundation
import NutritionEngine
import SystemCore
import Testing

@testable import MacroTrack

/// Words Today's composer matched to no food, worked out on the thread by the model (a stand-in
/// here, held until the test lets it answer): the row at once, the foods logged in its place as
/// estimates with Undo, "Looks right", and what's said when there's nothing.
@MainActor
struct EstimateInPlaceTests {
    /// Holds the stand-in model's answer until the test opens it.
    final class Gate {
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func open() {
            isOpen = true
            for continuation in waiting { continuation.resume() }
            waiting = []
        }
    }

    struct Setup {
        let model: AppModel
        let composer: TodayComposer
        let gate: Gate
    }

    /// A model whose stand-in reads any words as a banana and something the catalog hasn't got.
    func setup(throwing error: MealAIError? = nil) throws -> Setup {
        let model = TestEnvironment().model()
        model.onboard()
        let banana = try model.requireFood(Foods.bananaID)
        let usual = FoodUnits.suggested(for: banana)
        let gate = Gate()
        model.ai.describeStub = { _ in
            await gate.wait()
            if let error { throw error }
            return MealGuess(
                scene: nil, isFood: true,
                items: [
                    GuessedItem(
                        seenName: "Banana", seenBrand: nil, match: FoodMatch(food: banana, score: 3, personal: false), alternatives: [],
                        unit: usual.unit, count: usual.count, nutrients: banana.nutrients, sure: true, approximate: true),
                    GuessedItem(
                        seenName: "Mystery sauce", seenBrand: nil, match: nil, alternatives: [], unit: nil, count: 1, nutrients: .zero, sure: false,
                        approximate: true),
                ], engine: .onDevice, seconds: 1)
        }
        let composer = TodayComposer()
        composer.attach(model)
        return Setup(model: model, composer: composer, gate: gate)
    }

    /// Until no estimate is working: the read answers on the main actor, a few hops after the gate.
    func settle(_ model: AppModel) async {
        for _ in 0..<1000 where model.estimates.contains(where: { $0.state == .working }) { await Task.yield() }
    }

    @Test func wordsNothingMatchesLandOnTheThreadAsEstimates() async throws {
        let setup = try setup()
        let model = setup.model
        setup.composer.text = "banana 100, qqxzv"

        await setup.composer.submit()

        // The banana typed is logged at once; the words are a row on the thread, not the logger.
        #expect(model.entries(on: model.today).count == 1)
        #expect(model.logger == nil)
        let row = try #require(model.estimates.first)
        #expect(row.words == "qqxzv")
        #expect(row.state == .working)
        #expect(setup.composer.text.isEmpty)

        setup.gate.open()
        await settle(model)

        let estimate = try #require(model.estimates.first { $0.id == row.id })
        guard case .logged(let ids) = estimate.state else {
            Issue.record("expected its foods logged, not \(estimate.state)")
            return
        }
        let landed = model.entries(on: model.today).filter { ids.contains($0.id) }
        #expect(landed.count == 1)
        #expect(landed.allSatisfy { $0.isEstimate && $0.source == .description })
        // Logged when Return was pressed, after the banana typed with them, not when the model answered.
        let typed = try #require(model.entries(on: model.today).first { !ids.contains($0.id) })
        #expect(landed.allSatisfy { $0.date > typed.date && $0.date.timeIntervalSince(typed.date) < 5 })
        #expect(Set(model.toast?.undo ?? []) == Set(ids), "the fresh meal's Undo")
        // What the catalog hasn't got stays on the thread, a tap from the logger.
        let missed = try #require(model.estimates.first { $0.words == "Mystery sauce" })
        #expect(missed.state == .failed("Not in the catalog. Part of “qqxzv”."))
    }

    @Test func looksRightKeepsTheFoodsAsTheyAre() async throws {
        let setup = try setup()
        let model = setup.model
        setup.composer.text = "qqxzv"
        await setup.composer.submit()
        setup.gate.open()
        await settle(model)
        let ids = ThreadEstimates.unconfirmed(model.estimates)
        let before = model.entries(on: model.today).filter { ids.contains($0.id) }
        #expect(!ids.isEmpty)

        model.confirmEstimates(ids)

        let after = model.entries(on: model.today).filter { ids.contains($0.id) }
        #expect(after.count == before.count)
        #expect(after.allSatisfy { !$0.isEstimate && !$0.amountLabel.hasPrefix("≈") })
        #expect(after.map(\.nutrients) == before.map(\.nutrients))
        #expect(ThreadEstimates.unconfirmed(model.estimates).isEmpty)
    }

    @Test func undoTakesTheEstimateWithItsFoods() async throws {
        let setup = try setup()
        let model = setup.model
        setup.composer.text = "qqxzv"
        await setup.composer.submit()
        setup.gate.open()
        await settle(model)
        #expect(!ThreadEstimates.unconfirmed(model.estimates).isEmpty)

        model.undo(try #require(model.toast))

        #expect(model.entries(on: model.today).isEmpty)
        #expect(ThreadEstimates.unconfirmed(model.estimates).isEmpty, "nothing left to say Looks right about")
    }

    @Test func aFailedReadSaysSoAndOpensTheLogger() async throws {
        let setup = try setup(throwing: .busy)
        let model = setup.model
        setup.composer.text = "qqxzv"
        await setup.composer.submit()
        setup.gate.open()
        await settle(model)

        let row = try #require(model.estimates.first)
        #expect(row.state == .failed("The model is busy. Try again in a moment."))
        #expect(model.entries(on: model.today).isEmpty)

        model.openEstimateInLogger(row.id)
        #expect(model.estimates.isEmpty)
        #expect(model.logger != nil)
        #expect(model.takeLoggerText() == "qqxzv")
    }

    @Test func dismissingAWorkingRowStopsIt() async throws {
        let setup = try setup()
        let model = setup.model
        setup.composer.text = "qqxzv"
        await setup.composer.submit()
        let row = try #require(model.estimates.first)

        model.dismissEstimate(row.id)
        setup.gate.open()
        for _ in 0..<100 { await Task.yield() }

        #expect(model.estimates.isEmpty)
        #expect(model.entries(on: model.today).isEmpty, "a read dismissed logs nothing")
    }
}
