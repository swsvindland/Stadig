import Foundation
import FoundationModels

/// A search's suggestions put in the order this person is likeliest to want, from what they've
/// logged and the time of day. On the device only: it runs on what's being typed and on the
/// person's own log, and a search shouldn't spend Private Cloud Compute's quota or need a connection.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
public actor SearchCompletionAI {
    private let ranker: CompletionRanker

    public init() {
        ranker = CompletionRanker(model: FoundationMealModel(engine: .onDevice, model: SystemLanguageModel.default, pool: SessionPool()))
    }

    /// Call when a search is about to start.
    public func prewarm() async { await ranker.prewarm() }

    /// `options` reordered, never added to; as they came when the model can't answer in time.
    public func rank(typed: String, options: [String], past: [String], at date: Date, calendar: Calendar = .current) async -> [String] {
        await ranker.rank(typed: typed, options: options, past: past, at: date, calendar: calendar)
    }
}
