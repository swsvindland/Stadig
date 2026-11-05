import Foundation
import SystemCore

/// What a week asked for, kept so that changing a course or a class later doesn't rescore it.
public struct WeekTarget: Hashable, Codable, Sendable {
    /// Blocks planned across the week.
    public var total: Int
    /// Blocks each course asked for, a lagging course's extra one included.
    public var courses: [String: Int]
    /// The days of the week that counted. A pause entered afterwards takes its share off.
    public var days: Int

    public init(total: Int, counts: [Domain: Int], days: Int) {
        self.total = total
        courses = Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) })
        self.days = days
    }

    public var counts: [Domain: Int] {
        Dictionary(uniqueKeysWithValues: courses.compactMap { key, value in Domain(rawValue: key).map { ($0, value) } })
    }
}

/// How the person's study week is set up: how many blocks each course gets, and which parts of
/// which days are open. A record of its own, away from `MindSettings`, because a build from before
/// blocks has to keep reading the settings as they were: a new version of that record would hide it
/// and send the build back to onboarding. This one it simply never asks for.
///
/// Courses and parts are keyed by plain strings, so a course from a newer build on another device
/// keeps its blocks here rather than failing the whole record.
public struct WeekSettings: Hashable, Codable, Sendable, Identifiable {
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000317E")!
    /// A week set up from older settings starts at no more blocks than this: about four hours.
    public static let seedCap = 10
    /// Blocks a course can ask for in a week. One a day, because a block a day is what spacing wants
    /// and a second is better spent on another course.
    public static let blockRange = 0...7
    /// Weeks of `targets` kept: Discipline looks back four, and a little over.
    static let targetWeeks = 6

    public var id: UUID
    /// Blocks a week by course. A course left out has none: reviews only, if it's active.
    public var blocks: [String: Int]
    /// Parts of the week opened or closed by hand. Only what's been changed, so that a class added
    /// in Stadig Lift still closes its evening.
    public var parts: [String: Bool]
    /// A course's chosen part of the day, over the usual fit.
    public var pins: [String: String]
    /// The first day blocks counted. Days before it keep being judged the way they were planned.
    public var since: Day
    /// What each week asked for, by its Monday. Past weeks are never rewritten, so changing a course
    /// or a class doesn't rescore them.
    public var targets: [String: WeekTarget]
    public var updatedAt: Date

    public init(
        blocks: [Domain: Int] = [:], parts: [String: Bool] = [:], pins: [Domain: DayPart] = [:], since: Day,
        targets: [String: WeekTarget] = [:], updatedAt: Date = Date()
    ) {
        id = Self.singletonID
        self.blocks = Dictionary(uniqueKeysWithValues: blocks.map { ($0.key.rawValue, Self.clamped($0.value)) })
        self.parts = parts
        self.pins = Dictionary(uniqueKeysWithValues: pins.map { ($0.key.rawValue, $0.value.rawValue) })
        self.since = since
        self.targets = targets
        self.updatedAt = updatedAt
    }

    private static func clamped(_ count: Int) -> Int { min(max(count, blockRange.lowerBound), blockRange.upperBound) }

    // MARK: Blocks

    public func blocks(_ domain: Domain) -> Int { Self.clamped(blocks[domain.rawValue] ?? 0) }

    public mutating func setBlocks(_ count: Int, for domain: Domain) { blocks[domain.rawValue] = Self.clamped(count) }

    /// Blocks a week across some courses.
    public func total(_ domains: [Domain]) -> Int { domains.map(blocks).reduce(0, +) }

    /// The value that stands for a course being off, on the one control that sets a course's amount:
    /// off, reviews only, or a number of blocks.
    public static let courseOff = -1

    /// A course's amount: `courseOff`, 0 for reviews only, or its blocks a week.
    public func amount(_ domain: Domain, settings: MindSettings) -> Int { settings.has(domain) ? blocks(domain) : Self.courseOff }

    /// A course's amount as words: "Off", "Reviews only", "4 a week".
    public static func amountLabel(_ amount: Int) -> String {
        switch amount {
        case ..<0: "Off"
        case 0: "Reviews only"
        default: "\(amount) a week"
        }
    }

    /// Sets a course's amount, and the tiers that older builds read with it. Refused, returning
    /// false, when it would leave no course with blocks: there'd be no week to plan.
    @discardableResult
    public mutating func setAmount(_ amount: Int, for domain: Domain, settings: inout MindSettings) -> Bool {
        var week = self
        var next = settings
        if amount < 0 {
            next.courses[domain] = nil
        } else {
            next.courses[domain] = next.courses[domain] ?? .maintenance
            week.setBlocks(amount, for: domain)
        }
        guard week.total(next.domains) > 0 else { return false }
        next.courses = week.modes(next.domains)
        self = week
        settings = next
        return true
    }

    // MARK: Parts of the week

    static func key(_ weekday: Weekday, _ part: DayPart) -> String { "\(weekday.rawValue).\(part.rawValue)" }

    /// True or false when this part was opened or closed by hand; nil when it's left to the plan.
    public func override(_ weekday: Weekday, _ part: DayPart) -> Bool? { parts[Self.key(weekday, part)] }

    public mutating func setOverride(_ open: Bool?, _ weekday: Weekday, _ part: DayPart) { parts[Self.key(weekday, part)] = open }

    // MARK: Pins

    public func pin(_ domain: Domain) -> DayPart? { pins[domain.rawValue].flatMap(DayPart.init(rawValue:)) }

    public mutating func setPin(_ part: DayPart?, for domain: Domain) { pins[domain.rawValue] = part?.rawValue }

    // MARK: Weekly targets

    public func target(_ monday: Day) -> WeekTarget? { targets[monday.iso] }

    /// Notes what a week asks for, and forgets weeks too old for Discipline to look at.
    public mutating func record(_ target: WeekTarget, for monday: Day) {
        targets[monday.iso] = target
        let oldest = monday.adding(weeks: -Self.targetWeeks)
        targets = targets.filter { Day(iso: $0.key).map { $0 >= oldest } ?? false }
    }

    // MARK: Starting points

    /// Someone who has just chosen their courses. Languages most: they want near-daily exposure.
    public static func fresh(_ domains: [Domain], since: Day, now: Date) -> WeekSettings {
        var blocks: [Domain: Int] = [:]
        for domain in domains {
            switch domain {
            case .japanese, .spanish: blocks[domain] = 4
            case .reading: blocks[domain] = 3
            case .maths: blocks[domain] = 2
            case .writing: blocks[domain] = 1
            }
        }
        return WeekSettings(blocks: trimmed(blocks), since: since, updatedAt: now)
    }

    /// From settings saved before blocks: a Main course four a week, a Secondary course two, a
    /// Maintenance course reviews only, trimmed to the cap, so that four Main courses don't become
    /// 16 blocks overnight.
    public static func seeded(from settings: MindSettings, since: Day, now: Date) -> WeekSettings {
        var blocks: [Domain: Int] = [:]
        for (domain, mode) in settings.courses {
            switch mode {
            case .focus: blocks[domain] = 4
            case .secondary: blocks[domain] = 2
            case .maintenance: blocks[domain] = 0
            }
        }
        return WeekSettings(blocks: trimmed(blocks), since: since, updatedAt: now)
    }

    /// Takes blocks from the biggest course until the week fits the cap, from non-language courses
    /// first: a language loses most from thinning out. Every course that had blocks keeps one.
    static func trimmed(_ blocks: [Domain: Int]) -> [Domain: Int] {
        var out = blocks
        while out.values.reduce(0, +) > seedCap {
            let spare = out.keys.filter { out[$0, default: 0] > 1 }.sorted()
            let others = spare.filter { !$0.isLanguage }
            let pool = others.isEmpty ? spare : others
            guard let course = pool.max(by: { out[$0, default: 0] < out[$1, default: 0] }) else { break }
            out[course, default: 0] -= 1
        }
        return out
    }

    /// The tier each course reads as, for `MindSettings.courses`, which still says which courses are
    /// on and which an older build reads. The biggest course stays Main, or an older build would
    /// have nothing to put in its split.
    public func modes(_ domains: [Domain]) -> [Domain: CourseMode] {
        var out: [Domain: CourseMode] = [:]
        for domain in domains {
            switch blocks(domain) {
            case 3...: out[domain] = .focus
            case 1...: out[domain] = .secondary
            default: out[domain] = .maintenance
            }
        }
        if let top = domains.sorted().max(by: { blocks($0) < blocks($1) }), !out.values.contains(.focus) { out[top] = .focus }
        return out
    }

    // MARK: Coding

    enum CodingKeys: String, CodingKey { case id, blocks, parts, pins, since, targets, updatedAt }

    /// Fills anything missing with its default, as `MindSettings` does, so a field added later never
    /// fails a record saved before it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? Self.singletonID
        blocks = try c.decodeIfPresent([String: Int].self, forKey: .blocks) ?? [:]
        parts = try c.decodeIfPresent([String: Bool].self, forKey: .parts) ?? [:]
        pins = try c.decodeIfPresent([String: String].self, forKey: .pins) ?? [:]
        since = try c.decode(Day.self, forKey: .since)
        targets = try c.decodeIfPresent([String: WeekTarget].self, forKey: .targets) ?? [:]
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}
