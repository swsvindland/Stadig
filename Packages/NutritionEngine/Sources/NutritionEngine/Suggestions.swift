import Foundation
import SystemCore

/// Something worth logging again right now, with the entry to copy.
public struct LogAgainItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var template: FoodEntry
    public var score: Double
    public var timesLogged: Int
}

public enum LogAgain {
    /// Recency half-life, days.
    public static let halfLife = 21.0
    /// Spread of the time-of-day fit, hours.
    public static let hourSpread = 1.5

    static func key(_ entry: FoodEntry) -> String {
        entry.foodID ?? "\(entry.name.lowercased())|\(entry.brand?.lowercased() ?? "")"
    }

    /// Foods to log again now, best first: each past entry adds `0.5^(daysAgo/21) × timeFit`,
    /// where timeFit is a Gaussian on time of day. Quick adds and estimates aren't suggested.
    public static func rank(_ entries: [FoodEntry], now: Date, calendar: Calendar = .current, limit: Int = 12) -> [LogAgainItem] {
        let today = Day(now, calendar: calendar)
        let hourNow = hourOfDay(now, calendar)
        var scores: [String: (score: Double, count: Int, latest: FoodEntry)] = [:]
        for entry in entries where entry.source != .quickAdd && entry.day <= today && entry.day > today.adding(days: -180) {
            let days = Double(entry.day.days(until: today))
            let recency = pow(0.5, days / halfLife)
            var diff = abs(hourOfDay(entry.date, calendar) - hourNow)
            diff = min(diff, 24 - diff)
            let fit = max(0.1, exp(-(diff * diff) / (2 * hourSpread * hourSpread)))
            let k = key(entry)
            var current = scores[k] ?? (0, 0, entry)
            current.score += recency * fit
            current.count += 1
            if entry.date > current.latest.date { current.latest = entry }
            scores[k] = current
        }
        return scores.map { LogAgainItem(id: $0.key, template: $0.value.latest, score: $0.value.score, timesLogged: $0.value.count) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// What was eaten around this time of day most recently, for a one-tap "Same as yesterday":
    /// the latest earlier day's moment of two or more foods starting within `window` of the
    /// clock time of `now`, from the last week.
    public static func usualMoment(near now: Date, entries: [FoodEntry], calendar: Calendar = .current,
                                   window: TimeInterval = 90 * 60) -> Moment? {
        let today = Day(now, calendar: calendar)
        let hourNow = hourOfDay(now, calendar)
        let recent = entries.filter { $0.day < today && $0.day >= today.adding(days: -7) }
        for day in Set(recent.map(\.day)).sorted(by: >) {
            let moments = Timeline.moments(recent.filter { $0.day == day }).filter { $0.entries.count >= 2 }
            let near = moments.map { moment -> (Moment, Double) in
                var diff = abs(hourOfDay(moment.start, calendar) - hourNow)
                diff = min(diff, 24 - diff)
                return (moment, diff)
            }.filter { $0.1 * 3600 <= window }
            if let best = near.min(by: { $0.1 < $1.1 }) { return best.0 }
        }
        return nil
    }

    /// Copies of a moment's entries at `date`, a second apart so they keep their order.
    public static func copy(_ moment: Moment, to date: Date, source: EntrySource = .copied) -> [FoodEntry] {
        moment.entries.enumerated().map { i, e in copy(e, to: date.addingTimeInterval(Double(i)), source: source) }
    }

    /// A copy of an entry for now, keeping the amount and numbers.
    public static func copy(_ entry: FoodEntry, to date: Date, source: EntrySource = .recent) -> FoodEntry {
        FoodEntry(date: date, name: entry.name, brand: entry.brand, foodID: entry.foodID,
                  amountLabel: entry.amountLabel, grams: entry.grams, unitID: entry.unitID, count: entry.count,
                  nutrients: entry.nutrients, source: source,
                  confidence: entry.confidence)
    }

    static func hourOfDay(_ date: Date, _ calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }
}

/// CSV tables: your data, portable.
public struct NutritionExportTable: Sendable {
    public var name: String
    public var header: [String]
    public var rows: [[String]]
}

public enum NutritionExport {
    static func n(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    public static func tables(entries: [FoodEntry], weighIns: [WeighIn], checkIns: [CheckIn], days: [DayStatus]) -> [NutritionExportTable] {
        let diary = NutritionExportTable(
            name: "diary",
            header: ["day", "time", "name", "brand", "amount", "grams", "kcal", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g",
                     "sat_fat_g", "sodium_mg", "source", "estimate"],
            rows: entries.sorted { $0.date < $1.date }.map { e in
                [e.day.iso, e.date.formatted(.iso8601.time(includingFractionalSeconds: false)), e.name, e.brand ?? "",
                 e.amountLabel, n(e.grams), n(e.nutrients.kcal), n(e.nutrients.protein), n(e.nutrients.carbs), n(e.nutrients.fat),
                 n(e.nutrients.fiber), n(e.nutrients.sugar), n(e.nutrients.saturatedFat), n(e.nutrients.sodium), e.source.rawValue,
                 e.isEstimate ? "yes" : "no"]
            })
        let weights = NutritionExportTable(
            name: "weight",
            header: ["date", "kg", "source", "ignored"],
            rows: weighIns.sorted { $0.date < $1.date }.map { w in
                let source = switch w.source {
                case .health: "Health"
                case .manual: "Manual"
                }
                return [w.date.ISO8601Format(), n(w.kg), source, w.excluded ? "yes" : "no"]
            })
        let targets = NutritionExportTable(
            name: "targets",
            header: ["from", "maintenance_kcal", "kcal", "protein_g", "carbs_g", "fat_g", "status", "reason"],
            rows: checkIns.sorted { $0.day < $1.day }.map { c in
                [c.day.iso, n(c.expenditure), n(c.kcal), n(c.protein), n(c.carbs), n(c.fat), c.status.rawValue, c.reason]
            })
        let dayStates = NutritionExportTable(
            name: "days", header: ["day", "status"], rows: days.sorted { $0.day < $1.day }.map { [$0.day.iso, $0.state.rawValue] })
        return [diary, weights, targets, dayStates]
    }
}
