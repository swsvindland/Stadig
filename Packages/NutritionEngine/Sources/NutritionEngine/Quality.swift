import Foundation
import SystemCore

/// Fermented foods with live cultures, by name: for entries whose food didn't say (custom foods,
/// quick adds, estimates), in the languages packaged foods are named in.
public enum Fermented {
    private static let names: Set<String> = [
        "yogurt", "yoghurt", "yogourt", "yoghourt", "joghurt", "jogurt", "yaourt", "yogur", "iogurte", "kefir", "kéfir", "kimchi",
        "sauerkraut", "choucroute", "kombucha", "miso", "natto", "tempeh", "skyr", "lassi", "ayran", "kvass",
    ]
    /// Fermented, but frozen, baked, coated or cooked past the live cultures.
    private static let notLive: Set<String> = [
        "frozen", "froyo", "covered", "coated", "raisins", "pretzels", "bar", "bars", "bread", "cake", "cookie", "cookies",
        "cracker", "crackers", "chips", "cereal", "granola", "dressing", "sauce", "powder", "soup", "candy", "candies", "muffin",
        "cooked", "canned", "chocolate", "gummies", "bites", "melts",
    ]

    public static func isFermented(_ name: String) -> Bool {
        let words = Set(name.lowercased().split { !$0.isLetter }.map(String.init))
        return !words.isDisjoint(with: names) && words.isDisjoint(with: notLive) && !name.lowercased().contains("ice cream")
    }

    /// Whether an entry counts: what its food said, else its name.
    public static func isFermented(_ entry: FoodEntry) -> Bool {
        entry.fermented ?? isFermented(entry.name)
    }
}

/// What the week's food was made of: how much came from whole foods and how much was
/// ultra-processed, and how often something fermented was eaten. Calories are what's weighed,
/// since that's what the research measured and what a swap changes.
public struct QualityReport: Hashable, Sendable {
    public enum Status: String, Sendable {
        case good
        /// Above the aim, but not by enough to act on.
        case fair
        case off
        case unknown
    }

    /// A food that gave the week ultra-processed calories.
    public struct Source: Hashable, Sendable, Identifiable {
        public var name: String
        public var foodID: String?
        /// Calories a day from it, on average over the days read.
        public var kcal: Double
        /// Its share of all calories eaten.
        public var share: Double
        /// The last time it was logged, for its usual portion.
        public var entry: FoodEntry

        public var id: String { foodID ?? name }
    }

    /// Complete days read.
    public var days: [Day]
    /// Each group's share of the calories whose group is known, summing to 1.
    public var shares: [Processing: Double]
    /// The share of calories eaten whose group is known, 0–1.
    public var coverage: Double
    /// Ultra-processed foods by calories, biggest first.
    public var ultraSources: [Source]
    /// Days read with something fermented.
    public var fermentedDays: Int
    /// The fermented foods eaten, most often first.
    public var fermentedFoods: [String]

    public static let empty = QualityReport(days: [], shares: [:], coverage: 0, ultraSources: [], fermentedDays: 0, fermentedFoods: [])

    /// Enough logged, and enough of it with a known group, to say.
    public var known: Bool { days.count >= QualityAnalyst.minimumDays && coverage >= QualityAnalyst.minimumCoverage }

    public func share(_ group: Processing) -> Double? { known ? shares[group] ?? 0 : nil }

    public var ultraStatus: Status {
        guard let share = share(.ultraProcessed) else { return .unknown }
        return share <= QualityAnalyst.ultraAim ? .good : (share <= QualityAnalyst.ultraLimit ? .fair : .off)
    }

    /// Fermented foods a week at this rate.
    public var fermentedPerWeek: Double? {
        days.count >= QualityAnalyst.minimumDays ? Double(fermentedDays) * 7 / Double(days.count) : nil
    }

    public var fermentedStatus: Status {
        guard let rate = fermentedPerWeek else { return .unknown }
        // Rounded, so 3 days of 6 is "most days" and 2 of 7 is not.
        return rate.rounded() >= Double(QualityAnalyst.fermentedAim) ? .good : (rate >= 2 ? .fair : .off)
    }
}

public enum QualityAnalyst {
    /// Complete days a report needs before it says anything.
    public static let minimumDays = 3
    /// Below this share of calories with a known group, processing is unknown.
    public static let minimumCoverage = 0.6
    /// Ultra-processed calories to stay under, and the share above which it's worth acting on.
    /// Most adults in the US and UK eat over half their calories this way.
    public static let ultraAim = 0.2
    public static let ultraLimit = 0.3
    /// Days a week with something fermented: the Stanford trial's gains in gut diversity came from
    /// a daily habit; most days is the practical aim.
    public static let fermentedAim = 4

    /// The last seven complete days (from the last fortnight), the same days the nutrients read.
    public static func report(entries: [FoodEntry], complete: Set<Day>, today: Day) -> QualityReport {
        let days = complete.filter { $0 < today && $0 >= today.adding(days: -14) }.sorted(by: >).prefix(7)
        let window = Set(days)
        let eaten = entries.filter { window.contains($0.day) }
        let total = eaten.map { max(0, $0.nutrients.kcal) }.reduce(0, +)
        var byGroup: [Processing: Double] = [:]
        var ultra: [String: (kcal: Double, entry: FoodEntry)] = [:]
        for entry in eaten {
            let kcal = max(0, entry.nutrients.kcal)
            guard let group = entry.processing else { continue }
            byGroup[group, default: 0] += kcal
            if group == .ultraProcessed {
                let key = entry.foodID ?? entry.name.lowercased()
                let last = ultra[key].map { $0.entry.date > entry.date ? $0.entry : entry } ?? entry
                ultra[key] = ((ultra[key]?.kcal ?? 0) + kcal, last)
            }
        }
        let known = byGroup.values.reduce(0, +)
        let shares = known > 0 ? byGroup.mapValues { $0 / known } : [:]
        let n = Double(max(1, days.count))
        let sources = ultra.values.sorted { $0.kcal > $1.kcal }.prefix(3).map { kcal, entry in
            QualityReport.Source(name: entry.name, foodID: entry.foodID, kcal: kcal / n, share: total > 0 ? kcal / total : 0, entry: entry)
        }
        let fermented = eaten.filter { Fermented.isFermented($0) }
        let fermentedDays = Set(fermented.map(\.day)).count
        let fermentedFoods = Dictionary(grouping: fermented, by: \.name).sorted { $0.value.count > $1.value.count }.map(\.key)
        return QualityReport(days: Array(days), shares: shares, coverage: total > 0 ? known / total : 0, ultraSources: Array(sources),
                             fermentedDays: fermentedDays, fermentedFoods: fermentedFoods)
    }
}
