import Foundation

/// Something a day holds that isn't up for planning: a shift, a lecture, the drive in, sleep. Times
/// are minutes from the midnight of the day it's on, by the clock, so daylight saving can't move it.
/// An end past 1440 runs into the next day, which is how a night shift is written.
public struct DaySpan: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// `home` is work done at home: as busy as any, with no commute to it. Older builds read it as
        /// `work`, by the rule below, so it needed no schema bump.
        case work, school, commute, sleep, home

        /// A kind from a newer build counts as busy, the safe way round.
        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .work
        }
    }

    public var kind: Kind
    public var label: String
    public var start: Int
    public var end: Int

    public init(_ kind: Kind, _ label: String, from start: Int, to end: Int) {
        self.kind = kind
        self.label = label
        self.start = start
        self.end = end
    }

    public var minutes: Int { max(0, end - start) }
}

/// A person's work or school. A cycle of weeks from an anchor Monday, so that a plain week is a cycle
/// of one, and alternate Fridays or rotating shifts are a cycle of two or more.
public struct WorkPattern: Hashable, Codable, Sendable {
    /// A Monday in the first week of the cycle.
    public var anchor: Day
    /// Each week of the cycle: seven days, Monday first, each with its spans.
    public var weeks: [[[DaySpan]]]
    /// The last day it holds: the end of a term. Nil for no end.
    public var endsOn: Day?
    /// Days set one by one, by ISO date: a roster, or a one-off change.
    public var overrides: [String: [DaySpan]]
    /// A roster has no repeating weeks: a day with no entry isn't known, rather than free.
    public var isRoster: Bool

    public init(anchor: Day, weeks: [[[DaySpan]]], endsOn: Day? = nil, overrides: [String: [DaySpan]] = [:], isRoster: Bool = false) {
        self.anchor = anchor.startOfWeek
        self.weeks = weeks
        self.endsOn = endsOn
        self.overrides = overrides
        self.isRoster = isRoster
    }

    /// The spans on a day. Nil when it isn't known: past a term's end, or a roster day with no entry.
    /// Unknown is never free, or something flexible would land in a shift nobody wrote down.
    public func spans(on day: Day) -> [DaySpan]? {
        if let set = overrides[day.iso] { return set }
        if isRoster { return nil }
        if let endsOn, day > endsOn { return nil }
        guard !weeks.isEmpty else { return nil }
        let week = anchor.days(until: day.startOfWeek) / 7
        let index = ((week % weeks.count) + weeks.count) % weeks.count
        let days = weeks[index]
        let offset = day.weekday.rawValue - 1
        return days.indices.contains(offset) ? days[offset] : []
    }
}

/// Where a class or the gym sits on one weekday, every week. Stadig Lift keeps what's on and for how
/// long; this is only when, which is the hub's to say.
public struct ClassPlacement: Hashable, Codable, Sendable {
    /// A commitment's title.
    public var title: String
    public var weekday: Weekday
    public var part: DayPart

    public init(title: String, weekday: Weekday, part: DayPart) {
        self.title = title
        self.weekday = weekday
        self.part = part
    }
}

/// The repeating shape of someone's weeks, set in the hub and read by every app.
public struct Rhythm: Hashable, Codable, Sendable {
    public static let schemaVersion = 1
    public static let standardWake = 6 * 60
    public static let standardBed = 22 * 60 + 30
    public static let standardClearEvenings = 2

    public var pattern: WorkPattern?
    /// Minutes from midnight. A bedtime past 1440 is after midnight. A day whose spans include sleep
    /// uses those instead, which is how a shift pattern keeps its own hours.
    public var wake: Int
    public var bed: Int
    /// Evenings a week kept clear of anything flexible.
    public var clearEvenings: Int
    /// Classes and the gym moved for good. Optional in the file, and still schema 1: a bump would stop
    /// older apps reading the rhythm at all, and they lose nothing but the move by skipping it.
    public var placements: [ClassPlacement]
    /// The hour a study day starts, so that every app turns over together.
    public var dayStart: Int
    public var updated: Date

    public init(
        pattern: WorkPattern? = nil, wake: Int = standardWake, bed: Int = standardBed, clearEvenings: Int = standardClearEvenings, dayStart: Int = 4,
        placements: [ClassPlacement] = [], updated: Date = Date()
    ) {
        self.pattern = pattern
        self.wake = wake
        self.bed = bed
        self.clearEvenings = clearEvenings
        self.dayStart = dayStart
        self.placements = placements
        self.updated = updated
    }

    enum CodingKeys: String, CodingKey { case pattern, wake, bed, clearEvenings, dayStart, placements, updated }

    /// Fills anything missing with its default, so a field added later never fails a file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try c.decodeIfPresent(WorkPattern.self, forKey: .pattern)
        wake = try c.decodeIfPresent(Int.self, forKey: .wake) ?? Self.standardWake
        bed = try c.decodeIfPresent(Int.self, forKey: .bed) ?? Self.standardBed
        clearEvenings = try c.decodeIfPresent(Int.self, forKey: .clearEvenings) ?? Self.standardClearEvenings
        dayStart = try c.decodeIfPresent(Int.self, forKey: .dayStart) ?? 4
        placements = try c.decodeIfPresent([ClassPlacement].self, forKey: .placements) ?? []
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? .distantPast
    }

    /// Where a commitment was moved to on a weekday, if it was.
    public func placedPart(of title: String, on weekday: Weekday) -> DayPart? {
        placements.first { $0.title == title && $0.weekday == weekday }?.part
    }
}

/// Something that changed: "I'm out tonight", or a lighter week. Set in the hub, read by every app,
/// merged a change at a time, so that one device can't wipe out what another just said.
public struct DayChange: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1
    /// Plain strings rather than an enum: one a newer build wrote would otherwise fail the whole list,
    /// and a schema bump would leave the older apps reading nothing at all.
    public static let out = "out"
    public static let lighter = "lighter"
    public static let moved = "moved"
    /// Changes a week older than this no longer matter to anyone.
    public static let keptDays = 42

    public var id: UUID
    public var kind: String
    /// The day it's for: a lighter week's Monday.
    public var day: Day
    /// The parts it clears, by name. For a move, the one part it goes to.
    public var parts: [String]
    /// What a move moves: a commitment's title. Absent from other kinds and from older files.
    public var title: String?
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), kind: String, day: Day, parts: [String] = [], title: String? = nil, updatedAt: Date = Date(), deletedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.day = day
        self.parts = parts
        self.title = title
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Clears the evening and the night of a day. No reason needed. Say which part of the day it is
    /// and what's already gone clears too: otherwise tonight's blocks would move to a morning that's
    /// over, and be no more doable there, when they should move on to another day.
    public static func outTonight(on day: Day, at date: Date = Date(), during part: DayPart? = nil) -> DayChange {
        func closes(_ candidate: DayPart) -> Bool {
            if candidate >= .evening { return true }
            return part.map { candidate < $0 } ?? false
        }
        return DayChange(kind: out, day: day, parts: DayPart.allCases.filter(closes).map(\.rawValue), updatedAt: date)
    }

    public static func lighterWeek(of day: Day, at date: Date = Date()) -> DayChange {
        DayChange(kind: lighter, day: day.startOfWeek, updatedAt: date)
    }

    /// A class or the gym in another part, on this one day.
    public static func move(_ title: String, on day: Day, to part: DayPart, at date: Date = Date()) -> DayChange {
        DayChange(kind: moved, day: day, parts: [part.rawValue], title: title, updatedAt: date)
    }

    /// A session's minutes in a lighter week: two thirds, to the nearest five, and no less than half
    /// an hour, since a session shorter than that isn't worth the trip.
    public static func lighterMinutes(_ minutes: Int) -> Int { max(30, Int((Double(minutes) * 2 / 3 / 5).rounded()) * 5) }

    public var isDeleted: Bool { deletedAt != nil }

    /// The tombstone that replaces it when it's undone.
    public func deleted(at date: Date = Date()) -> DayChange {
        var tombstone = self
        tombstone.deletedAt = date
        tombstone.updatedAt = date
        return tombstone
    }

    /// Every copy merged: the newest edit of each change wins, a delete included, and on a tie a
    /// delete wins. As `LifeModePeriod.merge` does, in whole milliseconds.
    public static func merge(_ sources: [[DayChange]]) -> [DayChange] {
        func milliseconds(_ date: Date) -> Double { (date.timeIntervalSince1970 * 1000).rounded() }
        var merged: [UUID: DayChange] = [:]
        for change in sources.joined() {
            if let existing = merged[change.id] {
                let new = milliseconds(change.updatedAt)
                let old = milliseconds(existing.updatedAt)
                guard new > old || (new == old && change.isDeleted && !existing.isDeleted) else { continue }
            }
            merged[change.id] = change
        }
        return merged.values.sorted { ($0.day, $0.id.uuidString) < ($1.day, $1.id.uuidString) }
    }
}

extension Array where Element == DayChange {
    /// Without the tombstones.
    public var live: [DayChange] { filter { !$0.isDeleted } }

    /// Without what's too old to matter.
    public func kept(on day: Day) -> [DayChange] { filter { $0.day.days(until: day) <= DayChange.keptDays } }

    /// The parts cleared on a day.
    public func closedParts(on day: Day) -> Set<DayPart> {
        Set(live.filter { $0.kind == DayChange.out && $0.day == day }.flatMap(\.parts).compactMap(DayPart.init(rawValue:)))
    }

    /// Where a commitment was moved to on this one day, if it was. The latest move stands.
    public func movedPart(of title: String, on day: Day) -> DayPart? {
        live.filter { $0.kind == DayChange.moved && $0.day == day && $0.title == title }.max { $0.updatedAt < $1.updatedAt }?
            .parts.first.flatMap(DayPart.init(rawValue:))
    }

    public func isLighter(_ day: Day) -> Bool { live.contains { $0.kind == DayChange.lighter && $0.day == day.startOfWeek } }
}

/// When someone usually eats, and what they've eaten today, by part of the day. Published by Stadig
/// Macro, so a day's meals can sit where they usually do. Meals are the one thing the apps track that
/// has no plan behind it: these are habits, not targets.
public struct MealRhythm: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    /// A part for each usual meal, earliest first; a part can come twice.
    public var usual: [DayPart]
    public var day: Day
    /// A part for each meal eaten on `day`.
    public var eaten: [DayPart]
    public var updated: Date

    public init(usual: [DayPart], day: Day, eaten: [DayPart], updated: Date = Date()) {
        self.usual = usual
        self.day = day
        self.eaten = eaten
        self.updated = updated
    }
}

/// Works out what a day looks like from someone's rhythm. A pure function of published inputs, so any
/// app can answer for any date with no plan file to go out of date.
public enum DayShape {
    /// A part needs a free run this long to hold a block.
    public static let minimumRun = 45
    /// Which evenings stay clear, in order of preference: the end of the week first.
    static let clearOrder: [Weekday] = [.friday, .saturday, .sunday, .thursday, .wednesday, .tuesday, .monday]

    /// Everything on a day's timeline, 4 a.m. to 4 a.m.: its own spans, and what runs in from either
    /// side. Nil when the day's own spans aren't known.
    public static func busy(on day: Day, rhythm: Rhythm) -> [(start: Int, end: Int)]? {
        guard let pattern = rhythm.pattern, let own = pattern.spans(on: day) else { return nil }
        var out: [(start: Int, end: Int)] = []
        for (offset, source) in [(-1440, day.adding(days: -1)), (0, day), (1440, day.adding(days: 1))] {
            let spans = source == day ? own : pattern.spans(on: source) ?? []
            let awake = spans.filter { $0.kind != .sleep }
            out += awake.map { ($0.start + offset, $0.end + offset) }
            let sleep = spans.filter { $0.kind == .sleep }
            if sleep.isEmpty {
                out.append((rhythm.bed + offset, 1440 + rhythm.wake + offset))
            } else {
                out += sleep.map { ($0.start + offset, $0.end + offset) }
            }
        }
        return out
    }

    /// The longest free stretch in a part, in minutes.
    public static func longestRun(_ part: DayPart, busy: [(start: Int, end: Int)]) -> Int {
        var longest = 0
        var cursor = part.minutes.lowerBound
        for span in busy.sorted(by: { $0.start < $1.start }) where span.end > part.minutes.lowerBound && span.start < part.minutes.upperBound {
            longest = Swift.max(longest, Swift.min(span.start, part.minutes.upperBound) - cursor)
            cursor = Swift.max(cursor, span.end)
        }
        return Swift.max(longest, part.minutes.upperBound - cursor)
    }

    /// Where a part's longest free stretch starts, which is where anything flexible would go in it.
    public static func longestRunStart(_ part: DayPart, busy: [(start: Int, end: Int)]) -> Int {
        var longest = 0
        var start = part.minutes.lowerBound
        var cursor = part.minutes.lowerBound
        func offer(until end: Int) {
            guard end - cursor > longest else { return }
            longest = end - cursor
            start = cursor
        }
        for span in busy.sorted(by: { $0.start < $1.start }) where span.end > part.minutes.lowerBound && span.start < part.minutes.upperBound {
            offer(until: Swift.min(span.start, part.minutes.upperBound))
            cursor = Swift.max(cursor, span.end)
        }
        offer(until: part.minutes.upperBound)
        return start
    }

    /// The days of a week whose evenings are kept clear, chosen from the pattern alone, so that every
    /// app reaches the same answer whatever it knows. An evening taken up by work is no use to keep.
    public static func clearEvenings(weekOf monday: Day, rhythm: Rhythm) -> Set<Day> {
        var out: Set<Day> = []
        for weekday in clearOrder where out.count < rhythm.clearEvenings {
            let day = monday.adding(days: weekday.rawValue - 1)
            guard let busy = busy(on: day, rhythm: rhythm) else { continue }
            if longestRun(.evening, busy: busy) >= minimumRun || longestRun(.night, busy: busy) >= minimumRun { out.insert(day) }
        }
        return out
    }

    /// Minutes in a part with nothing on, whether or not they run together.
    public static func freeMinutes(_ part: DayPart, busy: [(start: Int, end: Int)]) -> Int {
        var free = 0
        var cursor = part.minutes.lowerBound
        for span in busy.sorted(by: { $0.start < $1.start }) where span.end > part.minutes.lowerBound && span.start < part.minutes.upperBound {
            free += Swift.max(0, Swift.min(span.start, part.minutes.upperBound) - cursor)
            cursor = Swift.max(cursor, span.end)
        }
        return free + Swift.max(0, part.minutes.upperBound - cursor)
    }

    /// The parts of a date free for something flexible, or nil when the day isn't known, which sends
    /// the app back to its own defaults. Lifts and classes aren't in here: each app holds those.
    public static func openParts(on day: Day, rhythm: Rhythm, changes: [DayChange]) -> [DayPart]? {
        guard let busy = busy(on: day, rhythm: rhythm) else { return nil }
        let closed = changes.closedParts(on: day)
        let clear = clearEvenings(weekOf: day.startOfWeek, rhythm: rhythm).contains(day)
        return DayPart.allCases.filter { part in
            !closed.contains(part) && !(clear && (part == .evening || part == .night)) && longestRun(part, busy: busy) >= minimumRun
        }
    }
}
