import Foundation
import SystemCore

/// Reads a Supplement Facts panel from OCR lines: the serving ("Serving Size 2 Softgels") and each
/// line's name and first amount ("Vitamin D3 (as cholecalciferol) 25 mcg (1,000 IU) 125%" is 25 mcg
/// of vitamin D3). A name wrapped onto its own line joins the amount on the next. Stops at "Other
/// ingredients", directions and warnings. Everything read is for the person to confirm.
public enum SupplementLabel {
    /// The panel's serving and lines, or nil when the text isn't a Supplement Facts panel. The name
    /// and brand are left for the person (or a model) to fill in.
    public static func parse(lines: [String]) -> SupplementFacts? {
        var ingredients: [SupplementIngredient] = []
        var serving: (count: Double, unit: String)?
        var heading = false
        var pending: String?
        var started = false
        for raw in lines {
            let line = NutritionLabel.digits(raw.split(whereSeparator: \.isWhitespace).joined(separator: " "))
            guard !line.isEmpty else { continue }
            if facts.test(line) {
                heading = true
                started = true
                ingredients.removeAll()
                pending = nil
                continue
            }
            if stop.test(line) {
                if started && !ingredients.isEmpty { break }
                continue
            }
            if servingSize.test(line) {
                serving = SupplementServing.parse(line)
                started = true
                pending = nil
                continue
            }
            if skip.test(line) {
                pending = nil
                continue
            }
            guard let match = amount.first(in: line), let value = number(match) else {
                if let calories = caloriesLine(line) {
                    ingredients.append(calories)
                    started = true
                    pending = nil
                    continue
                }
                // A name on a line of its own, wrapped before its amount.
                let words = line.trimmingCharacters(in: edge)
                if words.unicodeScalars.contains(where: CharacterSet.letters.contains), words.count <= 60 {
                    pending = pending.map { "\($0) \(words)" } ?? words
                    if (pending?.count ?? 0) > 80 { pending = words }
                } else {
                    pending = nil
                }
                continue
            }
            var name = String(line[..<match.range.lowerBound]).trimmingCharacters(in: edge)
            if let earlier = pending, name.isEmpty || name.hasPrefix("(") || name.first?.isLowercase == true {
                name = name.isEmpty ? earlier : "\(earlier) \(name)"
            }
            pending = nil
            guard name.unicodeScalars.contains(where: CharacterSet.letters.contains) else { continue }
            started = true
            var unit = match[3] ?? ""
            var quantity = value
            if unit.lowercased().hasPrefix("billion") {
                unit = "billion CFU"
            } else if unit.lowercased().hasPrefix("million") {
                unit = "CFU"
                quantity *= 1_000_000
            }
            ingredients.append(SupplementIngredient(name: String(name.prefix(80)), amount: quantity, unit: unit))
        }
        let read = ingredients.filter { $0.amount != nil }
        guard !read.isEmpty, heading || read.count >= 2 || serving != nil else { return nil }
        // Every line read says it's a panel; only the ones Macro Track tracks are kept.
        return SupplementFacts(
            id: "custom:\(UUID().uuidString)", name: "", servingCount: serving?.count ?? 1,
            unit: serving?.unit ?? "serving", ingredients: read.filter(\.isTracked), source: .label)
    }

    /// "Calories 20": the one line whose amount has no unit.
    private static func caloriesLine(_ line: String) -> SupplementIngredient? {
        guard let match = calories.first(in: line), let text = match[1], let value = Double(text.replacingOccurrences(of: ",", with: "")),
            value <= 2000
        else { return nil }
        return SupplementIngredient(name: "Calories", amount: value, unit: "kcal")
    }

    private static func number(_ match: Pattern.Match) -> Double? {
        guard let text = match[2], var value = Double(text.replacingOccurrences(of: ",", with: "")) else { return nil }
        // "<1 g" is half its bound, as on nutrition labels.
        if match[1] != nil { value /= 2 }
        return value
    }

    private static let edge = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".…:·-–—*†‡"))
    private static let facts = Pattern(#"supp?lement\s*fact|^dietary\s*supplement\s*facts"#, ignoringCase: true)
    private static let servingSize = Pattern(#"serv(?:ing)?\.?\s*s[i1l]ze"#, ignoringCase: true)
    private static let skip = Pattern(
        #"servings?\s*per|amount\s*per|%\s*d(?:aily)?\s*v|^%|^daily\s*value$|^each\s*(?:serving|softgel|capsule|tablet)"#,
        ignoringCase: true)
    private static let stop = Pattern(
        #"^other\s*ingredients|^ingredients\s*:|suggested\s*use|^directions|^warnings?\b|^caution|keep\s*out\s*of|daily\s*value\s*(?:not|is\s*not)|percent\s*daily\s*values?\s*(?:are|based)|^distributed|^manufactured|^contains\s*:|^allergen"#,
        ignoringCase: true)
    /// An amount with its unit, not glued to a word before it ("B12", "CoQ10", "MK-7" aren't amounts).
    /// OCR often reads a dagger after the unit as "t" ("650 mgt").
    private static let amount = Pattern(
        #"(?<![\p{L}\d.\-])(<|less\s*than\s*)?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(mcg\s*DFE|mcg\s*RAE|mg\s*NE|mg\s*α-?TE|billion\s*CFU|million\s*CFU|mcg|µg|μg|ug|mg|g|IU|I\.U\.|CFU|kcal|mL|ml)(?:[t+](?=\s|$))?(?![\p{L}])"#,
        ignoringCase: true)
    private static let calories = Pattern(#"^calories\s+(\d{1,4})\b"#, ignoringCase: true)
}
