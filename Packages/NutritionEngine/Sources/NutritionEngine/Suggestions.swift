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

    /// Foods to log again at `time` (now unless given), best first: each past entry adds
    /// `0.5^(daysAgo/21) × timeFit`, where timeFit is a Gaussian on time of day. Days ago count
    /// from now and the time of day from `time`, so lunch is what's offered for noon when catching
    /// up at 9 PM. Quick adds and estimates aren't suggested.
    public static func rank(
        _ entries: [FoodEntry], now: Date, at time: Date? = nil, calendar: Calendar = .current, limit: Int = 12
    ) -> [LogAgainItem] {
        let today = Day(now, calendar: calendar)
        let hourNow = hourOfDay(time ?? now, calendar)
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
            // Foods eaten together can tie, and a dictionary's order changes from one call to the next.
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
            .prefix(limit)
            .map { $0 }
    }

    /// What was eaten around this time of day most recently, for a one-tap "Same as yesterday":
    /// the latest other day's moment of two or more foods starting within `window` of the clock
    /// time of `now`, from the week before its day. Days after it count too, up to `through`, when
    /// a past day is being caught up: the same lunch eaten today is the likeliest one yesterday.
    public static func usualMoment(
        near now: Date, entries: [FoodEntry], calendar: Calendar = .current,
        window: TimeInterval = 90 * 60, through last: Day? = nil
    ) -> Moment? {
        let today = Day(now, calendar: calendar)
        let hourNow = hourOfDay(now, calendar)
        let latest = max(last ?? today, today)
        let recent = entries.filter { $0.day != today && $0.day >= today.adding(days: -7) && $0.day <= latest }
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

    /// "Same as yesterday" for right now: what was eaten around this time on a recent day, while
    /// nothing logged today ended within 90 minutes of `now`.
    public static func usualNow(entries: [FoodEntry], now: Date, calendar: Calendar = .current) -> Moment? {
        usual(at: now, entries: entries, today: Day(now, calendar: calendar), calendar: calendar)
    }

    /// "Same as yesterday" for a time being logged at, on any day to `today`: what was eaten around
    /// then on another recent day, while nothing logged that day ended within 90 minutes of it.
    /// `logged` is that day's whole log where `entries` leaves food for later out: what's already
    /// planned then shouldn't be offered again, and shouldn't be what's offered on another day.
    public static func usual(
        at time: Date, entries: [FoodEntry], logged: [FoodEntry]? = nil, today: Day, calendar: Calendar = .current
    ) -> Moment? {
        let day = Day(time, calendar: calendar)
        let nearby = Timeline.moments(logged ?? entries.filter { $0.day == day }).contains { abs($0.end.timeIntervalSince(time)) < 90 * 60 }
        return nearby ? nil : usualMoment(near: time, entries: entries, calendar: calendar, through: today)
    }

    /// Copies of a moment's entries at `date`, a second apart so they keep their order.
    public static func copy(_ moment: Moment, to date: Date, source: EntrySource = .copied) -> [FoodEntry] {
        moment.entries.enumerated().map { i, e in copy(e, to: date.addingTimeInterval(Double(i)), source: source) }
    }

    /// How far ahead of the clock a batch can end and still mean now.
    public static let settling: TimeInterval = 60

    /// A batch stamped just ahead of now, moved back so its last food is now. A meal's foods go in
    /// a second apart to keep their order: without this the last of them would be later food for a
    /// moment, and the meal would be split across the tick on the ring and in a fast. Just after
    /// midnight today's foods close up rather than run back into yesterday; a copy for an earlier
    /// day is already off today, and only moves with the rest.
    public static func settled(_ batch: [FoodEntry], now: Date, calendar: Calendar = .current) -> [FoodEntry] {
        guard let latest = batch.map(\.date).max(), latest > now, latest.timeIntervalSince(now) <= settling else { return batch }
        let back = latest.timeIntervalSince(now)
        let midnight = Day(now, calendar: calendar).date(calendar: calendar)
        let span = latest.timeIntervalSince(batch.map(\.date).filter { $0 >= midnight }.min() ?? latest)
        let squeeze = span > 0 ? min(1, now.timeIntervalSince(midnight) / span) : 1
        return batch.map { entry in
            var entry = entry
            entry.date =
                entry.date < midnight
                ? entry.date.addingTimeInterval(-back) : max(midnight, now.addingTimeInterval(-latest.timeIntervalSince(entry.date) * squeeze))
            entry.day = Day(entry.date, calendar: calendar)
            return entry
        }
    }

    /// A copy of an entry for now, keeping the amount and numbers.
    public static func copy(_ entry: FoodEntry, to date: Date, source: EntrySource = .recent) -> FoodEntry {
        FoodEntry(
            date: date, name: entry.name, brand: entry.brand, foodID: entry.foodID,
            amountLabel: entry.amountLabel, grams: entry.grams, unitID: entry.unitID, count: entry.count,
            nutrients: entry.nutrients, micros: entry.micros, processing: entry.processing, fermented: entry.fermented,
            fluid: entry.fluid, source: source,
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

    public static func tables(
        entries: [FoodEntry], weighIns: [WeighIn], checkIns: [CheckIn], days: [DayStatus],
        supplements: [SupplementLog] = [], water: [WaterLog] = [], fasts: [FastRun] = [], now: Date = Date(),
        calendar: Calendar = .current
    ) -> [NutritionExportTable] {
        // Times on the clock, in the zone the days are in; `.iso8601` alone writes UTC with no zone.
        let clock = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).time(includingFractionalSeconds: false)
        // Vitamins and minerals after the label basics, a column each; blank where a food didn't list it.
        let micros = Micronutrients.all.filter { !["fiber", "sodium", "saturatedFat"].contains($0.key) }
        let diary = NutritionExportTable(
            name: "diary",
            header: [
                "day", "time", "name", "brand", "amount", "grams", "kcal", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g",
                "sat_fat_g", "sodium_mg",
            ] + micros.map { "\($0.key)_\($0.unit == .µg ? "ug" : $0.unit.symbol)" }
                + ["nova", "fermented", "fluid_ml", "source", "estimate"],
            rows: entries.sorted { $0.date < $1.date }.map { e in
                [
                    e.day.iso, e.date.formatted(clock), e.name, e.brand ?? "",
                    e.amountLabel, n(e.grams), n(e.nutrients.kcal), n(e.nutrients.protein), n(e.nutrients.carbs), n(e.nutrients.fat),
                    n(e.nutrients.fiber), n(e.nutrients.sugar), n(e.nutrients.saturatedFat), n(e.nutrients.sodium),
                ]
                    + micros.map { n(e.micros?[$0.key]) }
                    + [
                        e.processing.map { String($0.rawValue) } ?? "", e.fermented.map { $0 ? "yes" : "no" } ?? "",
                        n(Hydration.fluid(of: e)), e.source.rawValue,
                        e.isEstimate ? "yes" : "no",
                    ]
            })
        let weights = NutritionExportTable(
            name: "weight",
            header: ["date", "kg", "source", "ignored"],
            rows: weighIns.sorted { $0.date < $1.date }.map { w in
                let source =
                    switch w.source {
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
        var tables = [diary, weights, targets, dayStates]
        if !supplements.isEmpty {
            let keys = Micronutrients.all.map(\.key).filter { key in supplements.contains { $0.amounts[key] != nil } }
            tables.append(
                NutritionExportTable(
                    name: "supplements",
                    header: ["day", "time", "name", "amount", "taken", "kcal"]
                        + keys.map { key in
                            let unit = Micronutrients.info(key)?.unit ?? .mg
                            return "\(key)_\(unit == .µg ? "ug" : unit.symbol)"
                        },
                    rows: supplements.sorted { $0.date < $1.date }.map { s in
                        [
                            s.day.iso, s.date.formatted(clock), s.name, s.amountLabel,
                            s.taken ? "yes" : "skipped", n(s.nutrients?.kcal),
                        ] + keys.map { n(s.amounts[$0]) }
                    }))
        }
        if !water.isEmpty {
            tables.append(
                NutritionExportTable(
                    name: "water", header: ["day", "time", "ml"],
                    rows: water.sorted { $0.date < $1.date }.map { [$0.day.iso, $0.date.formatted(clock), n($0.ml)] }))
        }
        if !fasts.isEmpty {
            // When each ended, by hand or by the meal that broke it; blank while one runs.
            let stamp = Date.ISO8601FormatStyle(timeZone: calendar.timeZone)
            tables.append(
                NutritionExportTable(
                    name: "fasts", header: ["start", "end", "hours", "goal_hours"],
                    rows: fasts.map { run in
                        [
                            run.fast.start.formatted(stamp), run.end?.formatted(stamp) ?? "", n((run.duration(at: now) / 360).rounded() / 10),
                            n(run.fast.goalHours),
                        ]
                    }))
        }
        return tables
    }
}
