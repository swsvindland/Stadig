import Foundation
import Synchronization
import Testing

@testable import FoodIntelligence

@Suite("Search completions and the model")
struct CompletionChoiceTests {
    /// Answers as scripted, counting how often it's asked.
    final class ScriptedModel: CompletionModel {
        let reply: @Sendable () async throws -> [Int]
        let asked = Mutex(0)

        init(reply: @escaping @Sendable () async throws -> [Int]) { self.reply = reply }

        func choose(instructions: String, prompt: String, options: Int) async throws -> [Int] {
            asked.withLock { $0 += 1 }
            return try await reply()
        }
    }

    let options = ["chicken", "chicken breast", "chicken soup"]
    let noon = Date(timeIntervalSince1970: 1_800_000_000)

    func rank(_ ranker: CompletionRanker, typed: String = "chick") async -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return await ranker.rank(typed: typed, options: options, past: ["Chicken breast"], at: noon, calendar: calendar)
    }

    @Test func theModelOrdersButNeverAdds() {
        #expect(CompletionChoice.apply([3, 1], to: options) == ["chicken soup", "chicken", "chicken breast"])
    }

    @Test func numbersThatArentSuggestionsAndRepeatsAreIgnored() {
        #expect(CompletionChoice.apply([9, 0, -1, 2, 2], to: options) == ["chicken breast", "chicken", "chicken soup"])
        #expect(CompletionChoice.apply([], to: options) == options)
    }

    @Test func thePromptCarriesWhatWasEatenAndTheTime() {
        let prompt = CompletionChoice.prompt(typed: "chick", options: options, past: ["Oats"], part: "morning")
        #expect(prompt.contains("Time: morning"))
        #expect(prompt.contains("- Oats"))
        #expect(prompt.contains("2. chicken breast"))
    }

    @Test func aPersonWithNoHistoryStillGetsAPrompt() {
        #expect(CompletionChoice.prompt(typed: "ch", options: options, past: [], part: "evening").contains("- nothing yet"))
    }

    @Test(arguments: [(7, "morning"), (12, "midday"), (16, "afternoon"), (19, "evening"), (23, "late night")])
    func theTimeOfDayIsNamed(hour: Int, part: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: hour)))
        #expect(CompletionChoice.part(of: date, calendar: calendar) == part)
    }

    @Test func aFailureLeavesTheSearchsOrder() async {
        let ranker = CompletionRanker(model: ScriptedModel { throw MealAIError.busy })
        #expect(await rank(ranker) == options)
    }

    @Test func aSlowModelLeavesTheSearchsOrder() async {
        let model = ScriptedModel {
            try await Task.sleep(for: .seconds(30))
            return [3, 2, 1]
        }
        let ranker = CompletionRanker(model: model, budget: .milliseconds(20))
        #expect(await rank(ranker) == options)
    }

    @Test func anAnswerIsntPaidForTwice() async {
        let model = ScriptedModel { [3, 2, 1] }
        let ranker = CompletionRanker(model: model)
        #expect(await rank(ranker).first == "chicken soup")
        #expect(await rank(ranker).first == "chicken soup")
        #expect(model.asked.withLock { $0 } == 1)
        _ = await rank(ranker, typed: "chicke")
        #expect(model.asked.withLock { $0 } == 2)
    }

    @Test func oneOptionNeedsNoModel() async {
        let model = ScriptedModel { [] }
        let one = await CompletionRanker(model: model).rank(typed: "ch", options: ["chicken"], past: [], at: noon, calendar: .current)
        #expect(one == ["chicken"])
        #expect(model.asked.withLock { $0 } == 0)
    }
}
