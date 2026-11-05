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

    init?(_ block: PlacedBlock) {
        guard let domain = Domain(rawValue: block.course) else { return nil }
        self.init(day: block.day, part: block.part, domain: domain, done: block.done)
        repeatIndex = block.repeatIndex
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
    /// Two commitments fill a day. Any part can still be opened by hand.
    public static func isPacked(_ weekday: Weekday, commitments: WeekCommitments) -> Bool { DayShape.isPacked(weekday, commitments: commitments) }

    /// The parts of a weekday open for study.
    public static func openParts(_ weekday: Weekday, commitments: WeekCommitments, settings: WeekSettings) -> [DayPart] {
        let held = Set(commitments.on(weekday).map(\.part))
        let packed = isPacked(weekday, commitments: commitments)
        return DayPart.allCases.filter { part in
            if let override = settings.override(weekday, part) { return override }
            return !packed && !held.contains(part) && DayShape.usualParts(weekday).contains(part)
        }
    }

    /// Whether the hub's rhythm is shaping the week, in place of Mind's defaults and the parts opened
    /// by hand. Those are kept, in case it stops.
    public static func followsRhythm(_ state: StudyState) -> Bool { state.rhythm?.pattern != nil }

    /// The parts of a date open for study. With a rhythm, work, sleep and any change say what's free,
    /// then lifts and classes take theirs. A day the rhythm doesn't know, past a term's end say, falls
    /// back on Mind's own defaults rather than reading as free.
    public static func openParts(on day: Day, state: StudyState, settings: WeekSettings) -> [DayPart] {
        if let rhythm = state.rhythm,
            let parts = DayShape.studyParts(on: day, rhythm: rhythm, changes: state.dayChanges, commitments: state.commitments)
        {
            return parts
        }
        let closed = state.dayChanges.closedParts(on: day)
        return openParts(day.weekday, commitments: state.commitments, settings: settings).filter { !closed.contains($0) }
    }

    /// The week as a grid: each part of each weekday, in order, as it stands this week.
    public static func cells(_ state: StudyState, settings: WeekSettings, layout: WeekLayout) -> [WeekCell] {
        cells(settings: settings, commitments: state.commitments, layout: layout) { weekday in
            openParts(on: layout.monday.adding(days: weekday.rawValue - 1), state: state, settings: settings)
        }
    }

    /// Open parts in this week.
    public static func openPartCount(_ state: StudyState, settings: WeekSettings) -> Int {
        let monday = state.today.startOfWeek
        return (0..<7).map { openParts(on: monday.adding(days: $0), state: state, settings: settings).count }.reduce(0, +)
    }

    /// The whole week as a grid: each part of each weekday, in order. Pass a layout to show its
    /// blocks; without one it's just the shape of the week.
    public static func cells(
        settings: WeekSettings, commitments: WeekCommitments, layout: WeekLayout? = nil, open openOn: ((Weekday) -> [DayPart])? = nil
    ) -> [WeekCell] {
        Weekday.allCases.flatMap { weekday -> [WeekCell] in
            let open = openOn?(weekday) ?? openParts(weekday, commitments: commitments, settings: settings)
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

    /// The parts of the day, best first for a course: a tie-breaker, and small against the spacing of
    /// a week. The evidence is thin. Your own chronotype matters more than any subject rule, which is
    /// why a course can be pinned. Maths goes early (Pope 2016: a small effect, in teenagers). Languages
    /// go late, because new words stick better when sleep follows soon (mostly small lab studies,
    /// though Memrise's data agrees). Writing sits off the peak, where insight comes more easily
    /// (Wieth and Zacks 2011). Reading in the evening is a preference, not a finding. See
    /// docs/decisions.md.
    static func fit(_ domain: Domain) -> [DayPart] {
        switch domain {
        case .maths: [.morning, .midday, .early, .afternoon, .evening, .night]
        case .japanese, .spanish: [.night, .evening, .afternoon, .midday, .morning, .early]
        case .reading: [.evening, .night, .afternoon, .midday, .morning, .early]
        case .writing: [.midday, .afternoon, .morning, .early, .evening, .night]
        }
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

    /// What a day brings to a week's count: 2 for a normal day, 1 in a review week, 0 before blocks
    /// began or during a pause.
    static func units(on day: Day, settings: WeekSettings, state: StudyState) -> Int {
        guard day >= settings.since else { return 0 }
        switch StudyCalendar.phase(on: day, start: state.start, calendar: state.calendar, lifeModes: state.lifeModes) {
        case .paused: return 0
        case .review: return 1
        default: return state.dayChanges.isLighter(day) ? 1 : 2
        }
    }

    /// What the week of `monday` asks for: this week's and next week's days, so that the hub can read
    /// it past the turn of the week. A lagging course gets one more block.
    public static func ask(_ state: StudyState, settings: WeekSettings, monday: Day, lagging: Set<Domain>, timeZone: TimeZone = .current) -> BlockAsk
    {
        let courses = state.settings.domains.map { domain in
            BlockCourse(
                id: domain.rawValue, blocks: settings.blocks(domain), extra: lagging.contains(domain) ? 1 : 0, pin: settings.pin(domain),
                fit: fit(domain))
        }
        var units: [String: Int] = [:]
        for offset in 0..<14 {
            let day = monday.adding(days: offset)
            units[day.iso] = self.units(on: day, settings: settings, state: state)
        }
        let active = Set(state.settings.domains)
        let finished = finished(state, settings: settings, monday: monday, timeZone: timeZone).filter { active.contains($0.domain) }
        return BlockAsk(
            monday: monday, since: settings.since, courses: courses, units: units,
            finished: finished.map { FinishedBlock(course: $0.domain.rawValue, day: $0.day, part: $0.part) }, neverStudied: state.sessions.isEmpty,
            updated: state.now)
    }

    /// What Stadig Mind publishes for the hub: this week as it stands.
    public static func published(_ state: StudyState, layout: WeekLayout) -> BlockAsk {
        var ask = ask(state, settings: state.week, monday: layout.monday, lagging: priorities(state))
        ask.planned = layout.blocks.filter { !$0.done }.map { FinishedBlock(course: $0.domain.rawValue, day: $0.day, part: $0.part) }
        return ask
    }

    /// Blocks each active course asks for in the week of `monday`, with one more for a lagging one.
    static func counts(_ state: StudyState, settings: WeekSettings, monday: Day, lagging: Set<Domain>) -> [Domain: Int] {
        let counts = ask(state, settings: settings, monday: monday, lagging: lagging).counts(monday: monday)
        return Dictionary(uniqueKeysWithValues: counts.compactMap { key, value in Domain(rawValue: key).map { ($0, value) } })
    }

    /// What a week asks for: its blocks, or its open parts if there are fewer. A week that can't
    /// hold its blocks doesn't call the rest missed.
    static func target(_ state: StudyState, settings: WeekSettings, monday: Day, lagging: Set<Domain> = []) -> Int {
        var open = 0
        for offset in 0..<7 {
            let day = monday.adding(days: offset)
            guard day >= settings.since, StudyCalendar.pause(on: day, lifeModes: state.lifeModes) == nil else { continue }
            open += openParts(on: day, state: state, settings: settings).count
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
        let ask = ask(state, settings: settings, monday: monday, lagging: lagging, timeZone: timeZone)
        var clock = Calendar(identifier: .gregorian)
        clock.timeZone = timeZone
        let week = BlockPlanner.layout(ask, today: state.today, firstPart: DayPart(hour: clock.component(.hour, from: state.now))) { day in
            openParts(on: day, state: state, settings: settings)
        }
        let counts = Dictionary(uniqueKeysWithValues: week.counts.compactMap { key, value in Domain(rawValue: key).map { ($0, value) } })
        let done = Dictionary(uniqueKeysWithValues: week.done.compactMap { key, value in Domain(rawValue: key).map { ($0, value) } })
        let leftovers = Dictionary(uniqueKeysWithValues: week.leftovers.compactMap { key, value in Domain(rawValue: key).map { ($0, value) } })
        let achieved = counts.keys.map { min(done[$0, default: 0], counts[$0, default: 0]) }.reduce(0, +)
        let target = max(achieved, target(state, settings: settings, monday: monday, lagging: lagging))
        return WeekLayout(
            monday: monday, blocks: week.blocks.compactMap(PlannedBlock.init), counts: counts, done: done, leftovers: leftovers, target: target,
            ledger: WeekTarget(total: target, counts: counts, days: countedDays(state, settings: settings, monday: monday).count))
    }
}
