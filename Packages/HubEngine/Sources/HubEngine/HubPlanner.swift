import Foundation
import SystemCore
import SystemStore

/// Everything the hub knows: what it holds itself, and what the apps last published.
public struct HubInputs: Sendable {
    public var rhythm: Rhythm
    public var changes: [DayChange]
    public var profile: SharedProfile?
    public var lift: AppSummary?
    /// Stadig Macro's summary, which says it's in use even before it has meal times to give.
    public var macro: AppSummary?
    /// Stadig Mind's summary, for the stats.
    public var mind: AppSummary?
    public var ask: BlockAsk?
    public var meals: MealRhythm?
    public var today: Day
    public var now: Date
    public var timeZone: TimeZone

    public init(
        rhythm: Rhythm, changes: [DayChange] = [], profile: SharedProfile? = nil, lift: AppSummary? = nil, macro: AppSummary? = nil,
        mind: AppSummary? = nil, ask: BlockAsk? = nil, meals: MealRhythm? = nil,
        today: Day, now: Date, timeZone: TimeZone = .current
    ) {
        self.rhythm = rhythm
        self.changes = changes.live
        self.profile = profile
        self.lift = lift
        self.macro = macro
        self.mind = mind
        self.ask = ask
        self.meals = meals
        self.today = today
        self.now = now
        self.timeZone = timeZone
    }
}

/// One thing in a part of a day.
public struct HubItem: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable { case lift, activity, meal, study, work, commute }

    public var id: String
    public var title: String
    public var kind: Kind
    public var part: DayPart
    public var minutes: Int
    public var done: Bool
    /// The app that tracks it. Nothing else has anything to tap: it passes by itself.
    public var app: AppID?
    /// Where it goes within its part, in minutes from midnight. Only for putting a part in order:
    /// what's flexible has no time of its own.
    public var order: Int
    /// The commitment it comes from, for a class or the gym: the name a move goes by.
    public var commitment: String?

    public init(
        id: String, title: String, kind: Kind, part: DayPart, minutes: Int, done: Bool = false, app: AppID? = nil, order: Int = 0,
        commitment: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.part = part
        self.minutes = minutes
        self.done = done
        self.app = app
        self.order = order
        self.commitment = commitment
    }

    /// Whether it can be moved: a class or the gym, until it's done.
    public var canMove: Bool { commitment != nil && !done }

    /// Work and the commute are the day's shape, not things to do.
    public var isYours: Bool { kind != .work && kind != .commute }
}

public struct HubPart: Hashable, Sendable, Identifiable {
    public var part: DayPart
    public var items: [HubItem]
    /// Minutes with nothing on: free time is whatever's left.
    public var freeMinutes: Int
    /// You said you're out.
    public var isClosed: Bool

    public var id: DayPart { part }
}

public struct HubDay: Hashable, Sendable, Identifiable {
    public var day: Day
    public var parts: [HubPart]
    /// Whether the rhythm knows this day. Past a term's end it doesn't, and says so.
    public var isKnown: Bool

    public var id: Day { day }
    public var items: [HubItem] { parts.flatMap(\.items) }
    public var freeMinutes: Int { parts.map(\.freeMinutes).reduce(0, +) }
    public var studyBlocks: Int { items.filter { $0.kind == .study }.count }
}

public struct HubWeek: Hashable, Sendable {
    public var monday: Day
    public var days: [HubDay]
    /// Blocks that no longer fit this week.
    public var leftovers: Int
    /// Evenings with at least this free count as clear.
    public static let clearMinutes = 150

    public var gym: Int { days.flatMap(\.items).filter { $0.kind == .lift }.count }
    public var study: Int { days.map(\.studyBlocks).reduce(0, +) }
    public var freeMinutes: Int { days.map(\.freeMinutes).reduce(0, +) }

    /// Evenings with no class and room to breathe.
    public var clearEvenings: Int {
        days.filter { day in
            let evening = day.parts.filter { $0.part == .evening || $0.part == .night }
            return !evening.flatMap(\.items).contains { $0.kind == .activity } && evening.map(\.freeMinutes).reduce(0, +) >= Self.clearMinutes
        }.count
    }
}

/// Puts a day together from what the apps published. A pure function of its inputs: nothing is stored,
/// so there's nothing to go out of date, and whatever wasn't done has moved on by itself.
public enum HubPlanner {
    /// Published data older than this says nothing about now: the app may be gone.
    public static let staleDays = 28
    /// A meal's place on the day.
    static let mealMinutes = 30

    static func fresh(_ updated: Date, _ inputs: HubInputs) -> Bool { Day(updated, timeZone: inputs.timeZone).days(until: inputs.today) <= staleDays }

    public static func week(of day: Day, _ inputs: HubInputs) -> HubWeek {
        let monday = day.startOfWeek
        let commitments = commitments(inputs)
        let blocks = study(monday: monday, inputs, commitments: commitments)
        return HubWeek(
            monday: monday, days: (0..<7).map { self.day(on: monday.adding(days: $0), inputs, commitments: commitments, blocks: blocks.blocks) },
            leftovers: blocks.leftovers)
    }

    public static func day(on day: Day, _ inputs: HubInputs) -> HubDay {
        let commitments = commitments(inputs)
        return self.day(on: day, inputs, commitments: commitments, blocks: study(monday: day.startOfWeek, inputs, commitments: commitments).blocks)
    }

    static func commitments(_ inputs: HubInputs) -> WeekCommitments {
        let lift = inputs.lift.flatMap { fresh($0.updated, inputs) ? $0 : nil }
        return WeekCommitments(profile: inputs.profile, lift: lift, before: inputs.today, timeZone: inputs.timeZone).placed(by: inputs.rhythm)
    }

    /// Stadig Mind's week, laid out by the same function Mind uses, or the week it last published if
    /// the two builds don't lay out alike. Within today the blocks hold their parts.
    static func study(monday: Day, _ inputs: HubInputs, commitments: WeekCommitments) -> (blocks: [PlacedBlock], leftovers: Int) {
        guard let published = inputs.ask, fresh(published.updated, inputs) else { return ([], 0) }
        let ask = published.lightened(by: inputs.changes)
        guard ask.algorithm == BlockAsk.currentAlgorithm else {
            let planned = ask.planned.map { PlacedBlock(day: $0.day, part: $0.part, course: $0.course) }
            let finished = ask.finished.map { PlacedBlock(day: $0.day, part: $0.part, course: $0.course, done: true) }
            return (planned + finished, 0)
        }
        let today = max(inputs.today, monday)
        let layout = BlockPlanner.layout(ask, today: today, firstPart: nil) { day in
            DayShape.studyParts(on: day, rhythm: inputs.rhythm, changes: inputs.changes, commitments: commitments)
                ?? DayShape.usualParts(day.weekday).filter { !inputs.changes.closedParts(on: day).contains($0) }
        }
        return (layout.blocks, layout.leftovers.values.reduce(0, +))
    }

    /// What a course's id reads as on screen.
    static func title(_ course: String) -> String { course.prefix(1).uppercased() + course.dropFirst() }

    static func day(on day: Day, _ inputs: HubInputs, commitments: WeekCommitments, blocks: [PlacedBlock]) -> HubDay {
        let busy = DayShape.busy(on: day, rhythm: inputs.rhythm)
        let closed = inputs.changes.closedParts(on: day)
        var items: [HubItem] = []

        // Work, school and the commute, split across the parts they run through. A night shift's
        // end belongs to the morning after it, which is on this day's timeline.
        let pattern = inputs.rhythm.pattern
        let lastNight = (pattern?.spans(on: day.adding(days: -1)) ?? []).filter { $0.end > DayPart.night.minutes.upperBound }
        let spans = (pattern?.spans(on: day) ?? []) + lastNight.map { DaySpan($0.kind, $0.label, from: $0.start - 1440, to: $0.end - 1440) }
        for span in spans where span.kind != .sleep {
            for part in DayPart.allCases {
                let minutes = min(span.end, part.minutes.upperBound) - max(span.start, part.minutes.lowerBound)
                guard minutes > 0 else { continue }
                let kind: HubItem.Kind = span.kind == .commute ? .commute : .work
                items.append(
                    HubItem(
                        id: "\(day.iso).\(part.rawValue).\(span.label).\(span.start)", title: span.label, kind: kind, part: part, minutes: minutes,
                        order: max(span.start, part.minutes.lowerBound)))
            }
        }

        // Classes first, at their set time: a class is a fact about the week, so it stays even when the
        // part is tight, and whatever doesn't fit runs on into the next. Going out takes it off the
        // day, with no mark. The lift is what can move, to the next part with room, or it waits for
        // another day, because its quota is weekly.
        var room: [DayPart: Int] = [:]
        for part in DayPart.allCases { room[part] = busy.map { DayShape.freeMinutes(part, busy: $0) } ?? part.minutes.count }
        func slot(in part: DayPart) -> Int { busy.map { DayShape.longestRunStart(part, busy: $0) } ?? part.minutes.lowerBound }
        func take(_ minutes: Int, from part: DayPart) -> Bool {
            guard room[part, default: 0] >= minutes else { return false }
            room[part, default: 0] -= minutes
            return true
        }
        func spend(_ minutes: Int, from part: DayPart) {
            var left = minutes
            for later in DayPart.allCases where later >= part {
                let used = min(left, room[later, default: 0])
                room[later, default: 0] -= used
                left -= used
            }
        }
        let onDay = commitments.on(day, changes: inputs.changes)
        for commitment in onDay where commitment.title != WeekCommitments.liftTitle && !closed.contains(commitment.part) {
            spend(commitment.minutes, from: commitment.part)
            items.append(
                HubItem(
                    id: "\(day.iso).\(commitment.title)", title: commitment.title, kind: .activity, part: commitment.part,
                    minutes: commitment.minutes,
                    order: slot(in: commitment.part), commitment: commitment.title))
        }
        for commitment in onDay where commitment.title == WeekCommitments.liftTitle {
            let order = ([commitment.part] + DayPart.allCases.filter { $0 != commitment.part }).filter { !closed.contains($0) }
            let minutes = inputs.changes.isLighter(day) ? DayChange.lighterMinutes(commitment.minutes) : commitment.minutes
            guard let part = order.first(where: { take(minutes, from: $0) }) else { continue }
            let done = inputs.lift?.sessions.contains { $0.kind == .strength && Day($0.start, timeZone: inputs.timeZone) == day } ?? false
            items.append(
                HubItem(
                    id: "\(day.iso).\(commitment.title)", title: "Gym", kind: .lift, part: part, minutes: minutes, done: done,
                    app: .liftTrack, order: slot(in: part), commitment: commitment.title))
        }

        // Meals in their usual parts, ticked off as they're logged.
        if let meals = inputs.meals, fresh(meals.updated, inputs) {
            var eaten = meals.day == day ? meals.eaten : []
            for (index, part) in meals.usual.enumerated() where !closed.contains(part) {
                let done = eaten.firstIndex(of: part).map { eaten.remove(at: $0) } != nil
                _ = take(mealMinutes, from: part)
                items.append(
                    HubItem(
                        id: "\(day.iso).meal.\(index)", title: "Meal", kind: .meal, part: part, minutes: mealMinutes, done: done, app: .macroTrack,
                        order: slot(in: part)))
            }
            // What was eaten at an unusual time, or before there's a usual time at all, still happened.
            for (index, part) in eaten.enumerated() {
                _ = take(mealMinutes, from: part)
                items.append(
                    HubItem(
                        id: "\(day.iso).meal.extra.\(index)", title: "Meal", kind: .meal, part: part, minutes: mealMinutes, done: true,
                        app: .macroTrack, order: slot(in: part)))
            }
        }

        for block in blocks where block.day == day {
            _ = take(inputs.ask?.courses.isEmpty == false ? 25 : 0, from: block.part)
            items.append(
                HubItem(
                    id: block.id, title: title(block.course), kind: .study, part: block.part, minutes: 25, done: block.done, app: .knowledge,
                    order: slot(in: block.part)))
        }

        // Within a part, in the order they happen; what shares a place stays in the order it was added.
        let ordered = items.enumerated().sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }.map(\.element)
        let parts = DayPart.allCases.map { part in
            HubPart(
                part: part, items: ordered.filter { $0.part == part }, freeMinutes: closed.contains(part) ? 0 : max(0, room[part, default: 0]),
                isClosed: closed.contains(part))
        }
        return HubDay(day: day, parts: parts, isKnown: busy != nil)
    }

    /// What's next: the first thing of yours still to do from now on, else the earliest left today.
    /// Nothing is ever overdue: what's passed stays in the list until the day turns over.
    public static func next(in day: HubDay, at part: DayPart) -> HubItem? {
        let waiting = day.items.filter { $0.isYours && !$0.done }
        return waiting.first { $0.part >= part } ?? waiting.first
    }
}

extension HubInputs {
    /// What's published now, or nil if the person doesn't use the hub. Every app can ask, and they all
    /// get the same day.
    public init?(shared: SharedContainer, today: Day, now: Date, timeZone: TimeZone = .current) {
        guard let rhythm = shared.read(.rhythm) else { return nil }
        self.init(
            rhythm: rhythm, changes: shared.read(.dayChanges) ?? [], profile: shared.read(.profile), lift: shared.read(.summary(.liftTrack)),
            macro: shared.read(.summary(.macroTrack)), mind: shared.read(.summary(.knowledge)), ask: shared.read(.blockAsk),
            meals: shared.read(.mealRhythm), today: today, now: now,
            timeZone: timeZone)
    }
}

extension HubPlanner {
    /// A line for each app's Today: what's left of the day, in its order. Nil with nothing left, and
    /// never more than a few things, because each app has its own screen to fill.
    public static func ahead(shared: SharedContainer, today: Day, now: Date, calendar: Calendar = .current) -> String? {
        guard let inputs = HubInputs(shared: shared, today: today, now: now) else { return nil }
        return ahead(inputs, at: DayPart(hour: calendar.component(.hour, from: now)))
    }

    static func ahead(_ inputs: HubInputs, at part: DayPart, limit: Int = 3) -> String? {
        let day = day(on: inputs.today, inputs)
        let left = day.items.filter { $0.isYours && !$0.done && $0.part >= part }.map(\.title)
        guard !left.isEmpty else { return nil }
        let shown = left.prefix(limit).joined(separator: ", ")
        return left.count > limit ? "\(shown) and \(left.count - limit) more" : shown
    }
}
