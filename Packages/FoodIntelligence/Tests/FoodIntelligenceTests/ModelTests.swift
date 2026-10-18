import Foundation
import FoundationModels
import Synchronization
import Testing
@testable import FoodIntelligence

@Suite("Model requests")
struct ModelTests {
    /// Runs `Retry.whileBusy` over scripted failures, recording each pause instead of sleeping.
    func retry(_ failures: [any Error], classify: (any Error) -> MealAIError = { $0 as? MealAIError ?? .failed("?") },
               pause: (Duration) async throws -> Void = { _ in }) async -> (Result<Int, any Error>, tries: Int, pauses: [Duration]) {
        let tries = Mutex(0), pauses = Mutex<[Duration]>([])
        let result: Result<Int, any Error>
        do {
            let value = try await Retry.whileBusy(classify: classify, pause: { duration in
                pauses.withLock { $0.append(duration) }
                try await pause(duration)
            }) {
                let attempt = tries.withLock { count in
                    count += 1
                    return count
                }
                if attempt <= failures.count { throw failures[attempt - 1] }
                return attempt
            }
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        return (result, tries.withLock { $0 }, pauses.withLock { $0 })
    }

    @Test func aBusyModelIsAskedTwiceMoreThenReportedBusy() async throws {
        let recovered = await retry([MealAIError.busy, MealAIError.busy])
        #expect(try recovered.0.get() == 3)
        #expect(recovered.pauses == [.milliseconds(400), .milliseconds(1000)])
        let busy = await retry([MealAIError.busy, MealAIError.busy, MealAIError.busy, MealAIError.busy])
        #expect(busy.tries == 3)
        #expect(busy.0.failureValue as? MealAIError == .busy)
    }

    @Test func otherFailuresAndCancellationComeOutAtOnce() async {
        let refused = await retry([MealAIError.refused])
        #expect(refused.tries == 1 && refused.pauses.isEmpty)
        #expect(refused.0.failureValue as? MealAIError == .refused)
        // Whatever the classifier makes of it.
        let other = await retry([CocoaError(.fileNoSuchFile)], classify: { _ in .failed("x") })
        #expect(other.0.failureValue as? MealAIError == .failed("x"))
        let cancelled = await retry([CancellationError()])
        #expect(cancelled.tries == 1 && cancelled.0.failureValue is CancellationError)
        // Cancelled while waiting to ask again.
        let waiting = await retry([MealAIError.busy], pause: { _ in throw CancellationError() })
        #expect(waiting.tries == 1 && waiting.0.failureValue is CancellationError)
    }

    @Test @available(macOS 27.0, iOS 27.0, *)
    func everyLiveCheckLeavesAWarmSessionForTheNext() async throws {
        let label = #"{"name": "Oat crunch", "brand": "", "calories": 230, "protein": 3}"#
        let script = ScriptedLanguageModel.Script([label, label])
        let pool = SessionPool()
        let model = FoundationMealModel(engine: .onDevice, model: ScriptedLanguageModel(script), pool: pool)
        let guess = try await model.checkLabel(text: "Panel text:\nCalories 230\nProtein 3g")
        #expect(guess.values == [.kcal: 230, .protein: 3])
        #expect(script.prewarms.withLock { $0 } == 1, "the next check's session is prewarmed")
        _ = try await model.checkLabel(text: "Panel text:\nCalories 230")
        // The second check took that session and left another; nothing piles up.
        #expect(script.prewarms.withLock { $0 } == 2)
        #expect(await pool.take(Prompts.liveLabelInstructions) != nil)
        #expect(await pool.take(Prompts.liveLabelInstructions) == nil)

        let supplement = ScriptedLanguageModel.Script([#"{"name": "Fish oil", "brand": "", "lines": []}"#])
        let supplements = SessionPool()
        _ = try await FoundationMealModel(engine: .onDevice, model: ScriptedLanguageModel(supplement), pool: supplements)
            .checkSupplement(text: "Panel text:\nSupplement Facts")
        #expect(await supplements.take(Prompts.liveSupplementInstructions) != nil)
    }
}

extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
