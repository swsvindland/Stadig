import Foundation
import SystemCore

/// A lift whose estimated one-rep max a session raised, from what it was going in to what it is
/// after: the Watch's finished face says what moved. Both are the estimator's current estimate (the
/// best of the last three sessions), so a session that only matched a recent best moves nothing.
public struct EstimateMove: Hashable, Sendable {
    public var exerciseID: String
    public var beforeKg: Double
    public var afterKg: Double

    /// Less than this much of a rise is noise, not a move.
    static let threshold = 0.01

    /// The session's lifts that moved, in the order they were done. `history` is what was known going
    /// in (it may hold only recent sessions); `basis` gives each exercise's load basis, nil for one
    /// the catalog doesn't know. A lift with no estimate going in has nothing to move from.
    public static func moves(
        history: [String: [LoggedSet]], session: [LoggedSet], trust: TrustState, basis: (String) -> LoadBasis?
    ) -> [EstimateMove] {
        var order: [String] = []
        for set in session where !order.contains(set.exerciseID) { order.append(set.exerciseID) }
        return order.compactMap { id in
            guard let basis = basis(id) else { return nil }
            let before = history[id] ?? []
            let today = session.filter { $0.exerciseID == id }
            guard let was = StrengthEstimator.current(before, basis: basis, trust: trust),
                let now = StrengthEstimator.current(before + today, basis: basis, trust: trust), now > was * (1 + threshold)
            else { return nil }
            return EstimateMove(exerciseID: id, beforeKg: was, afterKg: now)
        }
    }
}
