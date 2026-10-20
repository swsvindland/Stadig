import Foundation
import NutritionEngine
import SwiftUI
import SystemCore

/// Numbers as people read them on the wrist, worded as the phone words them.
enum WristFormat {
    /// "1,640"
    static func whole(_ value: Double) -> String { Int(value.rounded()).formatted() }

    /// "1,640 kcal"
    static func kcal(_ value: Double) -> String { "\(whole(value)) kcal" }

    /// "92 g"
    static func grams(_ value: Double) -> String { "\(Int(value.rounded())) g" }

    /// "84.2 kg"
    static func weight(_ kg: Double, unit: WeightUnit) -> String {
        "\(unit.fromKilograms(kg).formatted(.number.precision(.fractionLength(0...1)))) \(unit.symbol)"
    }

    /// A dial value in its unit: "84.2", always with its tenth so the number doesn't jump about.
    static func dial(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }

    /// "1.2 L", "350 ml", "40 fl oz".
    static func volume(_ ml: Double, ounces: Bool) -> String {
        if ounces { return "\(Int((ml / 29.5735).rounded())) fl oz" }
        return ml >= 1000 ? "\((ml / 1000).formatted(.number.precision(.fractionLength(0...1)))) L" : "\(Int(ml.rounded())) ml"
    }

    /// "45m", "3h 10m", "18h", "2d 4h", worded as the phone's but shorter.
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded(.down)))
        let hours = minutes / 60
        switch hours {
        case 0: return "\(minutes)m"
        case ..<24: return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
        case ..<48: return "\(hours)h"
        default: return "\(hours / 24)d \(hours % 24)h"
        }
    }

    /// "16 h", a fast's goal.
    static func hours(_ hours: Double) -> String { "\(Int(hours.rounded())) h" }

    /// "1,060 left", "120 over" or, with no target, "1,240 eaten"; the unit goes beside it.
    static func left(_ progress: MacroProgress) -> (value: String, label: String) {
        guard let left = progress.left else { return (whole(progress.eaten), "eaten") }
        return (whole(abs(left)), progress.isOver ? "over" : "left")
    }
}

/// One colour per macro, as on the phone.
enum MacroColor {
    static let kcal = Color.accentColor
    static let protein = Color.pink
    static let carbs = Color.blue
    static let fat = Color.orange
    static let water = Color.cyan
}
