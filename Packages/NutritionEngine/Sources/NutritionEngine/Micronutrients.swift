import Foundation
import SystemCore

/// Units the catalogs keep each nutrient in.
public enum NutrientUnit: String, Sendable {
    case g, mg, µg

    public var symbol: String { rawValue }
}

/// A nutrient worth knowing about, with its daily target for a person.
public struct NutrientInfo: Hashable, Sendable, Identifiable {
    /// Whether more is the aim (potassium) or less (sodium).
    public enum Goal: String, Sendable { case atLeast, atMost }

    /// The catalog key: "potassium", "vitaminD", or a core one ("fiber", "sodium").
    public var key: String
    public var label: String
    public var unit: NutrientUnit
    public var goal: Goal
    /// Commonly short (or over) and fixable with ordinary food, so worth an action when it is.
    /// Others are shown, never flagged: vitamin D, say, comes mostly from sunlight.
    public var watched: Bool
    /// Why it matters, in a line.
    public var why: String

    public var id: String { key }
}

/// The nutrients Macro Track follows and each person's daily targets: the US National Academies'
/// Dietary Reference Intakes for adults (RDA or AI; the CDRR for sodium), fibre at 14 g per
/// 1,000 kcal, and saturated fat under 10% of calories.
public enum Micronutrients {
    public static let all: [NutrientInfo] = [
        info("fiber", "Fiber", .g, watched: true, "Fullness, digestion and steadier blood sugar."),
        info("potassium", "Potassium", .mg, watched: true, "Blood pressure and muscle function."),
        info("magnesium", "Magnesium", .mg, watched: true, "Muscle and nerve function, sleep, energy."),
        info("calcium", "Calcium", .mg, watched: true, "Bones and muscle contraction."),
        info("iron", "Iron", .mg, watched: true, "Carrying oxygen; low iron feels like low energy."),
        info("vitaminC", "Vitamin C", .mg, watched: true, "Recovery, immunity, and absorbing iron."),
        info("folate", "Folate", .µg, watched: true, "Making new cells."),
        info("vitaminB12", "Vitamin B12", .µg, watched: true, "Nerves and red blood cells; mostly from animal foods."),
        info("sodium", "Sodium", .mg, .atMost, watched: true, "Blood pressure, and water the scale shows."),
        info("saturatedFat", "Saturated fat", .g, .atMost, watched: true, "Heart health over the years."),
        info("vitaminD", "Vitamin D", .µg, watched: false, "Bones and muscle; mostly from sunlight."),
        info("omega3", "Omega-3", .g, watched: false, "Heart and brain; fish twice a week covers it."),
        info("zinc", "Zinc", .mg, watched: false, "Immunity, healing, and testosterone."),
        info("vitaminA", "Vitamin A", .µg, watched: false, "Vision, skin and immunity."),
        info("vitaminK", "Vitamin K", .µg, watched: false, "Blood clotting and bones."),
        info("vitaminE", "Vitamin E", .mg, watched: false, "An antioxidant in cell membranes."),
        info("vitaminB6", "Vitamin B6", .mg, watched: false, "Using protein, and mood."),
        info("thiamin", "Thiamin (B1)", .mg, watched: false, "Turning food into energy."),
        info("riboflavin", "Riboflavin (B2)", .mg, watched: false, "Turning food into energy."),
        info("niacin", "Niacin (B3)", .mg, watched: false, "Turning food into energy."),
        info("pantothenicAcid", "Pantothenic acid (B5)", .mg, watched: false, "Turning food into energy."),
        info("choline", "Choline", .mg, watched: false, "Liver, muscle and memory."),
        info("phosphorus", "Phosphorus", .mg, watched: false, "Bones and energy."),
        info("selenium", "Selenium", .µg, watched: false, "Thyroid and immunity."),
        info("copper", "Copper", .mg, watched: false, "Iron use and connective tissue."),
        info("manganese", "Manganese", .mg, watched: false, "Bones and metabolism."),
        info("caffeine", "Caffeine", .mg, .atMost, watched: false, "Up to 400 mg a day is fine for most adults."),
    ]

    public static func info(_ key: String) -> NutrientInfo? { all.first { $0.key == key } }

    private static func info(_ key: String, _ label: String, _ unit: NutrientUnit, _ goal: NutrientInfo.Goal = .atLeast,
                             watched: Bool, _ why: String) -> NutrientInfo {
        NutrientInfo(key: key, label: label, unit: unit, goal: goal, watched: watched, why: why)
    }

    /// The daily target for an adult. `kcal` is the day's calorie target (or maintenance), which
    /// fibre and saturated fat scale with.
    public static func target(_ key: String, sex: BiologicalSex, age: Int?, kcal: Double) -> Double? {
        let age = age ?? 35
        // Unspecified sex takes the higher of the two, so nothing is flagged that might be fine.
        let female = sex == .female
        func pick(_ male: Double, _ woman: Double) -> Double { sex == .unspecified ? max(male, woman) : (female ? woman : male) }
        switch key {
        case "fiber": return (14 * kcal / 1000).rounded()
        case "potassium": return pick(3400, 2600)
        case "magnesium": return age < 31 ? pick(400, 310) : pick(420, 320)
        case "calcium": return (female && age > 50) || (!female && age > 70) ? 1200 : 1000
        case "iron": return female && age <= 50 ? 18 : (sex == .unspecified && age <= 50 ? 18 : 8)
        case "vitaminC": return pick(90, 75)
        case "folate": return 400
        case "vitaminB12": return 2.4
        case "sodium": return 2300
        case "saturatedFat": return (0.1 * kcal / 9).rounded()
        case "vitaminD": return age > 70 ? 20 : 15
        case "omega3": return pick(1.6, 1.1)
        case "zinc": return pick(11, 8)
        case "vitaminA": return pick(900, 700)
        case "vitaminK": return pick(120, 90)
        case "vitaminE": return 15
        case "vitaminB6": return age > 50 ? pick(1.7, 1.5) : 1.3
        case "thiamin": return pick(1.2, 1.1)
        case "riboflavin": return pick(1.3, 1.1)
        case "niacin": return pick(16, 14)
        case "pantothenicAcid": return 5
        case "choline": return pick(550, 425)
        case "phosphorus": return 700
        case "selenium": return 55
        case "copper": return 0.9
        case "manganese": return pick(2.3, 1.8)
        case "caffeine": return 400
        default: return nil
        }
    }

    /// An entry's amount of a nutrient, or nil when its food didn't list it.
    public static func amount(_ key: String, in entry: FoodEntry) -> Double? {
        switch key {
        case "fiber": entry.nutrients.fiber
        case "sodium": entry.nutrients.sodium
        case "saturatedFat": entry.nutrients.saturatedFat
        case "sugar": entry.nutrients.sugar
        default: entry.micros?[key]
        }
    }
}

/// How a nutrient stands over the last week of complete days.
public struct NutrientReading: Hashable, Sendable, Identifiable {
    public enum Status: String, Sendable {
        /// Well under the target (under 70%) for a nutrient to get enough of.
        case low
        case ok
        /// Over the limit, for one to keep under.
        case high
        /// Too little of what was eaten lists it to say.
        case unknown
    }

    public var nutrient: NutrientInfo
    /// The daily average, allowing for foods that don't list it (nil when unknown).
    public var daily: Double?
    /// The daily average from the foods that list it.
    public var measured: Double
    /// The share of calories eaten that came with a value for it, 0–1.
    public var coverage: Double
    public var target: Double?
    public var status: Status
    /// Foods that gave the most of it, biggest first.
    public var sources: [String]

    public var id: String { nutrient.key }
    /// The estimate against the target, 0–… (nil when either is missing).
    public var fraction: Double? { (daily ?? (nutrient.goal == .atMost ? measured : nil)).flatMap { d in target.map { $0 > 0 ? d / $0 : 0 } } }
}

/// The week's vitamins and minerals: which are short, which are over, and how much of what was
/// eaten can say.
public struct MicroReport: Hashable, Sendable {
    /// Complete days read.
    public var days: [Day]
    public var readings: [NutrientReading]

    /// Watched nutrients off target, worst first. Empty until three complete days are known.
    public var flagged: [NutrientReading] {
        guard days.count >= MicroAnalyst.minimumDays else { return [] }
        return readings.filter { $0.nutrient.watched && ($0.status == .low || $0.status == .high) }
            .sorted { severity($0) > severity($1) }
    }

    func severity(_ r: NutrientReading) -> Double {
        guard let f = r.fraction else { return 0 }
        return r.status == .low ? 1 - f : f - 1
    }

    public func reading(_ key: String) -> NutrientReading? { readings.first { $0.nutrient.key == key } }

    public static let empty = MicroReport(days: [], readings: [])
}

public enum MicroAnalyst {
    /// Complete days a report needs before it flags anything.
    public static let minimumDays = 3
    /// Below this share of calories with a value, a nutrient is unknown rather than low.
    public static let minimumCoverage = 0.5

    /// The last seven complete days (from the last fortnight) of a person's log, read against their targets.
    public static func report(entries: [FoodEntry], complete: Set<Day>, profile: SharedProfile, kcal: Double, today: Day) -> MicroReport {
        let days = complete.filter { $0 < today && $0 >= today.adding(days: -14) }.sorted(by: >).prefix(7)
        let window = Set(days)
        let eaten = entries.filter { window.contains($0.day) }
        let totalKcal = eaten.map { max(0, $0.nutrients.kcal) }.reduce(0, +)
        let age = profile.age(on: today)
        var readings: [NutrientReading] = []
        for nutrient in Micronutrients.all {
            var sum = 0.0, knownKcal = 0.0
            var bySource: [String: Double] = [:]
            for entry in eaten {
                guard let value = Micronutrients.amount(nutrient.key, in: entry) else { continue }
                sum += value
                knownKcal += max(0, entry.nutrients.kcal)
                bySource[entry.name, default: 0] += value
            }
            let n = Double(max(1, days.count))
            let measured = sum / n
            // Zero-calorie foods (water, black coffee) say nothing about coverage either way.
            let coverage = totalKcal > 0 ? knownKcal / totalKcal : 0
            let target = Micronutrients.target(nutrient.key, sex: profile.sex, age: age, kcal: kcal)
            // Foods without a value are assumed alike the ones with: for "enough", that errs
            // toward not flagging.
            let daily: Double? = coverage >= minimumCoverage ? measured / coverage : nil
            let status: NutrientReading.Status
            if days.isEmpty || target == nil {
                status = .unknown
            } else if nutrient.goal == .atMost {
                // Only what was measured counts toward a limit, so "over" is never a guess.
                status = coverage >= minimumCoverage || measured > target! ? (measured > target! ? .high : .ok) : .unknown
            } else if let daily {
                status = daily < 0.7 * target! ? .low : .ok
            } else {
                status = measured >= target! ? .ok : .unknown
            }
            let sources = bySource.sorted { $0.value > $1.value }.prefix(3).map(\.key)
            readings.append(NutrientReading(nutrient: nutrient, daily: daily, measured: measured, coverage: coverage, target: target,
                                            status: status, sources: sources))
        }
        return MicroReport(days: Array(days), readings: readings)
    }
}
