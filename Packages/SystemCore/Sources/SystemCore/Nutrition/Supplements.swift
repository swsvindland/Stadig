import Foundation

/// What a supplement comes as, from the unit its dose is counted in.
public enum SupplementForm: String, Codable, Sendable, CaseIterable {
    case capsule, softgel, tablet, gummy, lozenge, powder, liquid, drops, packet, other

    public init(unit: String) {
        switch unit {
        case "capsule", "pill": self = .capsule
        case "softgel": self = .softgel
        case "tablet", "caplet", "chewable", "wafer": self = .tablet
        case "gummy", "chew": self = .gummy
        case "lozenge": self = .lozenge
        case "scoop", "g", "tsp", "tbsp": self = .powder
        case "ml": self = .liquid
        case "drop", "spray": self = .drops
        case "packet": self = .packet
        default: self = .other
        }
    }

    public var label: String {
        switch self {
        case .capsule: "Capsule"
        case .softgel: "Softgel"
        case .tablet: "Tablet"
        case .gummy: "Gummy"
        case .lozenge: "Lozenge"
        case .powder: "Powder"
        case .liquid: "Liquid"
        case .drops: "Drops"
        case .packet: "Packet"
        case .other: "Other"
        }
    }
}

/// One line of a Supplement Facts panel, as printed, and what Macro Track counts it as.
public struct SupplementIngredient: Hashable, Codable, Sendable {
    public var name: String
    public var amount: Double?
    /// As printed, tidied: "mg", "mcg", "g", "IU", "mcg DFE", "mcg RAE", "CFU", "ml", "kcal".
    public var unit: String
    /// The nutrient it counts as ("vitaminD", "caffeine", "epa"), and its amount in that nutrient's
    /// unit; nil when it isn't one Macro Track follows (ashwagandha, probiotics, enzymes).
    public var key: String?
    public var value: Double?

    public init(name: String, amount: Double?, unit: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amount = amount
        self.unit = SupplementIngredients.unit(unit)
        if let amount, let read = SupplementIngredients.read(name: name, amount: amount, unit: unit) {
            key = read.key
            value = read.value
        }
    }

    /// A nutrient Macro Track follows; herbs, enzymes, probiotics and the like aren't.
    public var isTracked: Bool { key != nil }

    /// "1,000 mg", "25 mcg", "5 billion CFU".
    public var amountLabel: String? {
        guard let amount else { return nil }
        let digits = amount >= 100 ? 0 : (amount >= 1 ? 1 : 2)
        let number = amount.formatted(.number.precision(.fractionLength(0...digits)))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

/// A supplement's label: its serving and what's in it. From the NIH Dietary Supplement Label
/// Database, a photo of the panel, or typed in.
public struct SupplementFacts: Hashable, Codable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable { case dsld, label, custom }

    /// "dsld:12345", or "custom:<uuid>" for one the person made.
    public var id: String
    public var name: String
    public var brand: String?
    /// The 14-digit key, when it has a barcode.
    public var barcode: String?
    /// The label's serving: `servingCount` of `unit` ("2" "softgel").
    public var servingCount: Double
    /// Singular: "capsule", "softgel", "tablet", "gummy", "scoop", "ml", "drop", "g".
    public var unit: String
    public var ingredients: [SupplementIngredient]
    public var source: Source

    public init(id: String, name: String, brand: String? = nil, barcode: String? = nil, servingCount: Double = 1, unit: String = "capsule",
                ingredients: [SupplementIngredient], source: Source) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.brand = brand?.isEmpty == false ? brand : nil
        self.barcode = barcode
        self.servingCount = servingCount > 0 ? servingCount : 1
        self.unit = unit
        self.ingredients = ingredients
        self.source = source
    }

    public var form: SupplementForm { SupplementForm(unit: unit) }

    /// "Fish Oil · Nature Made", or just the name.
    public var title: String { brand.map { "\(name) · \($0)" } ?? name }

    /// Followed nutrients per serving, by key in each nutrient's unit. Omega-3 is the label's total,
    /// else EPA, DHA, DPA and ALA added up; a folate line in DFE stands for its folic acid line.
    public var amounts: [String: Double] {
        var amounts: [String: Double] = [:]
        let keys = Set(ingredients.compactMap(\.key))
        for ingredient in ingredients {
            guard let key = ingredient.key, let value = ingredient.value, value.isFinite, value >= 0 else { continue }
            // The macros go in `nutrients`; a folic acid line under folate is the same folate.
            if SupplementIngredients.macroKeys.contains(key) { continue }
            if key == "folate", ingredient.unit != "mcg DFE", keys.contains("folate"),
               ingredients.contains(where: { $0.key == "folate" && $0.unit == "mcg DFE" }) { continue }
            amounts[key, default: 0] += value
        }
        if amounts["omega3"] == nil {
            let parts = SupplementIngredients.omega3Parts.compactMap { amounts[$0] }
            if !parts.isEmpty { amounts["omega3"] = parts.reduce(0, +) }
        }
        return amounts
    }

    /// Calories and macros per serving, when the label gives any (gummies, powders, pre-workouts).
    public var nutrients: Nutrients? {
        var values: [String: Double] = [:]
        for ingredient in ingredients {
            guard let key = ingredient.key, SupplementIngredients.macroKeys.contains(key), let value = ingredient.value else { continue }
            values[key] = (values[key] ?? 0) + value
        }
        guard !values.isEmpty else { return nil }
        let protein = values["protein"] ?? 0, carbs = values["carbs"] ?? 0, fat = values["fat"] ?? 0
        let kcal = values["kcal"] ?? (protein * 4 + carbs * 4 + fat * 9)
        return Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat, sugar: values["sugar"])
    }

    /// Lines that aren't followed nutrients, with an amount: "Ashwagandha 600 mg", "Melatonin 3 mg".
    public var others: [SupplementIngredient] {
        ingredients.filter { $0.amount != nil && ($0.key == nil || SupplementIngredients.omega3Parts.contains($0.key!)) }
    }

    /// "2 softgels", "1 scoop", "10 g", "1 gummy".
    public func amountLabel(_ count: Double) -> String { SupplementServing.label(count, unit) }

    /// The label with only the lines Macro Track counts. A bottle's herbs, extracts and "fish oil
    /// concentrate" add nothing it tracks, so they aren't kept.
    public var tracked: SupplementFacts {
        var facts = self
        facts.ingredients = ingredients.filter(\.isTracked)
        return facts
    }

    public var servingLabel: String { amountLabel(servingCount) }
}

/// Serving sizes as labels and the NIH database print them: "2 Softgel(s)", "10 Gram(s) [1 scoop]",
/// "Serving Size: 1 Tablet", "1 mL [30 drops]".
public enum SupplementServing {
    private static let leading = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?)\s*([A-Za-z][A-Za-z\- ]*)?"#)
    private static let bracket = try! NSRegularExpression(pattern: #"\[\s*(\d+(?:\.\d+)?|one|two|three|half a|1/2)\s+([A-Za-z]+)[^\]]*\]"#,
                                                          options: [.caseInsensitive])

    /// The count and singular unit of a serving, or nil when there's no number.
    public static func parse(_ text: String) -> (count: Double, unit: String)? {
        var text = text.replacingOccurrences(of: "(s)", with: "s").replacingOccurrences(of: "(ies)", with: "ies")
        if let range = text.range(of: #"(?i)serving\s*size\s*[:.]?"#, options: .regularExpression) { text = String(text[range.upperBound...]) }
        // "Two Softgels" counts the same as "2 Softgels".
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let word = numberWords.first(where: { trimmed.lowercased().hasPrefix($0.key + " ") }) {
            text = "\(word.value) " + trimmed.dropFirst(word.key.count + 1)
        }
        let whole = NSRange(text.startIndex..., in: text)
        var main: (count: Double, unit: String)?
        if let match = leading.firstMatch(in: text, range: whole), let countRange = Range(match.range(at: 1), in: text) {
            let count = number(String(text[countRange]))
            let words = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            if let count, count > 0 { main = (count, unit(words: words)) }
        }
        // "10 Gram(s) [1 scoop]": the bracket's measure is what a person counts, when it's one number.
        if let match = bracket.firstMatch(in: text, range: whole), let c = Range(match.range(at: 1), in: text),
           let w = Range(match.range(at: 2), in: text), let count = number(String(text[c])), count > 0 {
            let unit = unit(words: String(text[w]))
            if ["scoop", "packet", "tsp", "tbsp", "drop", "capsule", "softgel", "tablet", "gummy", "spray"].contains(unit),
               main == nil || ["g", "ml", "mg"].contains(main!.unit) {
                return (count, unit)
            }
        }
        if let main, main.unit == "mg" { return (main.count / 1000, "g") }
        return main
    }

    private static let numberWords = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "half": 0.5]

    static func number(_ text: String) -> Double? {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        switch t {
        case "one": return 1
        case "two": return 2
        case "three": return 3
        case "half a", "1/2": return 0.5
        default: break
        }
        let parts = t.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 { return a / b }
        return Double(t.replacingOccurrences(of: ",", with: "."))
    }

    /// The singular counting word for what a label calls its serving.
    public static func unit(words: String) -> String {
        let w = words.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { w.contains($0) } }
        if has("softgel", "soft gel", "gelcap", "liquid cap") { return "softgel" }
        if has("caplet") { return "caplet" }
        if has("capsule", "vcap", "vegcap", "veggie cap", "vegicap", "cap") { return "capsule" }
        if has("chewable") { return "chewable" }
        // Spoons before tablets: "tablespoon" has "tab" in it.
        if has("tablespoon", "tbsp") { return "tbsp" }
        if has("teaspoon", "tsp") { return "tsp" }
        if has("tablet", "tab") { return "tablet" }
        if has("gumm") { return "gummy" }
        if has("chew") { return "chew" }
        if has("lozenge", "troche", "pastille") { return "lozenge" }
        if has("scoop") { return "scoop" }
        if has("packet", "stick", "sachet", "pouch") { return "packet" }
        if has("drop") { return "drop" }
        if has("spray", "pump") { return "spray" }
        if has("pill") { return "pill" }
        if has("wafer") { return "wafer" }
        if has("bar") { return "bar" }
        let first = w.split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
        switch first {
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": return "ml"
        case "g", "gram", "grams", "gm", "gms": return "g"
        case "mg": return "mg"
        case "oz", "fl": return "ml"
        case "": return "serving"
        default: return first.hasSuffix("s") && first.count > 3 ? String(first.dropLast()) : first
        }
    }

    /// "2 softgels", "1 gummy", "0.5 tsp", "10 g".
    public static func label(_ count: Double, _ unit: String) -> String {
        let number = count.formatted(.number.precision(.fractionLength(0...2)))
        switch unit {
        case "g", "ml", "tsp", "tbsp", "mg": return "\(number) \(unit)"
        default:
            let one = abs(count - 1) < 0.001
            let word = one || count < 1 ? unit : (unit.hasSuffix("y") && unit != "spray" ? "\(unit.dropLast())ies" : "\(unit)s")
            return "\(number) \(word)"
        }
    }
}

/// Reads Supplement Facts lines into the nutrients Macro Track follows: names as the NIH database
/// and labels print them ("Vitamin D3", "Eicosapentaenoic Acid", "Caffeine Anhydrous"), in any of
/// the units labels use, converted to each nutrient's unit (IU of vitamin D to µg, folic acid to
/// µg DFE).
public enum SupplementIngredients {
    /// Keys that are macros, which go to `Nutrients` rather than the vitamins and minerals.
    public static let macroKeys: Set<String> = ["kcal", "protein", "carbs", "fat", "sugar"]
    /// The omega-3s a label may list instead of a total.
    public static let omega3Parts = ["epa", "dha", "dpa", "ala", "otherOmega3"]

    /// Every key Macro Track follows on a label: the macros, fiber, the vitamins and minerals,
    /// omega-3 and its parts, and caffeine. Anything else (cholesterol, trans fat, added sugars,
    /// herbs) isn't kept.
    public static let tracked: Set<String> = Set(units.keys)

    /// Each followed nutrient's unit.
    static let units: [String: String] = [
        "kcal": "kcal", "protein": "g", "carbs": "g", "fat": "g", "sugar": "g", "fiber": "g", "saturatedFat": "g",
        "omega3": "g", "epa": "g", "dha": "g", "dpa": "g", "ala": "g", "otherOmega3": "g",
        "sodium": "mg", "potassium": "mg", "magnesium": "mg", "calcium": "mg", "iron": "mg", "zinc": "mg", "copper": "mg",
        "manganese": "mg", "phosphorus": "mg", "vitaminC": "mg", "vitaminE": "mg", "thiamin": "mg", "riboflavin": "mg",
        "niacin": "mg", "pantothenicAcid": "mg", "vitaminB6": "mg", "choline": "mg", "caffeine": "mg",
        "selenium": "µg", "vitaminD": "µg", "vitaminA": "µg", "vitaminK": "µg", "folate": "µg", "vitaminB12": "µg",
    ]

    /// Name patterns, tried in order against the name with its brackets removed.
    private static let names: [(key: String, pattern: NSRegularExpression)] = [
        ("kcal", #"^(total )?calories$"#),
        ("protein", #"^(total )?protein$"#),
        ("carbs", #"^(total )?carbohydrates?$|^(total )?carbs$"#),
        ("fat", #"^(total )?fat$"#),
        ("sugar", #"^(total )?sugars?$"#),
        ("fiber", #"^(total )?(dietary )?fib(er|re)$"#),
        ("saturatedFat", #"^saturated fat"#),
        ("sodium", #"^sodium$"#),
        ("potassium", #"^potassium$"#),
        ("magnesium", #"^magnesium$"#),
        ("calcium", #"^calcium$"#),
        ("iron", #"^iron$"#),
        ("zinc", #"^zinc$"#),
        ("copper", #"^copper$"#),
        ("manganese", #"^manganese$"#),
        ("phosphorus", #"^phosphorus$"#),
        ("selenium", #"^selenium$"#),
        ("vitaminC", #"^vitamin c$|^ascorbic acid$"#),
        ("vitaminD", #"^vitamin d ?[23]?$|^cholecalciferol$|^ergocalciferol$"#),
        ("vitaminA", #"^vitamin a$|^retinyl |^retinol$|^beta[- ]?carotene$"#),
        ("vitaminE", #"^vitamin e$|^d-alpha[- ]tocopher|^dl-alpha[- ]tocopher|^alpha[- ]tocopherol$"#),
        ("vitaminK", #"^vitamin k ?[12]?$|^phylloquinone$|^phytonadione$|^menaquinone|^mk-?[47]$"#),
        ("thiamin", #"^thiamine?( hcl| hydrochloride| mononitrate)?$|^vitamin b-? ?1$|^benfotiamine$"#),
        ("riboflavin", #"^riboflavin|^vitamin b-? ?2$"#),
        ("niacin", #"^niacin(amide)?$|^vitamin b-? ?3$|^nicotinamide$|^nicotinic acid$|^inositol hexanicotinate$"#),
        ("pantothenicAcid", #"^pantothenic acid$|^vitamin b-? ?5$|^(d-)?calcium (d-)?pantothenate$"#),
        ("vitaminB6", #"^vitamin b-? ?6$|^pyridox"#),
        ("folate", #"^folate|^folic acid$|^folacin$|methyl ?folate|^(l-)?5-mthf$|^5-methyltetrahydrofolate"#),
        ("vitaminB12", #"^vitamin b-? ?12$|cobalamin$"#),
        ("choline", #"^choline$"#),
        ("omega3", #"^(total )?omega[- ]?3s?( fatty acids)?$"#),
        ("epa", #"^epa$|^eicosapentaenoic"#),
        ("dha", #"^dha$|^docosahexaenoic"#),
        ("dpa", #"^dpa$|^docosapentaenoic"#),
        ("ala", #"^ala$|^alpha[- ]linolenic"#),
        ("otherOmega3", #"^other omega[- ]?3"#),
        ("caffeine", #"^(natural )?caffeine( anhydrous| citrate)?$"#),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    private static let brackets = try! NSRegularExpression(pattern: #"\([^)]*\)?|\[[^\]]*\]?|[†‡*®™]"#)
    private static let tail = try! NSRegularExpression(pattern: #"\s+(?:as|from)\s.*$|,.*$"#)

    /// The name as matched: lowercased, brackets and "as …"/"from …" dropped.
    public static func clean(_ name: String) -> String {
        var text = name.lowercased()
        text = brackets.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        text = tail.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The followed nutrient a line is, or nil.
    public static func key(for name: String) -> String? {
        let text = clean(name)
        guard !text.isEmpty, !name.lowercased().contains("from fat") else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return names.first { $0.pattern.firstMatch(in: text, range: range) != nil }?.key
    }

    /// A unit as printed, tidied: "Gram(s)" is "g", "{Calories}" is "kcal", "ug" is "mcg".
    public static func unit(_ unit: String) -> String {
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch u {
        case "g", "gram", "grams", "gram(s)", "gm", "gms", "grams(s)": return "g"
        case "mg", "mgs", "milligram", "milligrams", "milligram(s)": return "mg"
        case "mcg", "ug", "µg", "μg", "microgram", "micrograms", "microgram(s)", "mcgs": return "mcg"
        case "mcg dfe", "µg dfe", "ug dfe": return "mcg DFE"
        case "mg dfe": return "mg DFE"
        case "mcg rae", "µg rae", "ug rae": return "mcg RAE"
        case "mg ne": return "mg NE"
        case "mg {alpha}-te", "mg alpha-te", "mg ate", "mg α-te": return "mg α-TE"
        case "iu", "i.u.", "iu's", "ius": return "IU"
        case "calorie(s)", "{calories}", "calories", "calorie", "kcal", "cal": return "kcal"
        case "kj": return "kJ"
        case "ml", "milliliter", "milliliters", "millilitre": return "ml"
        case "cfu", "cfus": return "CFU"
        case "%": return "%"
        default: return unit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// A line's followed nutrient and its amount in that nutrient's unit, or nil when it isn't one
    /// or its unit can't be converted (a "%", enzyme units, IU of anything but vitamins A, D and E).
    public static func read(name: String, amount: Double, unit printed: String) -> (key: String, value: Double)? {
        guard amount.isFinite, amount >= 0, let key = key(for: name), let target = units[key] else { return nil }
        let unit = Self.unit(printed)
        let lower = clean(name)
        var value: Double?
        switch unit {
        case "kcal":
            value = key == "kcal" ? amount : nil
        case "kJ":
            value = key == "kcal" ? amount / 4.184 : nil
        case "IU":
            switch key {
            case "vitaminD": value = amount / 40
            // Retinol and supplemental beta-carotene are both 0.3 µg RAE an IU.
            case "vitaminA": value = amount * 0.3
            // Synthetic (dl-) vitamin E is 0.45 mg an IU; natural, and labels that don't say, 0.67.
            case "vitaminE": value = amount * (lower.hasPrefix("dl-") ? 0.45 : 0.67)
            default: value = nil
            }
        case "g", "mg", "mcg", "mcg DFE", "mg DFE", "mcg RAE", "mg NE", "mg α-TE":
            guard target != "kcal" else { return nil }
            let mg: Double = switch unit {
            case "g": amount * 1000
            case "mcg", "mcg DFE", "mcg RAE": amount / 1000
            default: amount
            }
            value = target == "g" ? mg / 1000 : (target == "mg" ? mg : mg * 1000)
            // Folic acid counts 1.7 times as folate (µg DFE); a label in DFE has done that already.
            if key == "folate", unit == "mcg" || unit == "mg" { value = value! * 1.7 }
            // Supplemental beta-carotene in micrograms is half as much vitamin A.
            if key == "vitaminA", lower.contains("carotene"), unit != "mcg RAE" { value = value! / 2 }
        case "":
            // A macro's column of bare numbers is grams, calories are calories; anything else is a % or a guess.
            value = key == "kcal" || (target == "g" && macroKeys.contains(key)) ? amount : nil
        default:
            value = nil
        }
        guard let value, value.isFinite, value <= plausible(key) else { return nil }
        return (key, value)
    }

    /// The most a serving could hold before the number must be a misread.
    static func plausible(_ key: String) -> Double {
        switch units[key] {
        case "kcal": 2000
        case "g": 200
        case "mg": key == "caffeine" ? 1500 : 50_000
        default: 100_000
        }
    }
}
