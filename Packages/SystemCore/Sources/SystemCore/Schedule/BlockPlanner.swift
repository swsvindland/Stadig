import Foundation

/// A course that wants blocks in a week. Stadig Mind says what it wants; the layout doesn't need to
/// know what a course is.
public struct BlockCourse: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    /// Blocks a week.
    public var blocks: Int
    /// One more for a lagging course, for the week this was published in.
    public var extra: Int
    /// The part it's been fixed to, if any.
    public var pin: DayPart?
    /// The parts of the day, best first.
    public var fit: [DayPart]

    public init(id: String, blocks: Int, extra: Int = 0, pin: DayPart? = nil, fit: [DayPart]) {
        self.id = id
        self.blocks = blocks
        self.extra = extra
        self.pin = pin
        self.fit = fit
    }
}

/// A block that happened, on the study day and in the part of the day it did.
public struct FinishedBlock: Hashable, Codable, Sendable {
    public var course: String
    public var day: Day
    public var part: DayPart

    public init(course: String, day: Day, part: DayPart) {
        self.course = course
        self.day = day
        self.part = part
    }
}

/// What a week of blocks asks for: everything the layout needs and nothing else, so that Stadig Mind
/// can publish it and the hub can lay out the same week without the app running.
public struct BlockAsk: Hashable, Codable, Sendable {
    public static let schemaVersion = 1
    /// Bumped when the layout changes. Two builds that differ can't predict each other, so the hub
    /// shows what the app last published instead.
    public static let currentAlgorithm = 1

    public var algorithm: Int
    /// The Monday of the week it was made in.
    public var monday: Day
    /// The first day blocks counted.
    public var since: Day
    /// In the order ties go.
    public var courses: [BlockCourse]
    /// What each day brings to a week's count, by its ISO date, this week and next: 2 for a normal
    /// day, 1 for a review or lighter day, 0 for a day that doesn't count.
    public var units: [String: Int]
    /// The blocks finished in the week it was made.
    public var finished: [FinishedBlock]
    /// Nothing has ever been studied, so the first block follows setup straight away.
    public var neverStudied: Bool
    /// The week as the app last laid it out, for a hub on a different `algorithm`.
    public var planned: [FinishedBlock]
    public var updated: Date

    public init(
        algorithm: Int = currentAlgorithm, monday: Day, since: Day, courses: [BlockCourse], units: [String: Int], finished: [FinishedBlock],
        neverStudied: Bool = false, planned: [FinishedBlock] = [], updated: Date = Date()
    ) {
        self.algorithm = algorithm
        self.monday = monday
        self.since = since
        self.courses = courses
        self.units = units
        self.finished = finished
        self.neverStudied = neverStudied
        self.planned = planned
        self.updated = updated
    }

    /// The same ask with a lighter week taken into account. Tapped in the hub, a lighter week may be
    /// news to Stadig Mind, which hasn't been opened since. A review day is one unit already, so the
    /// two don't stack.
    public func lightened(by changes: [DayChange]) -> BlockAsk {
        var ask = self
        for (iso, count) in units {
            guard let day = Day(iso: iso), changes.isLighter(day) else { continue }
            ask.units[iso] = min(count, 1)
        }
        return ask
    }

    /// What a day brings to the count. A day past what was published counts as a normal one.
    public func units(on day: Day) -> Int { day < since ? 0 : units[day.iso] ?? 2 }

    /// Blocks a course asks for in a week. Each day brings a seventh of them, or half that on a
    /// review or lighter day, and none before blocks began or during a pause. Rounded up, and worked
    /// in fourteenths so that seven sevenths of four is four and not a hair over.
    public func count(_ course: BlockCourse, monday week: Day) -> Int {
        let fourteenths = (0..<7).map { units(on: week.adding(days: $0)) * course.blocks }.reduce(0, +)
        let count = (fourteenths + 13) / 14
        return count + (count > 0 && week == monday ? course.extra : 0)
    }

    public func counts(monday week: Day) -> [String: Int] { Dictionary(uniqueKeysWithValues: courses.map { ($0.id, count($0, monday: week)) }) }
}

/// A block in a part of a day.
public struct PlacedBlock: Hashable, Sendable, Identifiable {
    public var day: Day
    public var part: DayPart
    public var course: String
    public var done: Bool
    /// Which of its kind this is, when a course has two blocks in one part of a day: a block and a
    /// conversation logged the same evening.
    public var repeatIndex = 0

    public init(day: Day, part: DayPart, course: String, done: Bool = false) {
        self.day = day
        self.part = part
        self.course = course
        self.done = done
    }

    public var id: String { "\(day.iso).\(part.rawValue).\(course)\(repeatIndex > 0 ? ".\(repeatIndex)" : "")" }
}

/// The week as it stands: what's been done, and what's left, laid out over the parts still to come.
public struct BlockLayout: Hashable, Sendable {
    public var monday: Day
    /// Every block, in day and part order: finished ones on the days they happened, the rest ahead.
    public var blocks: [PlacedBlock]
    public var counts: [String: Int]
    public var done: [String: Int]
    /// Blocks that no longer fit in this week.
    public var leftovers: [String: Int]
}

/// Lays out a week of blocks: one function, called by Stadig Mind for itself and by the hub to show
/// the same week. Each course has a count for the week rather than fixed days, so what's missed rolls
/// forward to the next open part and nothing has to be said about a day that didn't go to plan.
public enum BlockPlanner {
    /// The week as of `today`, from the open parts of each day.
    ///
    /// Today's blocks hold all day: the layout starts from what was done before today, with all of
    /// today's parts, and the day's finished blocks are ticked off afterwards. Only tomorrow does the
    /// week re-form around what actually happened. `firstPart` is the part it is now, for the very
    /// first block, which follows setup whatever the day looks like.
    public static func layout(_ ask: BlockAsk, today: Day, firstPart: DayPart?, parts open: (Day) -> [DayPart]) -> BlockLayout {
        let monday = today.startOfWeek
        let counts = ask.counts(monday: monday)
        let order = Dictionary(uniqueKeysWithValues: ask.courses.enumerated().map { ($0.element.id, $0.offset) })
        let week = monday...monday.adding(days: 6)
        let finished = ask.finished.filter { week.contains($0.day) && counts[$0.course] != nil }
            .map { PlacedBlock(day: $0.day, part: $0.part, course: $0.course, done: true) }
        var left = counts
        for block in finished where block.day < today { left[block.course, default: 0] -= 1 }

        // The parts to come, today's included.
        var parts: [(day: Day, part: DayPart)] = []
        for offset in 0..<7 {
            let day = monday.adding(days: offset)
            guard day >= today, ask.units(on: day) > 0 else { continue }
            parts += open(day).map { (day, $0) }
        }
        // Only what came before today counts against a part. Today's own finished blocks would push
        // their courses off the day, and the list has to hold until tomorrow.
        var placed = place(ask, left: left.filter { $0.value > 0 }, in: parts, earlier: finished.filter { $0.day < today })

        if ask.neverStudied, today == ask.since, let firstPart, !placed.blocks.contains(where: { $0.day == today }) {
            if let first = placed.blocks.indices.first {
                placed.blocks[first].day = today
                placed.blocks[first].part = firstPart
            } else if let course = ask.courses.first(where: { placed.leftovers[$0.id, default: 0] > 0 }) {
                // A closed last day of the week: nothing placed, and the first block still follows.
                placed.blocks.append(PlacedBlock(day: today, part: firstPart, course: course.id))
                placed.leftovers[course.id, default: 0] -= 1
            }
        }

        // A block done today comes off today's list; one that wasn't on it comes off the end of its
        // course's week instead, so that the day's list doesn't change but the count still holds.
        var extras: [PlacedBlock] = []
        for block in finished where block.day == today {
            if let index = placed.blocks.firstIndex(where: { $0.day == block.day && $0.course == block.course && !$0.done }) {
                placed.blocks[index].done = true
            } else {
                extras.append(block)
                if let last = placed.blocks.lastIndex(where: { $0.course == block.course && $0.day > block.day }) {
                    placed.blocks.remove(at: last)
                } else if placed.leftovers[block.course, default: 0] > 0 {
                    placed.leftovers[block.course, default: 0] -= 1
                }
            }
        }

        let past = finished.filter { $0.day < today }
        var blocks = (past + placed.blocks + extras).sorted {
            ($0.day, $0.part, order[$0.course] ?? .max) < ($1.day, $1.part, order[$1.course] ?? .max)
        }
        var seen: [String: Int] = [:]
        for index in blocks.indices {
            let plain = PlacedBlock(day: blocks[index].day, part: blocks[index].part, course: blocks[index].course).id
            blocks[index].repeatIndex = seen[plain, default: 0]
            seen[plain, default: 0] += 1
        }
        return BlockLayout(
            monday: monday, blocks: blocks, counts: counts, done: Dictionary(finished.map { ($0.course, 1) }, uniquingKeysWith: +),
            leftovers: placed.leftovers.filter { $0.value > 0 })
    }

    /// How well a part suits a course, from 2.5 at its best: a tie-breaker, and small against the
    /// spacing of a week.
    static func fit(_ course: BlockCourse, _ part: DayPart) -> Double {
        Double(course.fit.count - 1 - (course.fit.firstIndex(of: part) ?? course.fit.count - 1)) * 0.5
    }

    /// Places what's left, a round at a time so that the courses take turns at the best parts. Each
    /// block takes the part that suits it best, keeping a course to one block a day where it can and
    /// spreading the blocks over the days: spacing matters more than the time of day. Ties go by day,
    /// then part, so the same week always comes out the same way.
    static func place(_ ask: BlockAsk, left: [String: Int], in parts: [(day: Day, part: DayPart)], earlier: [PlacedBlock]) -> (
        blocks: [PlacedBlock], leftovers: [String: Int]
    ) {
        var blocks: [PlacedBlock] = []
        var leftovers: [String: Int] = [:]
        var free = parts
        let position = Dictionary(uniqueKeysWithValues: ask.courses.enumerated().map { ($0.element.id, $0.offset) })
        let order = ask.courses.filter { left[$0.id] != nil }.sorted {
            (-left[$0.id, default: 0], position[$0.id, default: 0]) < (-left[$1.id, default: 0], position[$1.id, default: 0])
        }
        for round in 0..<(left.values.max() ?? 0) {
            for course in order where round < left[course.id, default: 0] {
                var best: (index: Int, score: Double)?
                let same = (blocks + earlier).filter { $0.course == course.id }
                for (index, slot) in free.enumerated() {
                    let sameDay = same.filter { $0.day == slot.day }.count
                    let nextDoor = same.filter { abs($0.day.days(until: slot.day)) == 1 }.count
                    let thatDay = blocks.filter { $0.day == slot.day }.count
                    let pinned = course.pin == slot.part ? 6.0 : 0
                    let score = fit(course, slot.part) + pinned - 5 * Double(sameDay) - 1.4 * Double(thatDay) - 0.6 * Double(nextDoor)
                    if score > best?.score ?? -.infinity { best = (index, score) }
                }
                guard let best else {
                    leftovers[course.id, default: 0] += 1
                    continue
                }
                let slot = free.remove(at: best.index)
                blocks.append(PlacedBlock(day: slot.day, part: slot.part, course: course.id))
            }
        }
        return (blocks, leftovers)
    }
}
