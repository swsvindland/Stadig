import Foundation
import SystemCore

/// Words typed on Today that matched no food, worked out by Apple's model on the thread: a row that
/// says so at once, then the foods it found logged in its place (estimates, until "Looks right"), or
/// why there's nothing, with the way to the logger.
public struct ThreadEstimate: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// The model is reading the words.
        case working
        /// Its foods are logged, by id, waiting for "Looks right".
        case logged([UUID])
        /// Nothing to log, and why, in words.
        case failed(String)
    }

    public var id: UUID
    /// What was typed: what the logger opens with, if it comes to that.
    public var words: String
    /// When Return was pressed. What's found is logged then, with the meal it was typed with, not
    /// when the model answered.
    public var asked: Date
    public var state: State

    public init(id: UUID = UUID(), words: String, asked: Date, state: State = .working) {
        self.id = id
        self.words = words
        self.asked = asked
        self.state = state
    }

    /// Still a row of its own on the thread (working, or failed), rather than foods.
    public var isRow: Bool {
        if case .logged = state { return false }
        return true
    }

    /// Whether any of `entries` are its foods, waiting for "Looks right".
    public func logs(any entries: [FoodEntry]) -> Bool {
        guard case .logged(let ids) = state else { return false }
        return entries.contains { ids.contains($0.id) }
    }
}

public enum ThreadEstimates {
    /// The estimates still on today's thread: those asked today, and of the logged ones only the foods
    /// still in the log, so an Undo or a delete takes the estimate with them.
    public static func current(_ estimates: [ThreadEstimate], entries: [FoodEntry], today: Day, calendar: Calendar = .current) -> [ThreadEstimate] {
        let present = Set(entries.lazy.filter { $0.day == today }.map(\.id))
        return estimates.compactMap { estimate in
            guard Day(estimate.asked, calendar: calendar) == today else { return nil }
            guard case .logged(let ids) = estimate.state else { return estimate }
            let kept = ids.filter(present.contains)
            guard !kept.isEmpty else { return nil }
            var estimate = estimate
            estimate.state = .logged(kept)
            return estimate
        }
    }

    /// The foods waiting for "Looks right".
    public static func unconfirmed(_ estimates: [ThreadEstimate]) -> Set<UUID> {
        Set(
            estimates.flatMap { estimate -> [UUID] in
                guard case .logged(let ids) = estimate.state else { return [] }
                return ids
            })
    }

    /// The estimates once `ids` are confirmed: those foods no longer wait, and an estimate with none
    /// left waiting is done.
    public static func confirming(_ ids: Set<UUID>, in estimates: [ThreadEstimate]) -> [ThreadEstimate] {
        estimates.compactMap { estimate in
            guard case .logged(let logged) = estimate.state else { return estimate }
            let left = logged.filter { !ids.contains($0) }
            guard !left.isEmpty else { return nil }
            var estimate = estimate
            estimate.state = .logged(left)
            return estimate
        }
    }
}

extension FoodEntry {
    /// "Looks right": the same food and numbers, no longer an estimate, and its amount without the ≈.
    public func confirmed(at now: Date, calendar: Calendar = .current) -> FoodEntry {
        edited(at: now, calendar: calendar) { entry in
            entry.confidence = nil
            if entry.amountLabel.hasPrefix("≈ ") { entry.amountLabel.removeFirst(2) }
        }
    }
}
