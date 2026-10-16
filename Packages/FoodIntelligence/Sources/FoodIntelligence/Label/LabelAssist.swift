import Foundation
import FoodDatabase
import SystemCore

/// What the model read from a label's text: a name, and printed values when asked.
struct LabelGuess: Sendable, Equatable {
    enum Field: String, CaseIterable, Sendable {
        case kcal, fat, saturatedFat, carbs, fiber, sugar, protein, sodium

        /// The key FoodDatabase lists a missing nutrient under.
        var key: String { rawValue }
    }

    var name: String?
    var brand: String?
    var servingSize: String?
    var servingGrams: Double?
    var values: [Field: Double]

    init(name: String?, brand: String?, servingSize: String? = nil, servingGrams: Double? = nil, values: [Field: Double] = [:]) {
        self.name = name.map { FoodText.clean($0, limit: 60) }?.nilIfEmpty
        self.brand = brand.map { FoodText.clean($0, limit: 60) }?.nilIfEmpty.flatMap { Self.noBrand.matches($0) ? nil : $0 }
        self.servingSize = servingSize.map { FoodText.clean($0, limit: 40) }?.nilIfEmpty
        self.servingGrams = servingGrams
        self.values = values
    }

    private static let noBrand = Pattern(#"^(?:none|n/?a|unknown|generic|-)$"#)
}

/// Fills gaps in a thin label parse with values the model copied, keeping only numbers that are
/// actually printed in the OCR text: the model may read, never invent.
enum LabelAssist {
    /// Fewer fields than this and the parse is worth a second reader.
    static let thinFields = 4

    static func isThin(_ reading: LabelReading?) -> Bool { (reading?.fieldsRead ?? 0) < thinFields }

    static func fill(_ reading: LabelReading?, with guess: LabelGuess, lines: [String]) -> LabelReading? {
        let printed = numbers(in: lines)
        func verified(_ value: Double?) -> Double? {
            guard let value, value >= 0, value.isFinite else { return nil }
            return printed.contains { abs($0 - value) < 0.01 } ? value : nil
        }
        let values = guess.values.compactMapValues(verified)
        let grams = verified(guess.servingGrams)
        let serving = guess.servingSize.flatMap { size in numbers(in: [size]).allSatisfy { verified($0) != nil } ? size : nil }

        guard var reading else {
            let kcal = values[.kcal]
            let macros = [values[.fat], values[.carbs], values[.protein]]
            // Calories, or all three macros to count them from; anything less is not a label read.
            guard kcal != nil || !macros.contains(where: { $0 == nil }) else { return nil }
            var nutrients = Nutrients(kcal: 0, protein: values[.protein] ?? 0, carbs: values[.carbs] ?? 0, fat: values[.fat] ?? 0,
                                      fiber: values[.fiber], sugar: values[.sugar], saturatedFat: values[.saturatedFat], sodium: values[.sodium])
            nutrients.kcal = kcal ?? nutrients.macroKcal
            return LabelReading(servingLabel: serving, servingGrams: grams, servingMilliliters: nil, nutrients: nutrients,
                                fieldsRead: values.count + (grams == nil ? 0 : 1), estimatedCalories: kcal == nil,
                                missing: LabelGuess.Field.allCases.filter { values[$0] == nil }.map(\.key))
        }
        var filled = 0
        func take(_ field: LabelGuess.Field) -> Double? {
            guard let value = values[field] else { return nil }
            reading.missing.removeAll { $0 == field.key }
            filled += 1
            return value
        }
        // A core value the parser missed is 0 and listed as missing; a calorie estimate gives way
        // to the printed number.
        let core: [(LabelGuess.Field, WritableKeyPath<Nutrients, Double>)] = [(.fat, \.fat), (.carbs, \.carbs), (.protein, \.protein)]
        for (field, keyPath) in core where reading.missing.contains(field.key) {
            if let value = take(field) { reading.nutrients[keyPath: keyPath] = value }
        }
        if reading.missing.contains("kcal") || reading.estimatedCalories, let value = take(.kcal) {
            reading.nutrients.kcal = value
            reading.estimatedCalories = false
        }
        let optional: [(LabelGuess.Field, WritableKeyPath<Nutrients, Double?>)] = [
            (.fiber, \.fiber), (.sugar, \.sugar), (.saturatedFat, \.saturatedFat), (.sodium, \.sodium),
        ]
        for (field, keyPath) in optional where reading.nutrients[keyPath: keyPath] == nil {
            if let value = take(field) { reading.nutrients[keyPath: keyPath] = value }
        }
        if reading.servingGrams == nil, let grams {
            reading.servingGrams = grams
            filled += 1
        }
        if reading.servingLabel == nil, let serving { reading.servingLabel = serving }
        reading.fieldsRead += filled
        return reading
    }

    private static let number = Pattern(#"\d+(?:[.,]\d+)*"#)

    /// Every number printed in the text, reading a comma as a thousands separator and as a decimal point.
    static func numbers(in lines: [String]) -> [Double] {
        lines.flatMap { line in
            number.allMatches(in: line).flatMap { match -> [Double] in
                let text = match[0]
                return [Double(text.replacingOccurrences(of: ",", with: "")), Double(text.replacingOccurrences(of: ",", with: "."))]
                    .compactMap { $0 }
            }
        }
    }
}
