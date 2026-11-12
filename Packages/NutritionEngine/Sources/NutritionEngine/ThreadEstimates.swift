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
        /// Its foods, worked out but not logged: the words were too vague to log a guess at without
        /// asking (`VagueWords`). "Log" logs them as they are; nothing else does.
        case proposed([FoodEntry])
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
    /// Whether what the model finds waits to be asked about rather than going straight in: words
    /// that name no food ("whatever was in the fridge") leave the model to invent one.
    public var asksFirst: Bool

    public init(id: UUID = UUID(), words: String, asked: Date, state: State = .working, asksFirst: Bool? = nil) {
        self.id = id
        self.words = words
        self.asked = asked
        self.state = state
        self.asksFirst = asksFirst ?? VagueWords.isVague(words)
    }

    /// The foods waiting to be logged, if the words were too vague to log them without asking.
    public var proposal: [FoodEntry]? {
        if case .proposed(let entries) = state { return entries }
        return nil
    }

    /// Still a row of its own on the thread (working, waiting to be asked about, or failed), rather
    /// than foods.
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

/// Words that don't say what was eaten. Read by the model they come back as foods it made up
/// ("whatever was in the fridge" was 951 kcal of beans, chicken and rice), so what it finds is
/// shown and asked about, not logged.
public enum VagueWords {
    /// Words that stand in for food rather than name it: any of them makes the words vague.
    static let standIns: Set<String> = [
        "whatever", "something", "anything", "everything", "stuff", "things", "thing", "random", "fridge", "freezer",
        "bits", "odds", "ends", "misc", "miscellaneous",
    ]
    /// Words that only say a meal happened. Words that are only these (and fillers) are vague.
    static let mealsOnly: Set<String> = [
        "breakfast", "brunch", "lunch", "dinner", "supper", "tea", "meal", "meals", "snack", "snacks", "food", "foods",
        "leftover", "leftovers", "takeout", "takeaway", "buffet", "eating", "dessert",
    ]
    /// Words that say nothing about the food.
    static let fillers: Set<String> = [
        "a", "an", "the", "some", "my", "our", "of", "at", "from", "out", "in", "on", "for", "with", "and", "to", "was", "were",
        "had", "ate", "eat", "have", "got", "big", "small", "little", "light", "large", "huge", "late", "early", "quick",
        "fast", "normal", "usual", "typical", "regular", "home", "work", "office", "restaurant", "party", "friends",
        "today", "tonight", "yesterday", "again", "bit", "lot", "lots", "plate", "bowl", "kind", "sort", "like", "just",
        "ish", "i", "we", "it", "left", "over",
    ]

    /// Whether `words` name no food: a stand-in for food ("something sweet", "stuff from the
    /// fridge"), or nothing but a meal ("a big dinner", "lunch out", "fast food", "leftovers").
    /// "Leftover pizza" and "chicken dinner" name a food, so they aren't.
    public static func isVague(_ words: String) -> Bool {
        let tokens = words.lowercased()
            .split { !$0.isLetter && $0 != "'" }
            .map { String($0).replacing("'s", with: "") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return false }
        if tokens.contains(where: standIns.contains) { return true }
        return tokens.allSatisfy { fillers.contains($0) || mealsOnly.contains($0) }
    }
}
