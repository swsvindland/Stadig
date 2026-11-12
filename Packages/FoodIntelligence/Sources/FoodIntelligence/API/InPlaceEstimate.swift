import FoodDatabase
import Foundation
import SystemCore

/// Words typed on Today that no food matched, read by the model and logged where they were typed,
/// with no review in between: every food it named that the catalog has goes in as an estimate (to
/// confirm with "Looks right", or change), and what it named that the catalog hasn't is said on the
/// thread, a tap from the logger.
public enum InPlaceEstimate {
    /// What a read of the words comes to.
    public enum Outcome: Sendable {
        /// Foods to log, the weak matches too (each goes in as an estimate, to confirm or change), and
        /// what the model named that nothing in the catalog matched.
        case foods([GuessedItem], missed: [String])
        /// Nothing to log, and why, in words for the row.
        case nothing(String)
    }

    /// The foods to log from a read of `words`. A food with no catalog match, no unit or no amount
    /// can't be logged: it's missed. With nothing left, the row says why.
    public static func outcome(of guess: MealGuess, words: String) -> Outcome {
        let loggable = guess.items.filter(isLoggable)
        var missed: [String] = []
        for item in guess.items where !isLoggable(item) {
            let name = item.seenName.trimmingCharacters(in: .whitespacesAndNewlines)
            // "Salsa" twice is one thing nothing matched.
            if !name.isEmpty, !missed.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { missed.append(name) }
        }
        guard loggable.isEmpty else { return .foods(loggable, missed: missed) }
        guard !missed.isEmpty else { return .nothing("The model couldn't name a food in it. Try naming each one.") }
        return .nothing("Nothing in the catalog for \(spoken(missed)). Find it in the logger.")
    }

    /// What's said on the thread under foods the model named that the catalog hasn't (the row names
    /// them), when the rest of `words` went in: "Not in the catalog. Part of “burrito bowl”."
    public static func missing(from words: String) -> String {
        "Not in the catalog. Part of “\(words)”."
    }

    /// "salsa verde", "salsa verde and crema", "rice, salsa verde and crema".
    public static func spoken(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return "\(names.dropLast().joined(separator: ", ")) and \(last)"
    }

    private static func isLoggable(_ item: GuessedItem) -> Bool {
        item.match != nil && item.unit != nil && item.count > 0 && item.count.isFinite
    }
}

extension GuessedItem {
    /// How sure an entry made from it is (an entry's `confidence`, which marks it an estimate): a sure
    /// match at an amount the person said is 0.8, a weak match or the model's own amount 0.5.
    public var confidence: Double { sure && !approximate ? 0.8 : 0.5 }
}
