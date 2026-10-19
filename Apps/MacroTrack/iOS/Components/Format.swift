import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore

/// Numbers as people read them.
enum Format {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    /// "1,640 kcal"
    static func kcal(_ value: Double) -> String { "\(Int(value.rounded()).formatted()) kcal" }

    /// "1,640", for places that label the unit once.
    static func whole(_ value: Double) -> String { Int(value.rounded()).formatted() }

    /// "92 g"
    static func grams(_ value: Double) -> String { "\(Int(value.rounded())) g" }

    static func weight(_ kg: Double?, unit: WeightUnit) -> String {
        guard let kg else { return "—" }
        return "\(number(unit.fromKilograms(kg))) \(unit.symbol)"
    }

    /// "−0.4 kg a week"
    static func weeklyChange(_ kg: Double, unit: WeightUnit) -> String {
        let value = unit.fromKilograms(kg)
        let sign = value > 0.005 ? "+" : value < -0.005 ? "−" : ""
        return "\(sign)\(abs(value).formatted(.number.precision(.fractionLength(2)))) \(unit.symbol) a week"
    }

    static func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }

    static func day(_ day: Day, style: Date.FormatStyle = .dateTime.weekday(.abbreviated).month(.abbreviated).day()) -> String {
        day.date().formatted(style)
    }

    /// "Today", "Yesterday", or "Tue 14 Oct".
    static func relative(_ day: Day, today: Day = .today) -> String {
        switch day.days(until: today) {
        case 0: "today"
        case 1: "yesterday"
        default: Format.day(day)
        }
    }

    /// "Sat, Oct 17", with the year once it isn't this one's: a row of a history table.
    static func historyDay(_ day: Day, today: Day) -> String {
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        return Format.day(day, style: day.components.year == today.components.year ? style : style.year())
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// "P 32 · C 40 · F 12"
    static func macros(_ n: Nutrients) -> String {
        "P \(Int(n.protein.rounded())) · C \(Int(n.carbs.rounded())) · F \(Int(n.fat.rounded()))"
    }

    /// A number for a text field that's parsed back: never grouped, since "1,200" would read back as
    /// 1.2 (`FoodUnits.parseCount` takes a comma for the decimal point), in the locale's decimals.
    static func editable(_ value: Double, digits: Int = 2, locale: Locale = .current) -> String {
        guard value.isFinite else { return "" }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...digits)).locale(locale))
    }

    /// A number typed into a field: "1.5", "1,5", "1½", "1 1/2"; nil for anything else. The one
    /// parse for every field, so a Save button's check and what it saves can't disagree.
    static func parse(_ text: String) -> Double? { FoodUnits.parseCount(text) }
}
