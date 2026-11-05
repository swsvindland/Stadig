import Foundation
import SystemCore

/// A block of one course in a part of a day.
public struct PlannedBlock: Hashable, Sendable, Identifiable {
    public var day: Day
    public var part: DayPart
    public var domain: Domain
    public var done: Bool
    /// Which of its kind this is, when a course has two blocks in one part of a day: a block and a
    /// conversation logged the same evening.
    var repeatIndex = 0

    public init(day: Day, part: DayPart, domain: Domain, done: Bool = false) {
        self.day = day
        self.part = part
        self.domain = domain
        self.done = done
    }

    public var id: String { "\(day.iso).\(part.rawValue).\(domain.rawValue)\(repeatIndex > 0 ? ".\(repeatIndex)" : "")" }
}

/// The week as it stands: what's been done, and what's left, laid out over the parts still to come.
public struct WeekLayout: Hashable, Sendable {
    public var monday: Day
    /// Every block, in day and part order: finished ones on the days they happened, the rest ahead.
    public var blocks: [PlannedBlock]
    /// Blocks each course asks for this week.
    public var counts: [Domain: Int]
    /// Blocks each course has finished this week.
    public var done: [Domain: Int]
    /// Blocks that no longer fit in this week.
    public var leftovers: [Domain: Int]
    /// What the week asks for, for Discipline: the blocks, or the open parts if there are fewer.
    public var target: Int
    /// All of that, as a past week keeps it.
    public var ledger: WeekTarget

    public func blocks(on day: Day) -> [PlannedBlock] { blocks.filter { $0.day == day } }

    public var leftoverCount: Int { leftovers.values.reduce(0, +) }
}

/// One part of one weekday, as the week's grid shows it.
public struct WeekCell: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable {
        case block(Domain, done: Bool)
        case commitment(title: String, symbol: String)
        case open
        case closed
    }

    public var weekday: Weekday
    public var part: DayPart
    public var content: Content
    /// Whether a block can go here. Tapping the part flips it.
    public var isOpen: Bool

    public var id: String { "\(weekday.rawValue).\(part.rawValue)" }

    /// What's in it, for VoiceOver: "Tuesday evening: Japanese".
    public var accessibilityLabel: String {
        let what: String
        switch content {
        case .block(let domain, let done): what = done ? "\(domain.label), done" : domain.label
        case .commitment(let title, _): what = title
        case .open: what = "open"
        case .closed: what = "closed"
        }
        return "\(weekday.name) \(part.label.lowercased()): \(what)"
    }
}

/// Lays out a week of blocks. Each course has a count for the week rather than fixed days: what's
/// missed rolls forward to the next open part, whatever gets done counts wherever it happened, and
/// nothing has to be said about a day that didn't go to plan.
///
/// Only `layout` decides which part a block goes in, from the parts it's given, so a plan from the
/// hub can replace that one step without touching lessons or Discipline.
public enum WeekPlanner {
    /// The parts a weekday offers before anything else is known. Mind can't see work, so a day job
    /// is assumed: weekdays offer the ends of the day, weekends all of it.
    static func usualParts(_ weekday: Weekday) -> [DayPart] {
        switch weekday {
        case .saturday, .sunday: DayPart.allCases
        default: [.early, .evening, .night]
        }
    }

    /// Two commitments fill a day: with the gym in the morning and a class in the evening, there's
    /// no study to fit around them. Any part can still be opened by hand.
    public static func isPacked(_ weekday: Weekday, commitments: WeekCommitments) -> Bool { commitments.on(weekday).count >= 2 }

    /// The parts of a weekday open for study.
    public static func openParts(_ weekday: Weekday, commitments: WeekCommitments, settings: WeekSettings) -> [DayPart] {
        let held = Set(commitments.on(weekday).map(\.part))
        let packed = isPacked(weekday, commitments: commitments)
        return DayPart.allCases.filter { part in
            if let override = settings.override(weekday, part) { return override }
            return !packed && !held.contains(part) && usualParts(weekday).contains(part)
        }
    }

    /// The whole week as a grid: each part of each weekday, in order. Pass a layout to show its
    /// blocks; without one it's just the shape of the week.
    public static func cells(settings: WeekSettings, commitments: WeekCommitments, layout: WeekLayout? = nil) -> [WeekCell] {
        Weekday.allCases.flatMap { weekday -> [WeekCell] in
            let open = openParts(weekday, commitments: commitments, settings: settings)
            let held = commitments.on(weekday)
            let blocks = layout?.blocks.filter { $0.day.weekday == weekday } ?? []
            return DayPart.allCases.map { part in
                let isOpen = open.contains(part)
                let content: WeekCell.Content
                if let block = blocks.first(where: { $0.part == part }) {
                    content = .block(block.domain, done: block.done)
                } else if isOpen {
                    content = .open
                } else if let commitment = held.first(where: { $0.part == part }) {
                    content = .commitment(title: commitment.title, symbol: commitment.symbol)
                } else {
                    content = .closed
                }
                return WeekCell(weekday: weekday, part: part, content: content, isOpen: isOpen)
            }
        }
    }

    /// Open parts in a whole week, however many blocks there are.
    public static func openPartCount(settings: WeekSettings, commitments: WeekCommitments) -> Int {
        Weekday.allCases.map { openParts($0, commitments: commitments, settings: settings).count }.reduce(0, +)
    }

    /// Opens a part if it's closed and closes it if it's open. When that's what the week would do by
    /// itself, the hand-set value goes, so a later change in Stadig Lift still reaches this part.
    public static func toggling(_ weekday: Weekday, _ part: DayPart, settings: WeekSettings, commitments: WeekCommitments) -> WeekSettings {
        var week = settings
        let open = openParts(weekday, commitments: commitments, settings: settings).contains(part)
        week.setOverride(nil, weekday, part)
        if openParts(weekday, commitments: commitments, settings: week).contains(part) == open { week.setOverride(!open, weekday, part) }
        return week
    }

    /// A whole week as these choices would make it, for setup to show: from its Monday, with none of
    /// a first day's shortcuts. `since` goes a week back so that no day of it is the first.
    public static func preview(_ settings: MindSettings, week: WeekSettings, commitments: WeekCommitments, on day: Day) -> [WeekCell] {
        let monday = day.startOfWeek
        var whole = week
        whole.since = monday.adding(weeks: -1)
        let state = StudyState(settings: settings, today: monday, now: monday.date(), weekSettings: whole, commitments: commitments)
        return cells(settings: week, commitments: commitments, layout: layout(state, settings: whole))
    }

    // MARK: Time of day

    /// How well a part suits a course, from 2.5 at its best: a tie-breaker, and small against the
    /// spacing of a week. The evidence is thin. Your own chronotype matters more than any subject
    /// rule, which is why a course can be pinned. Maths goes early (Pope 2016: a small effect, in
    /// teenagers). Languages go late, because new words stick better when sleep follows soon (mostly
    /// small lab studies, though Memrise's data agrees). Writing sits off the peak, where insight
    /// comes more easily (Wieth and Zacks 2011). Reading in the evening is a preference, not a
    /// finding. See docs/decisions.md.
    static func timeFit(_ domain: Domain, _ part: DayPart) -> Double {
        let order: [DayPart]
        switch domain {
        case .maths: order = [.morning, .midday, .early, .afternoon, .evening, .night]
        case .japanese, .spanish: order = [.night, .evening, .afternoon, .midday, .morning, .early]
        case .reading: order = [.evening, .night, .afternoon, .midday, .morning, .early]
        case .writing: order = [.midday, .afternoon, .morning, .early, .evening, .night]
        }
        return Double(order.count - 1 - (order.firstIndex(of: part) ?? order.count - 1)) * 0.5
    }

    // MARK: The week's counts

    /// Courses that lagged when the week began. Worked out from before Monday, so a check-in landing
    /// midweek doesn't reshape the week under the person.
    static func priorities(_ state: StudyState) -> Set<Domain> {
        guard state.settings.autoPrioritise else { return [] }
        let monday = state.today.startOfWeek
        var past = state
        past.tests = state.tests.filter { state.day($0.date) < monday }
        past.books = state.books.filter { !$0.done || ReadingPlan.finishDay($0, dayStart: state.dayStart) < monday }
        past.today = monday
        past.now = monday.date()
        return SessionPlanner.priorities(past)
    }

    /// Blocks a course asks for in a week. Each day of the week brings a seventh of the course's
    /// blocks, or half that in a review week, and none before blocks began or during a pause, so a
    /// Thursday start or a pause ending on Wednesday asks for a share of the week, not the whole of
    /// it. A review week that starts midweek is covered the same way. Rounded up: the count is
    /// worked in fourteenths so that seven sevenths of four is four and not a hair over.
    static func count(_ domain: Domain, settings: WeekSettings, state: StudyState, monday: Day) -> Int {
        let blocks = settings.blocks(domain)
        var fourteenths = 0
        for offset in 0..<7 {
            let day = monday.adding(days: offset)
            guard day >= settings.since else { continue }
            switch StudyCalendar.phase(on: day, start: state.start, calendar: state.calendar, lifeModes: state.lifeModes) {
            case .paused: continue
            case .review: fourteenths += blocks
            default: fourteenths += blocks * 2
            }
        }
        return (fourteenths + 13) / 14
    }

    /// Blocks each active course asks for in the week of `monday`, with one more for a lagging one.
    static func counts(_ state: StudyState, settings: WeekSettings, monday: Day, lagging: Set<Domain>) -> [Domain: Int] {
        var counts: [Domain: Int] = [:]
        for domain in state.settings.domains {
            let count = count(domain, settings: settings, state: state, monday: monday)
            counts[domain] = count + (count > 0 && lagging.contains(domain) ? 1 : 0)
        }
        return counts
    }

    /// What a week asks for: its blocks, or its open parts if there are fewer. A week that can't
    /// hold its blocks doesn't call the rest missed.
    static func target(_ state: StudyState, settings: WeekSettings, monday: Day, lagging: Set<Domain> = []) -> Int {
        var open = 0
        for offset in 0..<7 {
            let day = monday.adding(days: offset)
            guard day >= settings.since, StudyCalendar.pause(on: day, lifeModes: state.lifeModes) == nil else { continue }
            open += openParts(day.weekday, commitments: state.commitments, settings: settings).count
        }
        return min(counts(state, settings: settings, monday: monday, lagging: lagging).values.reduce(0, +), open)
    }

    /// The days of a week that count: from the day blocks began, and not during a pause.
    static func countedDays(_ state: StudyState, settings: WeekSettings, monday: Day) -> [Day] {
        (0..<7).map { monday.adding(days: $0) }.filter { day in
            day >= settings.since && StudyCalendar.pause(on: day, lifeModes: state.lifeModes) == nil
        }
    }

    /// Every finished block of the week: a session of one course that counted, wherever and whenever
    /// it happened. A session that was stopped early doesn't count, so its block is still to do, and
    /// nor does a placement left without a single answer, which is still to come. Check-ins and
    /// quick reviews aren't blocks.
    static func finished(_ state: StudyState, settings: WeekSettings, monday: Day, timeZone: TimeZone) -> [PlannedBlock] {
        var clock = Calendar(identifier: .gregorian)
        clock.timeZone = timeZone
        var out: [PlannedBlock] = []
        for session in state.sessions where session.counts && [.regular, .review, .placement].contains(session.purpose) {
            if session.purpose == .placement && session.attempts.isEmpty && session.minutes == 0 { continue }
            let day = session.day(startingAt: state.dayStart)
            guard day >= monday, day <= monday.adding(days: 6), day >= settings.since else { continue }
            for domain in session.domains {
                out.append(PlannedBlock(day: day, part: DayPart(hour: clock.component(.hour, from: session.start)), domain: domain, done: true))
            }
        }
        return out
    }

    // MARK: Layout

    /// The week as of `state.today`.
    ///
    /// Today's blocks hold all day: the layout starts from what was done before today, with all of
    /// today's parts, and the day's finished blocks are ticked off afterwards. Only tomorrow does the
    /// week re-form around what actually happened.
    public static func layout(_ state: StudyState, settings: WeekSettings, timeZone: TimeZone = .current) -> WeekLayout {
        let monday = state.today.startOfWeek
        let lagging = priorities(state)
        let counts = counts(state, settings: settings, monday: monday, lagging: lagging)
        let finished = finished(state, settings: settings, monday: monday, timeZone: timeZone).filter { counts[$0.domain] != nil }
        var left = counts
        for block in finished where block.day < state.today { left[block.domain, default: 0] -= 1 }

        // The parts to come, today's included.
        var parts: [(day: Day, part: DayPart)] = []
        for offset in 0..<7 {
            let day = monday.adding(days: offset)
            guard day >= state.today, day >= settings.since, StudyCalendar.pause(on: day, lifeModes: state.lifeModes) == nil else { continue }
            parts += openParts(day.weekday, commitments: state.commitments, settings: settings).map { (day, $0) }
        }
        // Only what came before today counts against a part. Today's own finished blocks would push
        // their courses off the day, and the list has to hold until tomorrow.
        var placed = place(left.filter { $0.value > 0 }, in: parts, settings: settings, earlier: finished.filter { $0.day < state.today })

        // The very first block follows onboarding straight away, whatever the day looks like.
        if state.sessions.isEmpty, state.today == settings.since, !placed.blocks.contains(where: { $0.day == state.today }) {
            var clock = Calendar(identifier: .gregorian)
            clock.timeZone = timeZone
            let part = DayPart(hour: clock.component(.hour, from: state.now))
            if let first = placed.blocks.indices.first {
                placed.blocks[first].day = state.today
                placed.blocks[first].part = part
            } else if let domain = placed.leftovers.keys.sorted().first {
                // A closed last day of the week: nothing placed, and the first block still follows.
                placed.blocks.append(PlannedBlock(day: state.today, part: part, domain: domain))
                placed.leftovers[domain, default: 0] -= 1
            }
        }

        // A block done today comes off today's list; one that wasn't on it comes off the end of its
        // course's week instead, so that the day's list doesn't change but the count still holds.
        var extras: [PlannedBlock] = []
        for block in finished where block.day == state.today {
            if let index = placed.blocks.firstIndex(where: { $0.day == block.day && $0.domain == block.domain && !$0.done }) {
                placed.blocks[index].done = true
            } else {
                extras.append(block)
                if let last = placed.blocks.lastIndex(where: { $0.domain == block.domain && $0.day > block.day }) {
                    placed.blocks.remove(at: last)
                } else if placed.leftovers[block.domain, default: 0] > 0 {
                    placed.leftovers[block.domain, default: 0] -= 1
                }
            }
        }

        let past = finished.filter { $0.day < state.today }
        let done = Dictionary(finished.map { ($0.domain, 1) }, uniquingKeysWith: +)
        let achieved = counts.keys.map { min(done[$0, default: 0], counts[$0, default: 0]) }.reduce(0, +)
        let target = max(achieved, target(state, settings: settings, monday: monday, lagging: lagging))
        var blocks = (past + placed.blocks + extras).sorted { ($0.day, $0.part, $0.domain) < ($1.day, $1.part, $1.domain) }
        var seen: [String: Int] = [:]
        for index in blocks.indices {
            blocks[index].repeatIndex = seen[blocks[index].id, default: 0]
            seen[PlannedBlock(day: blocks[index].day, part: blocks[index].part, domain: blocks[index].domain).id, default: 0] += 1
        }
        return WeekLayout(
            monday: monday, blocks: blocks, counts: counts, done: done, leftovers: placed.leftovers.filter { $0.value > 0 }, target: target,
            ledger: WeekTarget(total: target, counts: counts, days: countedDays(state, settings: settings, monday: monday).count))
    }

    /// Places what's left, a round at a time so that the courses take turns at the best parts. Each
    /// block takes the part that suits it best, keeping a course to one block a day where it can and
    /// spreading the blocks over the days: spacing matters more than the time of day. Ties go by day,
    /// then part, so the same week always comes out the same way.
    static func place(_ left: [Domain: Int], in parts: [(day: Day, part: DayPart)], settings: WeekSettings, earlier: [PlannedBlock]) -> (
        blocks: [PlannedBlock], leftovers: [Domain: Int]
    ) {
        var blocks: [PlannedBlock] = []
        var leftovers: [Domain: Int] = [:]
        var free = parts
        let order = left.keys.sorted { (-left[$0, default: 0], $0) < (-left[$1, default: 0], $1) }
        for round in 0..<(left.values.max() ?? 0) {
            for domain in order where round < left[domain, default: 0] {
                var best: (index: Int, score: Double)?
                let same = (blocks + earlier).filter { $0.domain == domain }
                for (index, slot) in free.enumerated() {
                    let sameDay = same.filter { $0.day == slot.day }.count
                    let nextDoor = same.filter { abs($0.day.days(until: slot.day)) == 1 }.count
                    let thatDay = blocks.filter { $0.day == slot.day }.count
                    let pinned = settings.pin(domain) == slot.part ? 6.0 : 0
                    let score = timeFit(domain, slot.part) + pinned - 5 * Double(sameDay) - 1.4 * Double(thatDay) - 0.6 * Double(nextDoor)
                    if score > best?.score ?? -.infinity { best = (index, score) }
                }
                guard let best else {
                    leftovers[domain, default: 0] += 1
                    continue
                }
                let slot = free.remove(at: best.index)
                blocks.append(PlannedBlock(day: slot.day, part: slot.part, domain: domain))
            }
        }
        return (blocks, leftovers)
    }
}
