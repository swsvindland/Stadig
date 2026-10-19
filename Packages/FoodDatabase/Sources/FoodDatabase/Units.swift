import Foundation
import SystemCore

/// A way to count an amount of a food: grams, ounces, cups, the food's own portions, or kcal.
public struct PortionUnit: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case mass, volume, portion, energy, serving }

    /// "g", "oz", "lb", "ml", "floz", "cup", "tbsp", "tsp", "serving", "portion:<index>", "kcal". A
    /// portion's index is its place in the food's portions today, so a stored one is reopened with
    /// `FoodUnits.logged`.
    public var id: String
    /// "g", "oz", "cup", "slice", "kcal", "serving".
    public var label: String
    public var kind: Kind
    /// Basis units (g or ml, or servings) in one of this unit; for `.energy`, basis units per kcal.
    public var amount: Double

    public init(id: String, label: String, kind: Kind, amount: Double) {
        self.id = id
        self.label = label
        self.kind = kind
        self.amount = amount
    }

    /// Counted units take fractions ("1½ slices"); weights and energy take plain numbers.
    public var isCounted: Bool { kind == .portion || kind == .serving || ["cup", "tbsp", "tsp"].contains(id) }
}

/// Portion units and amounts: which units a food can be logged in, how amounts read and parse.
public enum FoodUnits {
    /// Every sensible unit for a food, the most natural first: weights, volumes where its portions
    /// or label make them convertible, its own portions ("slice", "serving", "cup, sliced"), and kcal.
    public static func units(for food: Food) -> [PortionUnit] { UnitTable(food).units }

    /// The unit and count to offer first: the last one used, else the food's own portion, else 100 g.
    /// With `lastAmount` (the basis units last logged), the last unit is offered only while it
    /// still holds that amount; see `logged`.
    public static func suggested(
        for food: Food, lastUnitID: String? = nil, lastCount: Double? = nil,
        lastAmount: Double? = nil
    ) -> (unit: PortionUnit, count: Double) {
        let table = UnitTable(food)
        if let lastUnitID, let lastCount, lastCount > 0, lastCount.isFinite, let unit = table.units.first(where: { $0.id == lastUnitID }),
            holds(unit, count: lastCount, amount: lastAmount)
        {
            return (unit, lastCount)
        }
        // "1 oz (28 g)" is 1 oz, though an ounce is 28.35 g.
        if let first = food.portions.first, let key = table.placed[0], let unit = table.units.first(where: { $0.id == key }),
            let parsed = parsePortion(first)
        {
            return (unit, parsed.count)
        }
        let count = food.portions.first?.amount ?? (food.basis == .serving ? 1 : 100)
        let unit =
            table.units.first { $0.id == food.basis.rawValue }
            ?? PortionUnit(
                id: food.basis.rawValue, label: food.basis.rawValue, kind: food.basis == .serving ? .serving : food.basis == .ml ? .volume : .mass,
                amount: 1)
        return (unit, count)
    }

    /// The unit and count a logged entry reopens in: the unit it was logged in while the food still
    /// has it and it still holds the amount logged (`amount`, in basis units), else the food's basis
    /// unit counting that amount. A portion's id is its place in the catalog row, and a catalog
    /// update can reword, drop or reorder portions, so "1 bar (40 g)" must not reopen as 1 g.
    public static func logged(for food: Food, unitID: String?, count: Double?, amount: Double?) -> (unit: PortionUnit, count: Double) {
        let offered = units(for: food)
        if let unitID, let count, count > 0, count.isFinite, let unit = offered.first(where: { $0.id == unitID }),
            holds(unit, count: count, amount: amount)
        {
            return (unit, count)
        }
        if let amount, amount > 0, amount.isFinite, let basis = offered.first(where: { $0.id == food.basis.rawValue }) { return (basis, amount) }
        return suggested(for: food)
    }

    /// Whether a count of a unit is the amount logged, give or take the 1% a reworded label moves
    /// it. Without an amount (an entry from before amounts were kept) nothing says otherwise.
    private static func holds(_ unit: PortionUnit, count: Double, amount: Double?) -> Bool {
        guard let amount, amount > 0, amount.isFinite else { return true }
        return abs(Self.amount(count, unit) / amount - 1) < 0.01
    }

    /// Basis units for a count of a unit.
    public static func amount(_ count: Double, _ unit: PortionUnit) -> Double { count * unit.amount }

    public static func nutrients(_ food: Food, count: Double, unit: PortionUnit) -> Nutrients { food.nutrients(for: amount(count, unit)) }

    /// The vitamins, minerals and other values the food has, for a portion; a value it doesn't
    /// list is unknown, not zero.
    public static func micros(_ food: Food, count: Double, unit: PortionUnit) -> [String: Double] {
        food.extras(for: amount(count, unit))
    }

    /// "1½ cups", "150 g", "2 large".
    public static func label(count: Double, unit: PortionUnit) -> String {
        "\(format(count, unit)) \(count > 1 ? plural(unit.label) : unit.label)"
    }

    /// How an entry's amount reads: "2 slices · 56 g", "½ serving", "≈ 300 kcal · 167 g". A unit
    /// other than the food's basis also gives the amount in the basis.
    public static func entryLabel(for food: Food, count: Double, unit: PortionUnit, estimate: Bool = false) -> String {
        let amount = count * unit.amount
        var text = label(count: count, unit: unit)
        if unit.id != food.basis.rawValue && !(food.basis == .serving && unit.amount == 1) {
            if food.basis == .serving {
                let servings = PortionUnit(id: "serving", label: "serving", kind: .serving, amount: 1)
                text += " · \(format(amount, servings)) \(amount > 1 ? "servings" : "serving")"
            } else {
                text += " · \(trimmed(amount, places: amount >= 10 ? 0 : 1)) \(food.basis.rawValue)"
            }
        }
        return estimate ? "≈ \(text)" : text
    }

    /// A count as the amount field shows it: "1½" slices, "120" g, "4.2" oz.
    public static func format(_ count: Double, _ unit: PortionUnit) -> String {
        guard count.isFinite else { return "" }
        if unit.isCounted {
            let whole = (count + 0.005).rounded(.down)
            if let glyph = glyphs.first(where: { abs(count - whole - $0.value) < 0.005 }) {
                return (whole == 0 ? "" : String(Int(whole))) + glyph.glyph
            }
        }
        return trimmed(count, places: 2)
    }

    /// The same amount of food in another unit, rounded for that unit: counts to quarters, grams to
    /// whole ones, ounces and pounds to tenths. A pound is too big to round whole: 200 g would be 1 lb.
    public static func convert(_ count: Double, from: PortionUnit, to: PortionUnit) -> Double {
        guard count > 0, to.amount > 0 else { return .nan }
        let value = count * from.amount / to.amount
        if to.isCounted { return max(0.25, (value * 4).rounded() / 4) }
        if tenths.contains(to.id) { return max(0.1, (value * 10).rounded() / 10) }
        return max(1, value.rounded())
    }

    /// Units whole numbers are too coarse for.
    private static let tenths: Set<String> = ["oz", "floz", "lb"]

    /// What ± adds: 10 g, ml or kcal, else half a unit.
    public static func step(for unit: PortionUnit) -> Double {
        unit.id == "g" || unit.id == "ml" || unit.kind == .energy ? 10 : 0.5
    }

    /// The most an amount can count: nobody logs a million of anything, and the bound keeps every
    /// amount made from a count far below where converting it to a whole number traps.
    static let maxCount = 1_000_000.0

    /// "1 1/2", "1½", "0.5", ".5", "2,5", "１/２" → a number; nil for anything else.
    public static func parseCount(_ text: String) -> Double? {
        var value = asciiDigits(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let comma = value.firstIndex(of: ",") { value.replaceSubrange(comma...comma, with: ".") }
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let count: Double?
        if let match = glyphCount.first(in: value), let glyph = glyphs.first(where: { $0.glyph == match[2] }), let whole = Double(match[1] ?? "0") {
            count = whole + glyph.value
        } else if let match = fractionCount.first(in: value), let whole = Double(match[1] ?? "0"),
            let numerator = match[2].flatMap(Double.init), let denominator = match[3].flatMap(Double.init)
        {
            count = denominator > 0 ? whole + numerator / denominator : nil
        } else {
            count = decimalCount.test(value) ? Double(value.hasPrefix(".") ? "0" + value : value) : nil
        }
        guard let count, count.isFinite, count <= maxCount else { return nil }
        return count
    }
}

// The patterns read ASCII digits only, since `Double` reads no others; `asciiDigits` maps the rest.
private let glyphCount = Pattern(#"^([0-9]+)? ?([¼⅓½⅔¾])$"#)
private let fractionCount = Pattern(#"^(?:([0-9]+) )?([0-9]+)/([0-9]+)$"#)
private let decimalCount = Pattern(#"^(?:[0-9]+\.?[0-9]*|\.[0-9]+)$"#)

/// Another script's digits and separators as ASCII: "１/２" from a Japanese keyboard, "١٫٥" from
/// an Arabic one.
private func asciiDigits(_ text: String) -> String {
    if text.unicodeScalars.allSatisfy(\.isASCII) { return text }
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
        if scalar.properties.numericType == .decimal, let digit = scalar.properties.numericValue, (0...9).contains(digit) {
            scalars.append(Unicode.Scalar(UInt8(0x30 + Int(digit))))
        } else {
            scalars.append(separators[scalar] ?? scalar)
        }
    }
    return String(scalars)
}

private let separators: [Unicode.Scalar: Unicode.Scalar] = ["\u{FF0F}": "/", "\u{2044}": "/", "\u{066B}": ".", "\u{FF0E}": ".", "\u{FF0C}": ","]

// MARK: - Portions

private let glyphs: [(value: Double, glyph: String)] = [(1 / 4, "¼"), (1 / 3, "⅓"), (1 / 2, "½"), (2 / 3, "⅔"), (3 / 4, "¾")]

/// Up to `places` decimals, without trailing zeros: 4.2, 120, 0.33.
private func trimmed(_ value: Double, places: Int) -> String {
    let scale = pow(10, Double(places))
    let rounded = (value * scale).rounded() / scale
    if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int(rounded)) }
    return String(rounded)
}

let weights: [String: Double] = ["g": 1, "oz": 28.3495, "lb": 453.592, "kg": 1000]
let volumes: [String: Double] = ["ml": 1, "floz": 29.5735, "cup": 240, "tbsp": 15, "tsp": 5, "l": 1000]
private let massUnits = ["g", "oz", "lb"]
private let volumeUnits = ["ml", "floz", "cup", "tbsp", "tsp"]

private let measureNames: [(Pattern, String)] = [
    (Pattern(#"^f(?:l(?:uid)?)?\.? ?(?:oz|ounces?)$"#), "floz"),
    (Pattern(#"^(?:g|gr|gms?|grams?|grammes?)$"#), "g"),
    (Pattern(#"^(?:oz|oza|onz|ounces?)$"#), "oz"),
    (Pattern(#"^(?:lbs?|pounds?)$"#), "lb"),
    (Pattern(#"^(?:kg|kgs|kilos?|kilograms?)$"#), "kg"),
    (Pattern(#"^(?:ml|mls|milliliters?|millilitres?)$"#), "ml"),
    (Pattern(#"^(?:l|liters?|litres?)$"#), "l"),
    (Pattern(#"^cups?$"#), "cup"),
    (Pattern(#"^(?:tbsp|tbs|tbl|tablespoons?)$"#), "tbsp"),
    (Pattern(#"^(?:tsp|teaspoons?)$"#), "tsp"),
    (Pattern(#"^servings?$"#), "serving"),
]

/// The measure a unit name spells: "floz" for "fl. oz.", "cup" for "cups".
func measureKey(_ name: String) -> String? {
    var text = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if text.hasSuffix(".") { text.removeLast() }
    text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return measureNames.first { $0.0.test(text) }?.1
}

private let countPattern = #"(?:\d+\s+\d+/\d+|\d+/\d+|\d*\.\d+|\d+)"#
private let leadingCount = Pattern(#"^\s*("# + countPattern + #")\s+(.+)$"#)
private let leadingCountOnly = Pattern(#"^\s*"# + countPattern + #"\s+"#)
private let labelMeasures = Pattern("(" + countPattern + #")\s*(fl(?:uid)?\.?\s*(?:oz|ounces?)\b|[a-z]+)"#, ignoringCase: true)
private let nameEnd = Pattern(#"[,(]|\s\d"#)

/// A per-serving food's serving weight (g) and volume (ml), when its label gives them: "1 serving
/// (30 g)", "1 serving (2 tbsp (32g))".
func servingSize(_ food: Food) -> (weight: Double?, volume: Double?) {
    var weight: Double?
    var volume: Double?
    for portion in food.portions {
        for match in labelMeasures.all(in: portion.label) {
            let unit = measureKey(match[2] ?? "") ?? ""
            let isWeight = weights[unit] != nil
            let amount = (FoodUnits.parseCount(match[1] ?? "") ?? .nan) * (weights[unit] ?? volumes[unit] ?? 0) / portion.amount
            guard amount > 0, amount.isFinite else { continue }
            if isWeight { weight = weight ?? amount } else { volume = volume ?? amount }
        }
    }
    return (weight, volume)
}

/// Size words describe a portion rather than count it: "2 large", not "2 larges".
private let sizes: Set<String> = ["small", "medium", "large", "regular", "extra", "jumbo", "whole", "kid"]
private let invariant = sizes.union(["g", "oz", "ml", "fl", "floz", "tbsp", "tsp", "kcal", "lb", "kg", "l", "fl oz", "shrimp"])
/// Words that say what a portion is like rather than what it counts: its size or state ("slice
/// thin", "piece fried") and the words that start a phrase about it ("thigh with skin").
private let describing = sizes.union([
    "mini", "miniature", "thick", "thin", "inner", "outer", "raw", "dry", "fresh", "frozen", "boneless", "nfs", "size",
    "with", "without", "per", "of", "from", "in", "and", "for", "not",
])
/// Containers and cuts, which count whatever follows them: "jar gerber second food", "roast rump".
private let containers: Set<String> = [
    "slice", "piece", "roast", "leg", "jar", "can", "bottle", "package", "packet", "container", "box", "bag", "envelope", "pouch", "carton", "scoop",
]
/// Foods that end in "ie", so "cookies" isn't a "cooky".
private let ieNouns: Set<String> = ["cookie", "brownie", "pie", "smoothie", "veggie", "hoagie", "calorie"]
private let qualifierStart = Pattern(#"\s*[,(]"#)

/// "slice" is "slices", "slice cooked" "slices cooked", "small bagel" "small bagels", "can or bottle"
/// "cans or bottles" and "cup, chopped" "cups, chopped"; units and sizes stay as they are.
func plural(_ name: String) -> String { inflecting(name, with: pluralWord) }

/// What a portion of several counts one of: "slices cooked" is a "slice cooked".
private func singular(_ name: String) -> String { inflecting(name, with: singularWord) }

/// The name with the noun it counts changed, in each of "can or bottle", leaving its qualifier
/// ("cup, chopped", "slice (thin)") as it is.
private func inflecting(_ name: String, with change: (String) -> String) -> String {
    let cut = qualifierStart.first(in: name)?.range.lowerBound
    var words = (cut.map { String(name[..<$0]) } ?? name).components(separatedBy: " ")
    var start = 0
    for end in words.indices.filter({ words[$0].lowercased() == "or" }) + [words.count] {
        if let i = countedWord(in: words[start..<end]) { words[i] = change(words[i]) }
        start = end + 1
    }
    return words.joined(separator: " ") + (cut.map { String(name[$0...]) } ?? "")
}

/// Which word a portion's name counts. Leading sizes describe it ("small bagel"); then the first
/// other word when it is a measure or container ("cup penne") or describing words follow it
/// ("slice cooked", "thigh with skin"), else the last word ("hot dog"). Nil when every word
/// describes ("extra large").
private func countedWord(in words: ArraySlice<String>) -> Int? {
    let lower = words.map { $0.lowercased() }
    guard let lead = lower.firstIndex(where: { !$0.isEmpty && !describes($0) }) else { return nil }
    let first = lower[lead]
    let heads = measureKey(first) != nil || containers.contains(first) || containers.contains(singularWord(first))
    if heads || lower[(lead + 1)...].contains(where: describes) { return words.startIndex + lead }
    return words.startIndex + (lower.lastIndex { !$0.isEmpty } ?? lead)
}

/// A size, a state, a participle ("cooked", "fried") or a word starting a phrase.
private func describes(_ word: String) -> Bool {
    describing.contains(word) || (word.count > 4 && word.hasSuffix("ed"))
}

private func pluralWord(_ word: String) -> String {
    let lower = word.lowercased()
    if lower.isEmpty || invariant.contains(lower) || lower.hasSuffix("s") || lower.hasSuffix("fish") { return word }
    if lower.hasSuffix("y"), let before = lower.dropLast().last, !"aeiou".contains(before) { return String(word.dropLast()) + "ies" }
    if lower.hasSuffix("x") || lower.hasSuffix("ch") || lower.hasSuffix("sh") || lower.hasSuffix("potato") || lower.hasSuffix("tomato") {
        return word + "es"
    }
    if lower.hasSuffix("leaf") || lower.hasSuffix("loaf") || lower.hasSuffix("half") { return String(word.dropLast()) + "ves" }
    return word + "s"
}

private func singularWord(_ word: String) -> String {
    let lower = word.lowercased()
    if lower.hasSuffix("ches") || lower.hasSuffix("shes") || lower.hasSuffix("xes") || lower.hasSuffix("potatoes") || lower.hasSuffix("tomatoes") {
        return String(word.dropLast(2))
    }
    if lower.hasSuffix("eaves") || lower.hasSuffix("oaves") || lower.hasSuffix("alves") { return String(word.dropLast(3)) + "f" }
    if lower.hasSuffix("ies"), lower.count > 4, !ieNouns.contains(String(lower.dropLast())) { return String(word.dropLast(3)) + "y" }
    if lower.hasSuffix("s"), let before = lower.dropLast().last, before != "s" && before != "u" { return String(word.dropLast()) }
    return word
}

/// A catalog portion as a count of a named unit: "2 SLICES (57 g)" is 2 of a 28.5 g "slice".
func parsePortion(_ portion: Portion) -> (count: Double, name: String, perUnit: Double)? {
    let match = leadingCount.first(in: portion.label)
    let count = match.map { FoodUnits.parseCount($0[1] ?? "") ?? .nan } ?? 1
    let text = match?[2] ?? portion.label
    // "1 roll 1 serving" and "1 cup, chopped (1/2\" pieces)" are a "roll" and a "cup".
    let stop = nameEnd.first(in: text)?.range.lowerBound ?? text.endIndex
    var name = text[..<stop].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    // Some packaged-food portions are only a weight ("1 151.0g"), which names no unit.
    guard !name.isEmpty, !(name.unicodeScalars.first.map(isDigit) ?? false), count > 0, portion.amount > 0 else { return nil }
    if count > 1 && measureKey(name) == nil { name = singular(name) }
    return (count, name, portion.amount / count)
}

/// A portion's words after its count, as its own unit's label: "cup, sliced".
private func fullName(_ portion: Portion) -> String {
    let rest = leadingCountOnly.replacing(in: portion.label, with: "")
    return String(rest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(32))
}

/// The units a food can be logged in, and the unit each of its portions is offered as (nil when it
/// isn't). Weights and volumes of the food's own kind are exact; a portion that measures the other
/// kind ("1 cup" of a weighed food) gives the density for all of that kind. Qualified measures
/// ("1 cup, sliced", "1 oz, dry, yields") are their own units instead.
struct UnitTable {
    var units: [PortionUnit] = []
    var placed: [String?]

    init(_ food: Food) {
        placed = food.portions.map { _ in nil }
        var ownKeys: [String] = []
        var own: [String: Double] = [:]
        var natural: [(unit: PortionUnit, index: Int, full: Bool)] = []
        let sameKind = { (key: String) in food.basis == .g ? weights[key] != nil : food.basis == .ml && volumes[key] != nil }
        let near = { (a: Double, b: Double) in abs(a / b - 1) < 0.1 }
        for (i, portion) in food.portions.enumerated() {
            guard let parsed = parsePortion(portion) else { continue }
            var measure = measureKey(parsed.name)
            // Drinks are counted in fluid ounces.
            if measure == "oz" && food.basis == .ml { measure = "floz" }
            let key: String
            if let measure, massUnits.contains(measure) || volumeUnits.contains(measure) {
                key = measure
            } else if measure == "serving" && food.basis == .serving && abs(parsed.perUnit - 1) < 1e-6 {
                key = "serving"
            } else {
                key = "portion:\(i)"
            }
            if key == "serving" {
                placed[i] = key
            } else if key.hasPrefix("portion:") {
                natural.append((PortionUnit(id: key, label: parsed.name, kind: .portion, amount: parsed.perUnit), i, false))
            } else if removingBrackets(portion.label).contains(",") {
                // A qualified measure ("1 cup, sliced") is its own unit, named in full.
                natural.append((PortionUnit(id: "portion:\(i)", label: fullName(portion), kind: .portion, amount: parsed.perUnit), i, true))
            } else if sameKind(key) {
                // "3 oz" of a weighed food is 3 oz; a portion that disagrees ("4 oz (28 g)") is left out.
                if near(parsed.perUnit, weights[key] ?? volumes[key]!) { placed[i] = key }
            } else if own[key] == nil {
                ownKeys.append(key)
                own[key] = parsed.perUnit
                placed[i] = key
            } else if near(parsed.perUnit, own[key]!) {
                placed[i] = key
            }
        }
        var units: [PortionUnit] = []
        func add(_ key: String, _ perUnit: Double, _ kind: PortionUnit.Kind) {
            let value = key == food.basis.rawValue ? 1 : own[key] ?? perUnit
            if value > 0 && value.isFinite { units.append(PortionUnit(id: key, label: key == "floz" ? "fl oz" : key, kind: kind, amount: value)) }
        }
        switch food.basis {
        case .g:
            for key in massUnits { add(key, weights[key]!, .mass) }
            // A cup or tablespoon of the food gives the density that converts every volume.
            if let measure = ownKeys.first(where: { volumes[$0] != nil }) {
                for key in volumeUnits { add(key, own[measure]! / volumes[measure]! * volumes[key]!, .volume) }
            }
        case .ml:
            for key in volumeUnits { add(key, volumes[key]!, .volume) }
            if let measure = ownKeys.first(where: { weights[$0] != nil }) {
                for key in massUnits { add(key, own[measure]! / weights[measure]! * weights[key]!, .mass) }
            }
        case .serving:
            let size = servingSize(food)
            if let weight = size.weight { for key in massUnits { add(key, weights[key]! / weight, .mass) } }
            if let volume = size.volume { for key in volumeUnits { add(key, volumes[key]! / volume, .volume) } }
            add("serving", 1, .serving)
        }
        let offered = Set(units.map(\.id))
        for i in placed.indices where placed[i].map({ !offered.contains($0) }) ?? false { placed[i] = nil }
        var labels = Set(units.map(\.label))
        for (unit, index, full) in natural {
            // Two "slice" portions read as "slice" and "slice (thin)".
            let label = labels.contains(unit.label) && !full ? fullName(food.portions[index]) : unit.label
            if labels.contains(label) { continue }
            labels.insert(label)
            units.append(PortionUnit(id: unit.id, label: label, kind: unit.kind, amount: unit.amount))
            placed[index] = unit.id
        }
        if food.nutrients.kcal > 0 { add("kcal", (food.basis == .serving ? 1 : 100) / food.nutrients.kcal, .energy) }
        self.units = units
    }
}

private let bracketed = Pattern(#"\([^)]*\)"#)

private func removingBrackets(_ text: String) -> String {
    bracketed.replacing(in: text, with: "")
}
