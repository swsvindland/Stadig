import Foundation
import SystemCore

/// What one camera frame reads of a nutrition panel: often only part of it.
public struct LabelFrame: Hashable, Sendable {
    /// Values by key ("kcal", "protein", "sodium", "vitaminD"…), in the label's units.
    public var amounts: [String: Double]
    public var servingLabel: String?
    public var servingGrams: Double?
    public var servingMilliliters: Double?
    /// The frame shows a panel's own words ("Nutrition Facts", "Serving size", "% Daily Value") or
    /// at least two of its lines; a package's front, with its "20g PROTEIN" banner, doesn't.
    public var isPanel: Bool

    public init(
        amounts: [String: Double], servingLabel: String? = nil, servingGrams: Double? = nil, servingMilliliters: Double? = nil,
        isPanel: Bool
    ) {
        self.amounts = amounts
        self.servingLabel = servingLabel
        self.servingGrams = servingGrams
        self.servingMilliliters = servingMilliliters
        self.isPanel = isPanel
    }
}

/// How sure a value read live is.
public enum LiveValue: Hashable, Sendable {
    case missing
    /// Read, but not yet by enough frames to trust.
    case reading(Double)
    /// Read the same way in at least two frames, and by most frames that read it.
    case locked(Double)

    public var value: Double? {
        switch self {
        case .missing: nil
        case .reading(let v), .locked(let v): v
        }
    }

    public var isLocked: Bool { if case .locked = self { true } else { false } }
}

/// Counts how often each value was read; the most read wins, and is sure once it's been read twice
/// and by at least three in five of the reads.
struct Tally<Value: Hashable & Sendable>: Sendable {
    private(set) var counts: [Value: Int] = [:]
    private(set) var reads = 0

    static var agreeing: Int { 2 }
    static var share: Double { 0.6 }
    /// What a model's check counts for: two frames' worth. It settles a tie and fills a gap, but
    /// three frames that agree outvote it.
    static var checkWeight: Int { 2 }

    mutating func add(_ value: Value, weight: Int = 1) {
        counts[value, default: 0] += weight
        reads += weight
    }

    /// These reads with a model's check added.
    func checked(_ value: Value?) -> Tally {
        guard let value else { return self }
        var tally = self
        tally.add(value, weight: Self.checkWeight)
        return tally
    }

    var best: (value: Value, count: Int)? {
        counts.max { a, b in a.value != b.value ? a.value < b.value : String(describing: a.key) > String(describing: b.key) }
            .map { ($0.key, $0.value) }
    }

    var sure: Bool {
        guard let best else { return false }
        return best.count >= Self.agreeing && Double(best.count) >= Self.share * Double(reads)
    }
}

/// A nutrition panel read from a stream of camera frames. Each frame gives whatever part of the
/// panel it shows; a value is trusted once two frames agree on it and most frames that read it do,
/// so a misread in one frame is outvoted and the top and bottom of a tall label can come from
/// different moments. Frames that aren't of a panel (the package's front) are ignored, and only
/// what Macro Track tracks is kept. A model's reading of the text (`check`) counts as two votes.
public struct LiveLabel: Sendable {
    private var values: [String: Tally<Double>] = [:]
    private var grams = Tally<Double>()
    private var milliliters = Tally<Double>()
    private var measures = Tally<String>()
    /// The latest model check: values by key, and the serving.
    private var checkedValues: [String: Double] = [:]
    private var checkedGrams: Double?
    private var checkedMeasure: String?
    /// Frames read, and those that showed part of a panel.
    public private(set) var frames = 0
    public private(set) var panelFrames = 0
    /// A model has checked the text read so far.
    public private(set) var isChecked = false

    public init() {}

    /// The core fields, in the panel's order.
    public static let core = ["kcal", "fat", "carbs", "protein"]
    /// The other lines worth showing while scanning.
    public static let secondary = ["saturatedFat", "sodium", "fiber", "sugar"]

    public mutating func add(_ frame: LabelFrame) {
        frames += 1
        guard frame.isPanel else { return }
        panelFrames += 1
        for (key, value) in frame.amounts where Self.kept(key) {
            values[key, default: Tally()].add(Self.bucket(value, key: key))
        }
        if let g = frame.servingGrams { grams.add((g * 10).rounded() / 10) }
        if let ml = frame.servingMilliliters { milliliters.add((ml * 10).rounded() / 10) }
        if let label = frame.servingLabel?.trimmingCharacters(in: .whitespaces), !label.isEmpty { measures.add(label.lowercased()) }
    }

    /// A model's reading of the text so far, values it copied from it by key; it replaces the last
    /// check. Values must already be checked against the printed text.
    public mutating func check(values: [String: Double], servingGrams: Double? = nil, servingLabel: String? = nil) {
        checkedValues = values.filter { Self.kept($0.key) }.reduce(into: [:]) { $0[$1.key] = Self.bucket($1.value, key: $1.key) }
        checkedGrams = servingGrams.map { ($0 * 10).rounded() / 10 }
        checkedMeasure = servingLabel?.trimmingCharacters(in: .whitespaces).lowercased()
        if checkedMeasure?.isEmpty == true { checkedMeasure = nil }
        isChecked = true
    }

    /// The panel's lines Macro Track keeps: the macros, fiber, sugar, sodium, saturated fat, and the
    /// vitamins and minerals. Cholesterol, trans fat and added sugars are read but not kept.
    static func kept(_ key: String) -> Bool { key == "kcal" || SupplementIngredients.tracked.contains(key) }

    /// Values close enough to be the same reading: tenths of a gram, whole milligrams and calories.
    static func bucket(_ value: Double, key: String) -> Double {
        value >= 10 || key == "kcal" ? value.rounded() : (value * 10).rounded() / 10
    }

    private func tally(_ key: String) -> Tally<Double> { (values[key] ?? Tally()).checked(checkedValues[key]) }

    public func value(_ key: String) -> LiveValue {
        let tally = tally(key)
        guard let best = tally.best else { return .missing }
        return tally.sure ? .locked(best.value) : .reading(best.value)
    }

    /// Every key read so far.
    public var keys: [String] { Array(Set(values.keys).union(checkedValues.keys)) }

    /// Values trusted so far.
    public var lockedCount: Int { keys.filter { tally($0).sure }.count }

    /// The core fields not yet trusted, in the panel's order.
    public var missingCore: [String] { Self.core.filter { !value($0).isLocked } }

    /// Enough to make a food: calories and two macros, or all three macros.
    public var ready: Bool {
        let macros = ["fat", "carbs", "protein"].filter { value($0).isLocked }.count
        return (value("kcal").isLocked && macros >= 2) || macros == 3
    }

    public var serving: (label: String?, grams: Double?, milliliters: Double?) {
        (measures.checked(checkedMeasure).best?.value, grams.checked(checkedGrams).best?.value, milliliters.best?.value)
    }

    /// The panel as read so far, with the same checks as a photo's: the best value for each line
    /// (trusted or not), calories worked out from the macros when they weren't read. Nil until a
    /// panel has been seen.
    public var reading: LabelReading? {
        guard panelFrames > 0, !keys.isEmpty else { return nil }
        var read = NutritionLabel.Values()
        for key in keys { if let best = tally(key).best { read.amounts[key] = best.value } }
        NutritionLabel.check(&read)
        let serving = serving
        read.servingLabel = serving.label ?? ""
        if let g = serving.grams {
            read.servingAmount = g
            read.servingUnit = "g"
        } else if let ml = serving.milliliters {
            read.servingAmount = ml
            read.servingUnit = "ml"
        }
        return read.reading
    }
}

/// A Supplement Facts panel read from a stream of camera frames: each tracked line's amount by vote,
/// in the order the lines appear on the label, however many frames it took to see them all. A
/// model's reading of the text (`check`) counts as two votes per line, and can add a line the
/// frames missed.
public struct LiveSupplementLabel: Sendable {
    private struct Line: Sendable {
        var key: String
        var name: String
        /// The nutrient it counts as, for matching a model's "Vitamin D" to a label's "Vitamin D3".
        var nutrient: String?
        var tally = Tally<String>()
        var checked: String?

        var votes: Tally<String> { tally.checked(checked) }
    }

    private var lines: [Line] = []
    private var servings = Tally<String>()
    private var checkedServing: String?
    public private(set) var frames = 0
    public private(set) var panelFrames = 0
    public private(set) var isChecked = false

    public init() {}

    public mutating func add(_ facts: SupplementFacts?) {
        frames += 1
        guard let facts else { return }
        panelFrames += 1
        if facts.unit != "serving" { servings.add("\(facts.servingCount)|\(facts.unit)") }
        // A line not seen before goes after the line above it in this frame.
        var anchor: Int?
        for ingredient in facts.ingredients where ingredient.isTracked {
            guard let amount = ingredient.amount, let i = place(ingredient, after: anchor) else { continue }
            lines[i].tally.add(Self.reading(amount, ingredient.unit))
            anchor = i
        }
    }

    /// A model's reading of the panel; it replaces the last check. Its lines must already be checked
    /// against the printed text.
    public mutating func check(_ facts: SupplementFacts) {
        for i in lines.indices { lines[i].checked = nil }
        checkedServing = facts.unit != "serving" ? "\(facts.servingCount)|\(facts.unit)" : nil
        var anchor: Int?
        for ingredient in facts.ingredients where ingredient.isTracked {
            guard let amount = ingredient.amount, let i = place(ingredient, after: anchor) else { continue }
            lines[i].checked = Self.reading(amount, ingredient.unit)
            anchor = i
        }
        isChecked = true
    }

    /// The line an ingredient is, by name or by the one line counting as the same nutrient; a new
    /// one goes after `anchor`.
    private mutating func place(_ ingredient: SupplementIngredient, after anchor: Int?) -> Int? {
        let key = SupplementIngredients.clean(ingredient.name)
        guard !key.isEmpty else { return nil }
        if let i = lines.firstIndex(where: { $0.key == key }) ?? sameNutrient(ingredient.key) {
            // The longest name read is the one least cut off.
            if ingredient.name.count > lines[i].name.count { lines[i].name = ingredient.name }
            return i
        }
        let at = anchor.map { $0 + 1 } ?? lines.count
        lines.insert(Line(key: key, name: ingredient.name, nutrient: ingredient.key), at: at)
        return at
    }

    private func sameNutrient(_ nutrient: String?) -> Int? {
        guard let nutrient else { return nil }
        let matches = lines.indices.filter { lines[$0].nutrient == nutrient }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Tenths: supplements print 13.5 mg of vitamin E and 2.5 mcg of B12.
    private static func reading(_ amount: Double, _ unit: String) -> String { "\((amount * 10).rounded() / 10)|\(unit)" }

    /// Each line as read so far, in label order, with whether it's been read the same way twice.
    public var readLines: [(ingredient: SupplementIngredient, locked: Bool)] {
        lines.compactMap { line in
            let votes = line.votes
            guard let best = votes.best else { return nil }
            let parts = best.value.split(separator: "|", maxSplits: 1).map(String.init)
            guard let amount = Double(parts[0]) else { return nil }
            return (SupplementIngredient(name: line.name, amount: amount, unit: parts.count > 1 ? parts[1] : ""), votes.sure)
        }
    }

    public var lockedCount: Int { lines.filter(\.votes.sure).count }

    /// Two lines trusted, or a serving and one line.
    public var ready: Bool { lockedCount >= 2 || (lockedCount >= 1 && servings.checked(checkedServing).best != nil) }

    /// The panel as read so far; its name is left for the person or the model. A panel seen twice
    /// with nothing Macro Track tracks on it (melatonin, ashwagandha) is still a supplement.
    public var facts: SupplementFacts? {
        let read = readLines.map(\.ingredient)
        guard !read.isEmpty || panelFrames >= 2 else { return nil }
        let serving = servings.checked(checkedServing).best.flatMap { best -> (Double, String)? in
            let parts = best.value.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let count = Double(parts[0]) else { return nil }
            return (count, parts[1])
        }
        return SupplementFacts(
            id: "custom:\(UUID().uuidString)", name: "", servingCount: serving?.0 ?? 1, unit: serving?.1 ?? "serving",
            ingredients: read, source: .label)
    }
}
