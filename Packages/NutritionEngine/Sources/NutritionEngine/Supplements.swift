import Foundation
import SystemCore

/// When in the day a dose is taken. Each has a time of its own, for reminders and for doses marked
/// on a day being caught up.
public enum DoseTime: String, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case morning, midday, afternoon, evening, bedtime

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .morning: "Morning"
        case .midday: "Midday"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .bedtime: "Bedtime"
        }
    }

    public var symbol: String {
        switch self {
        case .morning: "sunrise"
        case .midday: "sun.max"
        case .afternoon: "sun.min"
        case .evening: "sunset"
        case .bedtime: "moon.zzz"
        }
    }

    /// Minutes after midnight, until the person sets their own.
    public var defaultMinutes: Int {
        switch self {
        case .morning: 8 * 60
        case .midday: 12 * 60 + 30
        case .afternoon: 15 * 60
        case .evening: 19 * 60
        case .bedtime: 22 * 60 + 30
        }
    }

    /// The time of day it's nearest to now: what "take it now" means for an extra dose.
    public static func nearest(minutes: Int, times: [DoseTime: Int] = [:]) -> DoseTime {
        allCases.min { abs((times[$0] ?? $0.defaultMinutes) - minutes) < abs((times[$1] ?? $1.defaultMinutes) - minutes) } ?? .morning
    }

    private var order: Int { DoseTime.allCases.firstIndex(of: self) ?? 0 }
    public static func < (a: DoseTime, b: DoseTime) -> Bool { a.order < b.order }
}

extension DoseTime: CodingKeyRepresentable {}

/// The days a dose is due.
public enum DoseDays: Hashable, Codable, Sendable {
    case everyDay
    case weekdays([Weekday])
    case everyOtherDay(from: Day)
    /// Training days: the ones the shared schedule plans, and any day with a session logged.
    case trainingDays
    /// Rest days: the others.
    case restDays

    public func isDue(on day: Day, training: Bool) -> Bool {
        switch self {
        case .everyDay: true
        case .weekdays(let days): days.contains(day.weekday)
        case .everyOtherDay(let start): start.days(until: day) % 2 == 0
        case .trainingDays: training
        case .restDays: !training
        }
    }

    public var label: String {
        switch self {
        case .everyDay: "Every day"
        case .weekdays(let days):
            days.count == 7 ? "Every day" : days.sorted().map(\.short).joined(separator: ", ")
        case .everyOtherDay: "Every other day"
        case .trainingDays: "Training days"
        case .restDays: "Rest days"
        }
    }
}

/// One time a supplement is taken: when, how much, and on which days.
public struct Dose: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var time: DoseTime
    /// In the label's unit: 2 softgels, 1 scoop.
    public var count: Double
    public var days: DoseDays

    public init(id: UUID = UUID(), time: DoseTime = .morning, count: Double = 1, days: DoseDays = .everyDay) {
        self.id = id
        self.time = time
        self.count = count
        self.days = days
    }
}

/// A supplement in the person's stack: its label, and when and how much they take of it.
public struct Supplement: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var facts: SupplementFacts
    public var doses: [Dose]
    /// Kept with its history but not being taken: no doses are due.
    public var paused: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), facts: SupplementFacts, doses: [Dose] = [], paused: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.facts = facts
        self.doses = doses.isEmpty ? [Dose(count: facts.servingCount)] : doses
        self.paused = paused
        self.updatedAt = updatedAt
    }

    public var name: String { facts.name }

    /// What `count` units hold, by nutrient key: the label's serving scaled to the dose.
    public func amounts(count: Double) -> [String: Double] {
        let factor = count / facts.servingCount
        return facts.amounts.mapValues { $0 * factor }
    }

    public func nutrients(count: Double) -> Nutrients? { facts.nutrients?.scaled(count / facts.servingCount) }

    /// "2 softgels · morning", "1 tablet · morning and evening", "1 scoop · afternoon, training days".
    public var scheduleLabel: String {
        guard !paused else { return "Paused" }
        var groups: [(count: Double, days: DoseDays, times: [DoseTime])] = []
        for dose in doses.sorted(by: { $0.time < $1.time }) {
            if let i = groups.firstIndex(where: { $0.count == dose.count && $0.days == dose.days }) {
                groups[i].times.append(dose.time)
            } else {
                groups.append((dose.count, dose.days, [dose.time]))
            }
        }
        return groups.map { group in
            let times = group.times.map { $0.label.lowercased() }
            let when = times.count > 1 ? times.dropLast().joined(separator: ", ") + " and " + times.last! : times[0]
            return "\(facts.amountLabel(group.count)) · \(when)\(group.days == .everyDay ? "" : ", \(group.days.label.lowercased())")"
        }.joined(separator: "; ")
    }
}

/// A dose taken, or deliberately skipped. A dose not marked either way is unknown, never a miss,
/// and counts for nothing.
public struct SupplementLog: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var supplementID: UUID
    /// The planned dose it was; nil for an extra one.
    public var doseID: UUID?
    public var day: Day
    public var date: Date
    public var name: String
    public var count: Double
    public var unit: String
    public var taken: Bool
    /// What it held, by nutrient key, as logged: kept if the label is edited later.
    public var amounts: [String: Double]
    public var nutrients: Nutrients?
    public var updatedAt: Date

    public init(id: UUID = UUID(), supplement: Supplement, doseID: UUID?, date: Date, day: Day? = nil, count: Double, taken: Bool = true,
                updatedAt: Date = Date()) {
        self.id = id
        supplementID = supplement.id
        self.doseID = doseID
        self.day = day ?? Day(date)
        self.date = date
        name = supplement.name
        self.count = count
        unit = supplement.facts.unit
        self.taken = taken
        amounts = taken ? supplement.amounts(count: count) : [:]
        nutrients = taken ? supplement.nutrients(count: count) : nil
        self.updatedAt = updatedAt
    }

    /// "2 softgels".
    public var amountLabel: String { SupplementServing.label(count, unit) }
}

/// A planned dose on a day, and whether it's been marked.
public struct DueDose: Hashable, Sendable, Identifiable {
    public var supplement: Supplement
    public var dose: Dose
    public var log: SupplementLog?

    public var id: String { "\(supplement.id.uuidString)-\(dose.id.uuidString)" }
    public var taken: Bool { log?.taken == true }
    public var skipped: Bool { log?.taken == false }
    public var open: Bool { log == nil }
}

public enum SupplementPlan {
    /// The doses due on a day, by time of day then name, each with its log when marked.
    public static func due(on day: Day, stack: [Supplement], logs: [SupplementLog], training: Bool) -> [DueDose] {
        let marked = Dictionary(logs.filter { $0.day == day && $0.doseID != nil }.map { ("\($0.supplementID)-\($0.doseID!)", $0) },
                                uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        var due: [DueDose] = []
        for supplement in stack where !supplement.paused {
            for dose in supplement.doses where dose.days.isDue(on: day, training: training) {
                due.append(DueDose(supplement: supplement, dose: dose, log: marked["\(supplement.id)-\(dose.id)"]))
            }
        }
        // A dose marked and then taken off the plan still shows on the day it was marked.
        for log in marked.values where !due.contains(where: { $0.log?.id == log.id }) {
            guard let supplement = stack.first(where: { $0.id == log.supplementID }) else { continue }
            let time = DoseTime.nearest(minutes: minutes(log.date))
            due.append(DueDose(supplement: supplement, dose: Dose(id: log.doseID!, time: time, count: log.count, days: .everyDay), log: log))
        }
        return due.sorted { a, b in a.dose.time != b.dose.time ? a.dose.time < b.dose.time : a.supplement.name < b.supplement.name }
    }

    /// Doses taken outside the plan on a day.
    public static func extras(on day: Day, logs: [SupplementLog]) -> [SupplementLog] {
        logs.filter { $0.day == day && $0.doseID == nil && $0.taken }.sorted { $0.date < $1.date }
    }

    /// Whether a day is a training day: planned in the shared schedule, or a session was logged.
    public static func isTrainingDay(_ day: Day, profile: SharedProfile, lift: AppSummary?) -> Bool {
        profile.schedule.trainingDays.contains(day.weekday)
            || (lift?.sessions.contains { $0.day == day && $0.kind == .strength } ?? false)
    }

    /// What taken doses held, added up by nutrient key.
    public static func amounts(_ logs: [SupplementLog]) -> [String: Double] {
        var total: [String: Double] = [:]
        for log in logs where log.taken {
            for (key, value) in log.amounts { total[key, default: 0] += value }
        }
        return total
    }

    static func minutes(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
