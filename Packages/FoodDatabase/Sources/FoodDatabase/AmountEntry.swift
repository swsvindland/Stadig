import Foundation

/// A quantity being entered on the amount keypad. It opens selected, so the first key replaces the
/// amount offered rather than adding to it, and it holds only what the keys can make: a whole number,
/// a whole number with a fraction, or a decimal.
public struct AmountEntry: Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        case digit(Int)
        case point
        /// "¼", "⅓", "½", "⅔" or "¾".
        case fraction(String)
        case delete
    }

    /// What the field shows, with "." as the point: `display(locale:)` is for reading.
    public private(set) var text: String
    public private(set) var unit: PortionUnit?
    /// The amount offered and not touched yet: the next key replaces it.
    public private(set) var isSelected = true
    /// A number the person entered, which changing the unit keeps as it is: "150" then "oz" means
    /// 150 oz. An amount offered is converted instead: 1 cup becomes 240 g.
    public private(set) var isTyped = false
    /// What the 0.5–2× choices are multiples of.
    public private(set) var base: Double

    /// Long enough for any real amount, short enough to fit the field.
    static let wholeDigits = 6
    static let decimals = 2

    public init(count: Double, unit: PortionUnit?) {
        self.unit = unit
        base = count
        text = unit.map { FoodUnits.format(count, $0) } ?? Self.plain(count)
    }

    /// The amount entered, or nil while it isn't one yet (empty, or 0).
    public var count: Double? {
        let digits = text.hasSuffix(".") ? String(text.dropLast()) : text
        guard let value = FoodUnits.parseCount(digits), value > 0 else { return nil }
        return value
    }

    public func display(locale: Locale = .current) -> String {
        text.isEmpty ? "0" : text.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }

    public mutating func press(_ key: Key) {
        switch key {
        case .digit(let digit): add(digit)
        case .point: addPoint()
        case .fraction(let glyph): addFraction(glyph)
        case .delete: deleteLast()
        }
    }

    /// Whatever the person's typed in a field of the Mac's, kept as they typed it.
    public mutating func type(_ typed: String) {
        guard typed != text else { return }
        text = typed
        isSelected = false
        isTyped = true
    }

    /// One of the 0.5–2× choices: an amount offered, so the next key replaces it again.
    public mutating func choose(_ value: Double) {
        text = unit.map { FoodUnits.format(value, $0) } ?? Self.plain(value)
        isSelected = true
        isTyped = false
    }

    /// VoiceOver's up and down, or anything else that nudges: to the next step, never below one step.
    public mutating func nudge(up: Bool) {
        let step = unit.map(FoodUnits.step) ?? 0.5
        choose(max(step, (count ?? 0) + (up ? step : -step)))
    }

    public mutating func change(to next: PortionUnit) {
        guard next != unit else { return }
        defer { unit = next }
        guard let old = unit, let value = count else { return }
        if isTyped {
            base = value
            return
        }
        // Keep the amount: 1 cup becomes 240 g, not 1 g, rounded for the new unit.
        let converted = FoodUnits.convert(value, from: old, to: next)
        guard converted.isFinite else { return }
        base = converted
        text = FoodUnits.format(converted, next)
        isSelected = true
    }

    private mutating func begin() {
        if isSelected { text = "" }
        isSelected = false
        isTyped = true
    }

    private mutating func add(_ digit: Int) {
        begin()
        guard (0...9).contains(digit), !endsInFraction else { return }
        if text == "0" { text = "" }
        if let point = text.firstIndex(of: ".") {
            guard text.distance(from: point, to: text.endIndex) <= Self.decimals else { return }
        } else {
            guard text.count < Self.wholeDigits else { return }
        }
        text += String(digit)
    }

    private mutating func addPoint() {
        begin()
        guard !text.contains("."), !endsInFraction else { return }
        text = (text.isEmpty ? "0" : text) + "."
    }

    /// After a whole number; a second fraction takes the place of the first.
    private mutating func addFraction(_ glyph: String) {
        begin()
        guard !text.contains(".") else { return }
        if endsInFraction { text.removeLast() }
        if text == "0" { text = "" }
        text += glyph
    }

    private mutating func deleteLast() {
        begin()
        if !text.isEmpty { text.removeLast() }
    }

    private var endsInFraction: Bool { text.last.map { Self.fractions.contains($0) } ?? false }

    private static let fractions: Set<Character> = ["¼", "⅓", "½", "⅔", "¾"]

    private static func plain(_ value: Double) -> String {
        value == value.rounded() ? String(Int(min(value, FoodUnits.maxCount))) : String(format: "%.2f", value).trimmingTrailingZeros
    }
}

extension String {
    fileprivate var trimmingTrailingZeros: String {
        var text = self
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
