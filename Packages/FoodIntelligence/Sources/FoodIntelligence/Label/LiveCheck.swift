import Foundation
import FoodDatabase
import SystemCore

/// What a model read in the text a live scan gathered: the product's name, and panel values it
/// copied, kept only where the number is printed in the panel's text. The model may read, never
/// invent.
public struct LabelCheck: Sendable, Equatable {
    public var name: String?
    public var brand: String?
    /// By key ("kcal", "protein", "sodium"…), in the label's units.
    public var values: [String: Double]
    /// The household measure ("2/3 cup") and the serving's weight, when printed.
    public var servingLabel: String?
    public var servingGrams: Double?
}

/// The same for a Supplement Facts panel: only the lines Macro Track tracks, with printed amounts.
public struct SupplementCheck: Sendable {
    public var name: String?
    public var brand: String?
    public var facts: SupplementFacts
}

/// A supplement panel as the model returned it, before it's checked.
struct SupplementReply: Sendable {
    struct Line: Sendable {
        var name: String
        var amount: Double
        var unit: String
    }

    var name: String?
    var brand: String?
    var servingSize: String?
    var lines: [Line]
}

enum LiveCheck {
    /// Keeps the values printed in the panel's text, and the name.
    static func label(_ guess: LabelGuess, panel: [String]) -> LabelCheck {
        let printed = Printed(panel)
        var values: [String: Double] = [:]
        for (field, value) in guess.values where printed.contains(value) { values[field.key] = value }
        let grams = guess.servingGrams.flatMap { printed.contains($0) ? $0 : nil }
        // "2/3 cup (55g)" is measured as 2/3 cup; a serving given only by weight has no measure.
        let measure = guess.servingSize.flatMap { size -> String? in
            let head = size.split(separator: "(", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            let numbers = LabelAssist.numbers(in: [head])
            guard !head.isEmpty, !numbers.isEmpty, numbers.allSatisfy(printed.contains),
                  !head.lowercased().hasSuffix("g"), !head.lowercased().hasSuffix("ml") else { return nil }
            return head
        }
        return LabelCheck(name: guess.name, brand: guess.brand, values: values, servingLabel: measure, servingGrams: grams)
    }

    /// Keeps the tracked lines whose amount is printed in the panel's text, and the serving.
    static func supplement(_ reply: SupplementReply, panel: [String]) -> SupplementCheck {
        let printed = Printed(panel)
        let ingredients = reply.lines.compactMap { line -> SupplementIngredient? in
            guard printed.contains(line.amount) else { return nil }
            let ingredient = SupplementIngredient(name: line.name, amount: line.amount, unit: line.unit)
            return ingredient.isTracked ? ingredient : nil
        }
        let serving = reply.servingSize.flatMap(SupplementServing.parse).flatMap { printed.contains($0.count) ? $0 : nil }
        let name = reply.name.map { FoodText.clean($0, limit: 60) }.flatMap { $0.isEmpty ? nil : $0 }
        let brand = reply.brand.map { FoodText.clean($0, limit: 60) }.flatMap { $0.isEmpty || $0.lowercased() == "none" ? nil : $0 }
        let facts = SupplementFacts(id: "custom:\(UUID().uuidString)", name: name ?? "", brand: brand, servingCount: serving?.count ?? 1,
                                    unit: serving?.unit ?? "serving", ingredients: ingredients, source: .label)
        return SupplementCheck(name: name, brand: brand, facts: facts)
    }

    /// The numbers printed in some text, with words for small counts ("two softgels").
    struct Printed {
        let numbers: [Double]

        init(_ lines: [String]) {
            numbers = LabelAssist.numbers(in: lines) + Self.words.filter { word, _ in
                lines.contains { $0.lowercased().contains(word) }
            }.map(\.value)
        }

        func contains(_ value: Double) -> Bool {
            value.isFinite && value >= 0 && numbers.contains { abs($0 - value) < 0.01 }
        }

        private static let words: [String: Double] = ["one": 1, "two": 2, "three": 3, "four": 4]
    }
}
