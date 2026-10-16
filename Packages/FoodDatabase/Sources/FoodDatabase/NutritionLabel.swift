import Foundation
import SystemCore

/// A nutrition facts panel read from text lines (OCR).
public struct LabelReading: Hashable, Sendable {
    /// Something on the label that deserves a second look.
    public enum Warning: String, Hashable, Codable, Sendable {
        /// A part is more than its total, like sugars over carbs.
        case partOverTotal
        /// Calories don't match the fat, carbs and protein.
        case caloriesMismatch
    }

    /// The household measure as printed: "2/3 cup", "1 Package".
    public var servingLabel: String?
    public var servingGrams: Double?
    public var servingMilliliters: Double?
    /// Per serving. A core value the label didn't give is 0 here and listed in `missing`.
    public var nutrients: Nutrients
    public var extras: [String: Double]
    /// How many fields were read; low means a messy read.
    public var fieldsRead: Int
    /// Calories were missing and are estimated from fat, carbohydrate and protein.
    public var estimatedCalories: Bool
    public var warnings: [Warning]
    /// The nutrients the label didn't give, by key ("kcal", "protein", "fiber", "vitaminD"…).
    public var missing: [String]

    public init(servingLabel: String?, servingGrams: Double?, servingMilliliters: Double?, nutrients: Nutrients,
                extras: [String: Double] = [:], fieldsRead: Int, estimatedCalories: Bool = false, warnings: [Warning] = [],
                missing: [String] = []) {
        self.servingLabel = servingLabel
        self.servingGrams = servingGrams
        self.servingMilliliters = servingMilliliters
        self.nutrients = nutrients
        self.extras = extras
        self.fieldsRead = fieldsRead
        self.estimatedCalories = estimatedCalories
        self.warnings = warnings
        self.missing = missing
    }

    /// The label as a custom food, per 100 g/ml when the serving size is known (with the serving as
    /// a portion, so it logs by serving or by weight), else per serving.
    public func food(name: String, brand: String?, barcode: String?) -> Food {
        let measure = String((servingLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let servingName = measure.isEmpty ? "1 serving" : "1 serving (\(measure))"
        let weight = servingGrams ?? servingMilliliters
        let byWeight = weight.map { $0 > 0 && $0 <= 5000 } ?? false
        let basis: FoodBasis = byWeight ? (servingGrams != nil ? .g : .ml) : .serving
        let factor = byWeight ? 100 / weight! : 1
        let portions = byWeight ? [Portion(label: servingName, amount: weight!)] : measure.isEmpty ? [] : [Portion(label: servingName, amount: 1)]
        let code = barcode.flatMap { Barcode.keys(for: $0).first ?? $0 }
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Food(id: "custom:\(UUID().uuidString)", name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    brand: trimmedBrand?.isEmpty == false ? trimmedBrand : nil, barcode: code, basis: basis,
                    nutrients: nutrients.scaled(factor), extras: extras.mapValues { $0 * factor }, portions: portions, source: .label)
    }
}

/// One recognized text box, normalized to 0–1 with a top-left origin, as on-device OCR returns it.
public struct LabelTextBox: Hashable, Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var center: Double { y + height / 2 }
}

/// Reads a US Nutrition Facts panel from OCR. A nutrient's value is either in its own box ("Total
/// Fat 8g") or in the nearest box to its right ("Calories" … "230"). Handles two-column panels, the
/// older column format with units in the heading ("PROTEIN, g"), bilingual labels, "<1g" (read as
/// 0.5 g), "Includes 10g Added Sugars", and OCR's O for 0 and trailing g read as 9. Everything read
/// is for the person to confirm.
public enum NutritionLabel {
    /// Reads a US-style (and two-column) nutrition facts panel from OCR lines, or nil when the text
    /// isn't one. A value on the line after its name ("Calories" / "230") is read as that name's.
    public static func parse(lines: [String]) -> LabelReading? {
        var merged: [String] = []
        for line in lines {
            if let last = merged.last, isAmountOnly(line), last.unicodeScalars.contains(where: isLetter),
               !last.unicodeScalars.contains(where: isDigit) {
                merged[merged.count - 1] = "\(last) \(line)"
            } else {
                merged.append(line)
            }
        }
        return parse(boxes: merged.enumerated().map { LabelTextBox(text: $1, x: 0, y: Double($0) * 0.03, width: 1, height: 0.03) })
    }

    /// Reads a panel from OCR boxes with their positions, which splits like "Calories" … "230" and
    /// two-column cans need; nil when the text isn't a nutrition panel.
    public static func parse(boxes: [LabelTextBox]) -> LabelReading? {
        let values = read(boxes)
        return values.found ? values.reading : nil
    }

    // MARK: Reading

    struct Values {
        var amounts: [String: Double] = [:]
        var servingLabel = ""
        var servingAmount: Double?
        var servingUnit: String?
        var estimatedCalories = false
        var warnings: [LabelReading.Warning] = []

        /// Enough was read to be worth filling a form: calories or at least two macros.
        var found: Bool {
            (amounts["kcal"] != nil && !estimatedCalories) || ["fat", "carbs", "protein"].filter { amounts[$0] != nil }.count >= 2
        }

        var reading: LabelReading {
            let core = ["kcal", "protein", "carbs", "fat", "fiber", "sugar", "saturatedFat", "sodium"]
            let nutrients = Nutrients(kcal: amounts["kcal"] ?? 0, protein: amounts["protein"] ?? 0, carbs: amounts["carbs"] ?? 0,
                                      fat: amounts["fat"] ?? 0, fiber: amounts["fiber"], sugar: amounts["sugar"],
                                      saturatedFat: amounts["saturatedFat"], sodium: amounts["sodium"])
            return LabelReading(servingLabel: servingLabel.isEmpty ? nil : servingLabel,
                                servingGrams: servingUnit == "g" ? servingAmount : nil,
                                servingMilliliters: servingUnit == "ml" ? servingAmount : nil,
                                nutrients: nutrients, extras: amounts.filter { !core.contains($0.key) },
                                fieldsRead: amounts.count - (estimatedCalories ? 1 : 0), estimatedCalories: estimatedCalories,
                                warnings: warnings, missing: fields.map(\.key).filter { amounts[$0] == nil })
        }
    }

    /// What one camera frame shows of a panel: whatever values it reads, even one, with no
    /// calories worked out from the macros. Frames of a label too big for one photo are read one by
    /// one and put together by ``LiveLabel``.
    public static func frame(boxes: [LabelTextBox]) -> LabelFrame {
        let ordered = order(boxes)
        var values = scan(ordered)
        readServing(ordered, &values)
        let panel = values.amounts.count >= 2 || ordered.contains { panelWords.test($0.text) }
        return LabelFrame(amounts: values.amounts, servingLabel: values.servingLabel.isEmpty ? nil : values.servingLabel,
                          servingGrams: values.servingUnit == "g" ? values.servingAmount : nil,
                          servingMilliliters: values.servingUnit == "ml" ? values.servingAmount : nil, isPanel: panel)
    }

    /// A panel's own words, which a package's front doesn't print.
    private static let panelWords = Pattern(
        #"nutrition\s*facts|serv(?:ing)?\.?\s*size|daily\s*value|amount\s*per\s*serving|valeur\s*nutritive|informaci[oó]n\s*nutricional"#,
        ignoringCase: true)

    /// Values found on a label; missing nutrients stay unknown rather than zero.
    static func read(_ boxes: [LabelTextBox]) -> Values {
        let ordered = order(boxes)
        var values = scan(ordered)
        check(&values)
        readServing(ordered, &values)
        return values
    }

    /// Boxes top to bottom, then left to right.
    static func order(_ boxes: [LabelTextBox]) -> [LabelTextBox] {
        boxes.enumerated().sorted { a, b in
            a.element.y != b.element.y ? a.element.y < b.element.y : a.element.x != b.element.x ? a.element.x < b.element.x : a.offset < b.offset
        }.map(\.element)
    }

    /// Each nutrient's value, where the boxes give one.
    static func scan(_ ordered: [LabelTextBox]) -> Values {
        var values = Values()
        for field in fields { if let value = readField(field, ordered) { values.amounts[field.key] = value } }
        if let added = readAddedSugar(ordered) { values.amounts["addedSugar"] = added }
        return values
    }

    /// A part over its total, and calories that don't match the macros, flagged; calories worked
    /// out from the macros when the label didn't give them.
    static func check(_ values: inout Values) {
        let amounts = values.amounts
        func over(_ part: Double?, _ whole: Double?) -> Bool {
            guard let part, let whole else { return false }
            return part > whole + 0.5
        }
        if over(amounts["saturatedFat"], amounts["fat"]) || over(amounts["transFat"], amounts["fat"])
            || over(amounts["sugar"], amounts["carbs"]) || over(amounts["addedSugar"], amounts["sugar"] ?? amounts["carbs"]) {
            values.warnings.append(.partOverTotal)
        }
        var energy: Double?
        if let fat = amounts["fat"], let carbs = amounts["carbs"], let protein = amounts["protein"] { energy = 9 * fat + 4 * carbs + 4 * protein }
        if amounts["kcal"] == nil, let energy {
            values.amounts["kcal"] = energy.rounded()
            values.estimatedCalories = true
        } else if let calories = amounts["kcal"], let energy, abs(calories - energy) > max(25, calories * 0.25) {
            values.warnings.append(.caloriesMismatch)
        }
    }

    private struct Field {
        var key: String
        var label: Pattern
        var unit: String
        var implied: Pattern
        var plausible: Double

        init(_ key: String, _ label: String, _ unit: String, _ plausible: Double) {
            self.key = key
            self.label = Pattern(label, ignoringCase: true)
            self.unit = unit
            implied = Pattern(#"^[\s,.:]*\(?"# + (unit == "kcal" ? "g" : unit) + #"\b"#, ignoringCase: true)
            self.plausible = plausible
        }
    }

    private static let fields: [Field] = [
        Field("kcal", #"\bcalories\b|\bcal[oó]r[ií]as\b"#, "kcal", 2000),
        Field("fat", #"\btotal\s*fat\b|\bfat,?\s*total\b|\bgrasa\s*total\b|^fat\b"#, "g", 200),
        Field("carbs", #"\btotal\s*carb(?:ohydrates?|s|\.)?|\bcarbohydrates?\b|\bcarbs?\b\.?"#, "g", 300),
        Field("protein", #"\bprotein\b|\bprote[ií]nas?\b"#, "g", 200),
        Field("fiber", #"\b(?:dietary\s*)?fib(?:er|re)\b"#, "g", 100),
        Field("sodium", #"\bsodium\b"#, "mg", 10000),
        Field("saturatedFat", #"\bsat(?:urated|\.)?\s*fat\b"#, "g", 100),
        Field("transFat", #"\btrans\.?\s*fat\b"#, "g", 50),
        Field("cholesterol", #"\bcholest(?:erol|\.)?"#, "mg", 2000),
        // "Sugar Alcohol" is a different line; "Includes 10g Added Sugars" is read on its own.
        Field("sugar", #"\btotal\s*sugars?\b|^sugars?\b(?!\s*alc)"#, "g", 300),
        Field("addedSugar", #"^added\s*sugars?\b"#, "g", 300),
        Field("vitaminD", #"\bvit(?:amin|\.)?\s*d\b"#, "mcg", 1000),
        Field("calcium", #"\bcalcium\b"#, "mg", 5000),
        Field("iron", #"\biron\b"#, "mg", 200),
        Field("potassium", #"\bpotas(?:sium|\.)?"#, "mg", 10000),
    ]

    /// Lines that mention a nutrient without giving its amount for this food.
    private static let noise = Pattern(
        #"per\s*gram|calorie\s*diet|calories\s*a\s*day|from\s*fat|fat\s*cal\b|daily\s*value|lowered|less\s*than\s*\d[\d,]+|%\s*dv"#,
        ignoringCase: true)
    private static let zeroAsO = Pattern(#"(?<=\d|^|\s|<)[Oo](?=\s*(?:m?g|\d|\*|%|$))"#)
    private static let oneAsL = Pattern(#"(?<=\s|^|<)[lI|](?=\s*m?g\b)"#)
    private static let thousands = Pattern(#"(\d+),(\d{3})(?!\d)"#)
    private static let amountPattern = Pattern(#"^\s*(<|less\s*than\s*)?(\d+(?:[.,]\d+)?)\s*(mg|g|kcal|mcg|µg)?\b"#, ignoringCase: true)
    private static let leadIn = Pattern(#"^[^\d<]{0,20}?(?=<|\d|[Oo]\s*m?g\b|less)"#, ignoringCase: true)
    private static let amountOnly = Pattern(#"^\s*(?:<|less\s*than\s*)?\d+(?:[.,]\d+)?\s*(?:mg|g|kcal|mcg|µg)?\s*\*?\s*$"#, ignoringCase: true)

    private static func isAmountOnly(_ line: String) -> Bool { amountOnly.test(digits(line)) }

    /// OCR reads a label's 0 as O and 1 as l or I, and a trailing "g" as 9.
    static func digits(_ text: String) -> String {
        let zeros = zeroAsO.replacing(in: text, with: "0")
        let ones = oneAsL.replacing(in: zeros, with: "1")
        // "1,160mg" has a thousands comma even with the unit attached; "0,125 g" is a decimal.
        return thousands.replacing(in: ones) { match in match[1] == "0" ? match.whole : (match[1] ?? "") + (match[2] ?? "") }
    }

    private struct Amount {
        var value: Double
        var unit: String
        var raw: String
    }

    /// The first amount at the start of some text: "8g", "<1 g", "160mg", "230".
    private static func leadingAmount(_ text: String) -> Amount? {
        guard let match = amountPattern.first(in: digits(text)), let raw = match[2] else { return nil }
        var value = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
        // A "less than" amount is logged as half its bound: "<1g" is 0.5 g.
        if match[1] != nil { value /= 2 }
        let unit = (match[3] ?? "").lowercased()
        return Amount(value: value, unit: unit == "µg" ? "mcg" : unit, raw: raw)
    }

    private static func convert(_ field: Field, _ amount: Amount, implied: Bool) -> Double? {
        var value = amount.value
        let unit = amount.unit
        if field.unit == "kcal" { return unit == "g" || unit == "mg" ? nil : value }
        if field.unit == "mcg" {
            // A bare number is usually the % Daily Value column.
            if unit.isEmpty { return implied ? value : nil }
            return unit == "mcg" ? value : unit == "mg" ? value * 1000 : nil
        }
        if unit.isEmpty {
            if !implied {
                // "Total Fat 09" is "0g" read as "09".
                guard amount.raw.count >= 2, amount.raw.hasSuffix("9"), amount.raw.allSatisfy(\.isASCII),
                      amount.raw.allSatisfy(\.isNumber) else { return nil }
                value = Double(amount.raw.dropLast()) ?? 0
            }
        } else if unit == "mcg" {
            return nil
        }
        if field.unit == "mg" { return unit == "g" ? value * 1000 : value }
        return unit == "mg" ? value / 1000 : value
    }

    /// The box on the same printed row nearest to the right, where split labels keep their value.
    private static func rightOf(_ index: Int, _ boxes: [LabelTextBox]) -> LabelTextBox? {
        let box = boxes[index]
        return boxes.indices.filter { i in
            let other = boxes[i]
            return i != index && other.x > box.x + box.width * 0.5
                && abs(other.center - box.center) < max(box.height, other.height) * 0.6
        }
        .min { boxes[$0].x != boxes[$1].x ? boxes[$0].x < boxes[$1].x : $0 < $1 }
        .map { boxes[$0] }
    }

    private static func readField(_ field: Field, _ boxes: [LabelTextBox]) -> Double? {
        for index in boxes.indices {
            let text = boxes[index].text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if noise.test(text) { continue }
            guard let match = field.label.first(in: text) else { continue }
            let rest = String(text[match.range.upperBound...])
            // "PROTEIN, g" gives the unit once for a column of bare numbers.
            let implied = field.implied.test(rest)
            // The value follows the label within a short gap, which allows bilingual labels such as
            // "Total Fat / Grasa Total 0g" but not "SODIUM CONTENT … FROM 790mg".
            if let gap = leadIn.first(in: rest), let amount = leadingAmount(String(rest[gap.range.upperBound...])),
               let value = convert(field, amount, implied: implied), value <= field.plausible {
                return value
            }
            guard let next = rightOf(index, boxes) else { continue }
            // A footer split as "Sodium" | "Less than 2,400mg" gives a limit, not this food's amount.
            if noise.test(next.text) { continue }
            if let amount = leadingAmount(next.text),
               let value = convert(field, amount, implied: implied || field.unit == "kcal" || !amount.unit.isEmpty),
               value <= field.plausible {
                return value
            }
        }
        return nil
    }

    private static let servingHeading = Pattern(#"erv(?:ing)?\.?\s*s[i1l]z?e\b|tama[ñn]o\s*de\s*porci"#, ignoringCase: true)
    private static let servingLead = Pattern(#".*?(?:s[i1l]z?e|porci[oó]n)\b\s*[:.]?"#, ignoringCase: true)
    private static let perContainer = Pattern(#"per\s*cont|servings?\s*per"#, ignoringCase: true)
    private static let servingWeights = Pattern(#"(\d+(?:\.\d+)?)\s*(g|gm|grams?|ml)\b"#, ignoringCase: true)
    private static let servingOunces = Pattern(#"(\d+(?:\.\d+)?)\s*(fl\.?\s*)?oz"#, ignoringCase: true)
    private static let measureTail = Pattern(#"\d+(?:\.\d+)?\s*(?:g|gm|grams?|ml)\b.*$"#, ignoringCase: true)
    private static let edges = Pattern(#"^[\s,;:/]+|[\s,;:/]+$"#)

    private static func readServing(_ boxes: [LabelTextBox], _ values: inout Values) {
        // Tolerates cut-off and misread headings: "erving Size", "Serv. sie".
        guard let index = boxes.firstIndex(where: { servingHeading.test($0.text) }) else { return }
        let box = boxes[index]
        var own = box.text
        if let lead = servingLead.first(in: own) { own.removeSubrange(lead.range) }
        own = own.trimmingCharacters(in: .whitespacesAndNewlines)
        // The measure can continue in the box to the right or on the next printed line.
        let below = boxes.indices.first { i in
            let other = boxes[i]
            return i != index && other.center > box.center + min(box.height, other.height) * 0.3
                && other.y < box.y + box.height * 2.2 && abs(other.x - box.x) < 0.25
        }.map { boxes[$0] }
        let parts = [own, rightOf(index, boxes)?.text ?? "", below?.text ?? ""].filter { !perContainer.test($0) }
        let plain = digits(parts.joined(separator: " "))
        let amounts = values.amounts
        let macros = (amounts["fat"] ?? 0) + (amounts["carbs"] ?? 0) + (amounts["protein"] ?? 0)
        // A serving can't weigh less than its own fat, carbohydrate and protein.
        let fits = { (grams: Double) in grams > 0 && grams <= 2000 && grams >= macros * 0.8 }
        for match in servingWeights.all(in: plain) {
            guard let amount = Double(match[1] ?? "") else { continue }
            let unit = match[2]?.lowercased() == "ml" ? "ml" : "g"
            if unit == "ml" || fits(amount) {
                values.servingAmount = amount
                values.servingUnit = unit
                break
            }
        }
        if values.servingAmount == nil, let ounces = servingOunces.first(in: plain), let count = Double(ounces[1] ?? "") {
            let fluid = ounces[2] != nil
            let amount = count * (fluid ? 29.57 : 28.35)
            if fluid || fits(amount) {
                values.servingAmount = (amount * 10).rounded() / 10
                values.servingUnit = fluid ? "ml" : "g"
            }
        }
        // The household measure, e.g. "2/3 cup" from "2/3 cup (55g)"; it always has a number.
        values.servingLabel = parts.lazy.map { part in
            let head = String(part.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            return edges.replacing(in: measureTail.replacing(in: head, with: ""), with: "")
        }
        .first { $0.unicodeScalars.contains(where: isDigit) }
        .map { String($0.prefix(40)) } ?? ""
    }

    private static let addedSugar = Pattern(#"incl(?:udes|\.)?\s*(<|less\s*than\s*)?(\d+(?:[.,]\d+)?)\s*g\s*(?:of\s*)?added"#,
                                            ignoringCase: true)

    /// "Includes 10g Added Sugars" gives the amount before the nutrient's name.
    private static func readAddedSugar(_ boxes: [LabelTextBox]) -> Double? {
        for box in boxes {
            guard let match = addedSugar.first(in: digits(box.text)), let raw = match[2],
                  let number = Double(raw.replacingOccurrences(of: ",", with: ".")) else { continue }
            let value = number / (match[1] != nil ? 2 : 1)
            if value <= 300 { return value }
        }
        return nil
    }
}
