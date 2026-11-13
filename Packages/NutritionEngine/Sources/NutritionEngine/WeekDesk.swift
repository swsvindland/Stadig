import Foundation
import SystemCore

// The week desk (the Mac and an iPad on its side): seven days side by side, each day's meals stacked
// toward its target, what's eaten and what's still to come, and what moving a meal to another day
// does to both days and to the week.

/// A meal the meal plan has on a day, as the desk shows it. The app reads the plan (this package
/// doesn't know the planner): what the dish is called, when it's eaten, its foods and its numbers.
public struct WeekPlanned: Hashable, Sendable {
    public var id: String
    public var time: Date
    public var name: String
    /// The dish's foods by name, for its markers.
    public var foods: [String]
    public var nutrients: Nutrients

    public init(id: String, time: Date, name: String, foods: [String], nutrients: Nutrients) {
        self.id = id
        self.time = time
        self.name = name
        self.foods = foods
        self.nutrients = nutrients
    }
}

/// A meal on the desk: food logged together (a ``Moment``), or a dish the meal plan has for a time
/// still to come.
public struct WeekMeal: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// Logged, and its time has come.
        case eaten
        /// Logged for later.
        case later
        /// On the meal plan, not logged.
        case planned
    }

    public var id: String
    public var day: Day
    public var start: Date
    /// A saved meal's name, else its biggest foods: "Skyr, granola".
    public var name: String
    /// Up to four of its foods' markers, the biggest, in the order eaten.
    public var markers: [String]
    public var nutrients: Nutrients
    public var kind: Kind
    /// The log's entries, earliest first; none for a dish on the plan.
    public var entries: [FoodEntry]

    /// Only what's in the log moves: a dish on the plan moves in the meal plan.
    public var canMove: Bool { kind != .planned }
    /// Still to come: drawn lighter than what's eaten.
    public var isAhead: Bool { kind != .eaten }
}

/// One day's column.
public struct WeekDay: Hashable, Sendable, Identifiable {
    public enum Timing: Hashable, Sendable { case past, today, ahead }

    /// How the day stands against its target: what's left of it today, and under or over it on any
    /// other day (what was eaten, or what's planned).
    public enum Standing: Hashable, Sendable {
        case left(Double)
        case under(Double)
        case over(Double)
    }

    public var day: Day
    public var timing: Timing
    /// In time order.
    public var meals: [WeekMeal]
    public var target: DailyTargets?
    /// What's been eaten (the doses taken counted, as Today counts them).
    public var eaten: Nutrients
    /// What's logged for later and planned.
    public var ahead: Nutrients

    public var id: Day { day }
    public var total: Nutrients { eaten + ahead }
    public var hasFood: Bool { !meals.isEmpty }
    /// How many of the meals, from the top, are eaten: where today's now line goes.
    public var eatenMeals: Int { meals.prefix { $0.kind == .eaten }.count }

    public var standing: Standing? {
        guard let kcal = target?.kcal, kcal > 0 else { return nil }
        if timing == .today {
            let left = kcal - eaten.kcal
            return left >= 0 ? .left(left) : .over(-left)
        }
        guard hasFood else { return nil }
        let balance = total.kcal - kcal
        return balance > 0 ? .over(balance) : .under(-balance)
    }
}

/// The week's average day, over the days that say something: those eaten, and those planned.
public struct WeekAverage: Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    /// The same days' own targets, averaged.
    public var kcalTarget: Double?
    public var proteinTarget: Double?
    /// Days over and done with food logged.
    public var logged: Int
    /// Days with food still to come: today once something's ahead, and the days after it.
    public var planned: Int
}

/// The desk for one week.
public struct WeekBoard: Hashable, Sendable {
    /// Monday.
    public var start: Day
    public var days: [WeekDay]
    public var maintenance: Double?
    /// The target line across the week: the calorie target most of its days have.
    public var target: Double?
    public var average: WeekAverage?
    /// The calories at the foot of the columns: room for maintenance and the biggest day.
    public var scaleTop: Double

    public var end: Day { start.adding(days: 6) }
    public var isEmpty: Bool { days.allSatisfy { !$0.hasFood } }
    public func day(_ day: Day) -> WeekDay? { days.first { $0.day == day } }
}

/// What the desk is drawn from: the week's log, the plan's dishes, each day's targets.
public struct WeekLog: Sendable {
    /// The log's entries for the week, eaten and for later, in any order.
    public var entries: [FoodEntry]
    public var planned: [WeekPlanned]
    public var doses: [SupplementLog]
    public var targets: [Day: DailyTargets]
    public var maintenance: Double?
    public var saved: [SavedMeal]

    public init(
        entries: [FoodEntry], planned: [WeekPlanned] = [], doses: [SupplementLog] = [], targets: [Day: DailyTargets] = [:],
        maintenance: Double? = nil, saved: [SavedMeal] = []
    ) {
        self.entries = entries
        self.planned = planned
        self.doses = doses
        self.targets = targets
        self.maintenance = maintenance
        self.saved = saved
    }
}

/// A meal held over another day: both days and the week as they'd be, and what changes, in words.
public struct WeekMove: Hashable, Sendable {
    public var meal: WeekMeal
    public var to: Day
    public var before: WeekBoard
    public var after: WeekBoard
    /// "Saturday goes from 738 under to 33 over. Thursday comes down to 1,298, 902 under. The week
    /// still averages 2,172."
    public var changes: String

    public var from: Day { meal.day }
    /// Whether a meal in the board after holds what's moving (it may have joined a meal there).
    public func holdsMoved(_ other: WeekMeal) -> Bool {
        let ids = Set(meal.entries.map(\.id))
        return other.entries.contains { ids.contains($0.id) }
    }
}

/// The body weight beside the week: the trend over the four weeks to its end.
public struct WeekWeight: Hashable, Sendable {
    public var points: [WeightTrend.Point]
    /// The trend on the last day, kg.
    public var trend: Double
    /// Kg a week, as the Plan tab says it.
    public var weekly: Double?
}

public enum WeekDesk {
    /// The seven days of the week `day` is in, Monday first.
    public static func days(of day: Day) -> [Day] { (0..<7).map { day.startOfWeek.adding(days: $0) } }

    public static func board(_ log: WeekLog, week: Day, now: Date, calendar: Calendar = .current) -> WeekBoard {
        let today = Day(now, calendar: calendar)
        let days = days(of: week)
        let byDay = Dictionary(grouping: log.entries, by: \.day)
        let plannedByDay = Dictionary(grouping: log.planned.filter { $0.time > now }, by: { Day($0.time, calendar: calendar) })
        let dosesByDay = Dictionary(grouping: log.doses, by: \.day)
        let columns = days.map { day in
            let entries = (byDay[day] ?? []).sorted { $0.date < $1.date }
            let planned = plannedByDay[day] ?? []
            let split = FoodLog(entries, now: now)
            let logged = Timeline.moments(entries).map { meal(of: $0, on: day, saved: log.saved, now: now) }
            let dishes = planned.map { dish in
                WeekMeal(
                    id: "plan-\(dish.id)", day: day, start: dish.time, name: dish.name, markers: markers(dish.foods.map { (name: $0, kcal: 0.0) }),
                    nutrients: dish.nutrients, kind: .planned, entries: [])
            }
            return WeekDay(
                day: day, timing: day < today ? .past : day == today ? .today : .ahead,
                meals: (logged + dishes).sorted { $0.start < $1.start }, target: log.targets[day],
                eaten: Intake.total(split.eaten, doses: dosesByDay[day] ?? []),
                ahead: Intake.total(split.upcoming) + Nutrients.sum(planned.map(\.nutrients)))
        }
        let target = commonTarget(columns)
        let biggest = columns.map(\.total.kcal).max() ?? 0
        return WeekBoard(
            start: days[0], days: columns, maintenance: log.maintenance, target: target, average: average(columns),
            scaleTop: scaleTop(maintenance: log.maintenance, target: target, biggest: biggest))
    }

    /// The board with `meal` on `day` instead, at the same times of day, as the Log tab's move puts
    /// it there. Nil for a dish on the plan, or the day it's on already.
    public static func move(
        _ meal: WeekMeal, to day: Day, in log: WeekLog, week: Day, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> WeekMove? {
        guard meal.canMove, day != meal.day else { return nil }
        let ids = Set(meal.entries.map(\.id))
        let dates = Placing.dates(for: meal.entries, .sameTimes(on: day), calendar: calendar)
        let moved = zip(meal.entries, dates).map { entry, date in
            var entry = entry
            entry.date = date
            entry.day = Day(date, calendar: calendar)
            return entry
        }
        var after = log
        after.entries = log.entries.filter { !ids.contains($0.id) } + moved
        let before = board(log, week: week, now: now, calendar: calendar)
        let then = board(after, week: week, now: now, calendar: calendar)
        let today = Day(now, calendar: calendar)
        return WeekMove(
            meal: meal, to: day, before: before, after: then,
            changes: changes(from: meal.day, to: day, before: before, after: then, today: today, locale: locale))
    }

    /// A saved meal's name for exactly these foods, else the two with the most calories in the
    /// order eaten: "Skyr, granola".
    public static func name(of entries: [FoodEntry], saved: [SavedMeal]) -> String {
        if let meal = SavedMeals.meal(for: entries, in: saved) { return meal.name }
        let ordered = entries.sorted { $0.date < $1.date }
        let biggest = Set(ordered.indices.sorted { ordered[$0].nutrients.kcal > ordered[$1].nutrients.kcal }.prefix(2))
        let titles = ordered.indices.filter(biggest.contains).map { FoodLabel.title(ordered[$0].name) }
        guard let first = titles.first else { return "" }
        guard titles.count > 1 else { return first }
        return "\(first), \(lowered(titles[1]))"
    }

    /// The markers of up to `limit` foods, the biggest by calories, in the order given; a marker
    /// once, and a plate only when nothing else is known.
    public static func markers(_ foods: [(name: String, kcal: Double)], limit: Int = 4) -> [String] {
        var seen = Set<String>()
        let found = foods.enumerated().compactMap { index, food -> (index: Int, marker: String, kcal: Double)? in
            let marker = FoodMarker.of(food.name)
            guard marker != FoodMarker.unknown, seen.insert(marker).inserted else { return nil }
            return (index, marker, food.kcal)
        }
        guard !found.isEmpty else { return foods.isEmpty ? [] : [FoodMarker.unknown] }
        let kept = Set(found.sorted { $0.kcal > $1.kcal }.prefix(limit).map(\.index))
        return found.filter { kept.contains($0.index) }.map(\.marker)
    }

    /// The four weeks of the trend to `end` (the week's last day, or today when that's sooner).
    public static func weight(_ trend: WeightTrend, through end: Day, weeks: Int = 4) -> WeekWeight? {
        let points = trend.points.filter { $0.day > end.adding(days: -7 * weeks) && $0.day <= end }
        guard let last = points.last else { return nil }
        return WeekWeight(points: points, trend: last.trend, weekly: trend.weeklyChange(ending: last.day))
    }

    // MARK: - Pieces

    static func meal(of moment: Moment, on day: Day, saved: [SavedMeal], now: Date) -> WeekMeal {
        let entries = moment.entries
        let kind: WeekMeal.Kind = moment.start <= now ? .eaten : .later
        return WeekMeal(
            id: "meal-\(moment.id)", day: day, start: moment.start, name: name(of: entries, saved: saved),
            markers: markers(entries.map { ($0.name, $0.nutrients.kcal) }), nutrients: moment.nutrients, kind: kind, entries: entries)
    }

    /// The days that say something about the week: those eaten (over and done) and those planned.
    /// Today counts once something is planned for the rest of it; until then it's half a day.
    static func average(_ days: [WeekDay]) -> WeekAverage? {
        let counted = days.filter { day in
            switch day.timing {
            case .past: day.eaten.kcal > 0
            case .today, .ahead: day.ahead.kcal > 0
            }
        }
        guard !counted.isEmpty else { return nil }
        let n = Double(counted.count)
        let kcalTargets = counted.compactMap(\.target?.kcal)
        let proteinTargets = counted.compactMap(\.target?.protein)
        return WeekAverage(
            kcal: counted.map(\.total.kcal).reduce(0, +) / n, protein: counted.map(\.total.protein).reduce(0, +) / n,
            kcalTarget: kcalTargets.isEmpty ? nil : kcalTargets.reduce(0, +) / Double(kcalTargets.count),
            proteinTarget: proteinTargets.isEmpty ? nil : proteinTargets.reduce(0, +) / Double(proteinTargets.count),
            logged: counted.count(where: { $0.timing == .past }), planned: counted.count(where: { $0.timing != .past }))
    }

    /// The calorie target most of the week's days share (the later one of a tie), for the line
    /// across the columns.
    static func commonTarget(_ days: [WeekDay]) -> Double? {
        let targets = days.compactMap { $0.target?.kcal.map { $0.rounded() } }.filter { $0 > 0 }
        let counts = Dictionary(targets.map { ($0, 1) }, uniquingKeysWith: +)
        return targets.reversed().max { counts[$0, default: 0] < counts[$1, default: 0] }
    }

    /// A little past the furthest of maintenance, the target and the biggest day, to the next 50:
    /// the lines and every block fit, with the maintenance line clear of the foot. 2,500 with none.
    static func scaleTop(maintenance: Double?, target: Double?, biggest: Double) -> Double {
        let furthest = max(maintenance ?? 0, target ?? 0, biggest)
        guard furthest > 0 else { return 2500 }
        return (furthest * 1.03 / 50).rounded(.up) * 50
    }

    /// "Big Mac" stays as it is after a comma; "Granola" is "granola".
    private static func lowered(_ title: String) -> String {
        let letters = Array(title)
        guard letters.count > 1, letters[1].isLowercase else { return title }
        return title.prefix(1).lowercased() + title.dropFirst()
    }

    // MARK: - What changes

    static func changes(from: Day, to: Day, before: WeekBoard, after: WeekBoard, today: Day, locale: Locale) -> String {
        guard let fromBefore = before.day(from), let fromAfter = after.day(from), let toBefore = before.day(to), let toAfter = after.day(to)
        else { return "" }
        func number(_ value: Double) -> String { Int(value.rounded()).formatted(.number.locale(locale)) }
        func named(_ day: Day) -> String {
            switch today.days(until: day) {
            case 0: "Today"
            case 1: "Tomorrow"
            case -1: "Yesterday"
            default: day.weekday.name
            }
        }
        func against(_ day: WeekDay) -> (over: Bool, by: Double)? {
            guard let kcal = day.target?.kcal, kcal > 0 else { return nil }
            let balance = day.total.kcal - kcal
            return (balance > 0, abs(balance))
        }
        func word(_ side: (over: Bool, by: Double)) -> String { "\(number(side.by)) \(side.over ? "over" : "under")" }

        // The day it lands on.
        let gaining: String
        if let was = against(toBefore), let now = against(toAfter) {
            gaining =
                (!was.over && !now.over) || !toBefore.hasFood
                ? "comes up to \(number(toAfter.total.kcal)), \(word(now))" : "goes from \(word(was)) to \(word(now))"
        } else {
            gaining =
                toBefore.hasFood
                ? "comes up from \(number(toBefore.total.kcal)) to \(number(toAfter.total.kcal))" : "comes up to \(number(toAfter.total.kcal))"
        }
        // The day it leaves.
        let losing: String
        if !fromAfter.hasFood {
            losing = fromAfter.timing == .past ? "has nothing logged" : "has nothing planned"
        } else if let was = against(fromBefore), let now = against(fromAfter) {
            losing =
                was.over ? "drops from \(word(was)) to \(word(now))" : "comes down to \(number(fromAfter.total.kcal)), \(word(now))"
        } else {
            losing = "comes down from \(number(fromBefore.total.kcal)) to \(number(fromAfter.total.kcal))"
        }
        var sentences = ["\(named(to)) \(gaining).", "\(named(from)) \(losing)."]
        if let then = before.average?.kcal, let now = after.average?.kcal {
            sentences.append(
                abs(then - now) < 0.5 ? "The week still averages \(number(now))." : "The week averages \(number(now)) instead of \(number(then)).")
        }
        return sentences.joined(separator: " ")
    }
}
