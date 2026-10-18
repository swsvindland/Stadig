import FoodDatabase
import Foundation
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
        for (field, value) in guess.values where printed.contains(value, as: field) { values[field.key] = value }
        let grams = guess.servingGrams.flatMap { printed.contains($0) ? $0 : nil }
        // "2/3 cup (55g)" is measured as 2/3 cup; a serving given only by weight has no measure.
        let measure = guess.servingSize.flatMap { size -> String? in
            let head = size.split(separator: "(", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            let numbers = LabelAssist.numbers(in: [head])
            guard !head.isEmpty, !numbers.isEmpty, numbers.allSatisfy(printed.contains),
                !head.lowercased().hasSuffix("g"), !head.lowercased().hasSuffix("ml")
            else { return nil }
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
        let brand = Brands.clean(reply.brand, limit: 60)
        let facts = SupplementFacts(
            id: "custom:\(UUID().uuidString)", name: name ?? "", brand: brand, servingCount: serving?.count ?? 1,
            unit: serving?.unit ?? "serving", ingredients: ingredients, source: .label)
        return SupplementCheck(name: name, brand: brand, facts: facts)
    }

    /// The amounts printed in some text, with words for small counts ("two softgels"). A % Daily
    /// Value is not an amount, so it never vouches for one.
    struct Printed {
        let lines: [String]
        let numbers: [Double]

        init(_ lines: [String]) {
            self.lines = lines
            numbers =
                LabelAssist.amounts(in: lines)
                + Self.words.filter { word, _ in
                    lines.contains { $0.lowercased().contains(word) }
                }.map(\.value)
        }

        func contains(_ value: Double) -> Bool {
            value.isFinite && value >= 0 && numbers.contains { abs($0 - value) < 0.01 }
        }

        /// The value is printed on the field's own row: "Total Sugars 12g" for sugar, not "Includes
        /// 10g Added Sugars", and not another row's number. A model that mixes up two rows would
        /// otherwise pass, and its value counts twice against the frames' reads.
        func contains(_ value: Double, as field: LabelGuess.Field) -> Bool {
            guard value.isFinite, value >= 0, let row = Self.rows[field] else { return false }
            for (i, line) in lines.enumerated() {
                guard let label = row.firstRange(in: line) else { continue }
                let end = Self.rowEnd(of: field, in: line, after: label.upperBound)
                // "Calories per gram: Fat 9 Carbohydrate 4" is a footnote up to the row; "Calories
                // from Fat 70" and "Sodium Less than 2,400mg" name the row, not its amount.
                if Self.footnote.matches(String(line[..<end])) || Self.notAmount.matches(String(line[label.lowerBound..<end])) { continue }
                var amounts = LabelAssist.amounts(in: [String(line[label.upperBound..<end])])
                // A big number can land on a line of its own, under its label.
                if amounts.isEmpty, i + 1 < lines.count {
                    let next = lines[i + 1]
                    if !Self.footnote.matches(next), !Self.notAmount.matches(next), !Self.rowStarts.contains(where: { $0.matches(next) }) {
                        amounts = LabelAssist.amounts(in: [next])
                    }
                }
                if amounts.contains(where: { abs($0 - value) < 0.01 }) { return true }
            }
            return false
        }

        /// Where a field's row ends on a line OCR joined with more: at another row's label, or once
        /// its amount is past at its own label again or a footnote, so a bilingual "Total Fat / Grasa
        /// Total 8g" is one row, "Calories 250 Calories from Fat 110" two, and a linear label's
        /// "Protein 2g. *Percent Daily Values are based on a 2,000 calorie diet" keeps its protein.
        private static func rowEnd(of field: LabelGuess.Field, in line: String, after start: String.Index) -> String.Index {
            let amount = line[start...].firstIndex(where: \.isNumber) ?? line.endIndex
            let others = rows.filter { $0.key != field }.map(\.value) + [otherRows]
            let past = [rows[field], footnote].compactMap { $0?.firstRange(in: line, from: amount)?.lowerBound }
            return (others.compactMap { $0.firstRange(in: line, from: start)?.lowerBound } + past).min() ?? line.endIndex
        }

        private static let words: [String: Double] = ["one": 1, "two": 2, "three": 3, "four": 4]

        // The row labels FoodDatabase's NutritionLabel reads the panel with (private there, so copied).
        private static let rows: [LabelGuess.Field: Pattern] = [
            .kcal: Pattern(#"\bcalories\b|\bcal[oó]r[ií]as\b"#),
            .fat: Pattern(#"\btotal\s*fat\b|\bfat,?\s*total\b|\bgrasa\s*total\b|^fat\b"#),
            .saturatedFat: Pattern(#"\bsat(?:urated|\.)?\s*fat\b"#),
            .carbs: Pattern(#"\btotal\s*carb(?:ohydrates?|s|\.)?|\bcarbohydrates?\b|\bcarbs?\b\.?"#),
            .fiber: Pattern(#"\b(?:dietary\s*)?fib(?:er|re)\b"#),
            // "Includes 10g Added Sugars" and "Sugar Alcohol" are other rows.
            .sugar: Pattern(#"\btotal\s*sugars?\b|^sugars?\b(?!\s*alc)"#),
            .protein: Pattern(#"\bprotein\b|\bprote[ií]nas?\b"#),
            .sodium: Pattern(#"\bsodium\b"#),
        ]
        /// The panel's other rows, which end a joined row too: "Total Sugars 12g (Incl. 10g Added
        /// Sugars)", "Protein 3g Vitamin D 2mcg".
        private static let otherRows = Pattern(
            #"\btrans\.?\s*fat\b|\bcholest(?:erol|\.)?|\bincl(?:udes|\.)?(?!\w)|\badded\s*sugars?\b|\bsugars?\b|\bvit(?:amin|\.)?\s*[a-z](?:\d|\b)"#
                + #"|\bcalcium\b|\biron\b|\bpotas(?:sium|\.)?|\bfat\s*cal\b|\bcalories\s*from\s*fat\b"#)
        private static let rowStarts = Array(rows.values) + [otherRows]
        /// Footnote lines, whose numbers are never this food's: "Calories per gram: Fat 9 …", "a
        /// 2,000 calorie diet".
        private static let footnote = Pattern(#"per\s*gram|calorie\s*diet|calories\s*a\s*day"#)
        /// Rows that name a nutrient without giving this food's amount. A % Daily Value needs no
        /// entry: `LabelAssist.amounts` never reads one, so "Total Fat 7g (9% DV)" still gives 7.
        private static let notAmount = Pattern(#"from\s*fat|fat\s*cal\b|lowered|less\s*than\s*\d[\d,]+"#)
    }
}
