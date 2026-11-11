import Foundation
import SystemCore

/// How the hub says things, here so the wording can be tested.
public enum HubText {
    /// "45 min", "2 hr", "1 hr 30 min".
    public static func length(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// To the nearest quarter of an hour: free time is room, not a measurement.
    public static func rough(_ minutes: Int) -> Int { (minutes + 7) / 15 * 15 }

    /// Free time is what's left. It's never named or given a clock time, only how much there is.
    public static func free(_ minutes: Int) -> String {
        guard minutes >= 30 else { return "Full" }
        return "\(length(rough(minutes))) free"
    }

    /// The same for a narrow column: "2h 30m free".
    public static func shortFree(_ minutes: Int) -> String {
        guard minutes >= 30 else { return "Full" }
        let total = rough(minutes)
        return (total % 60 == 0 ? "\(total / 60)h" : total < 60 ? "\(total)m" : "\(total / 60)h \(total % 60)m") + " free"
    }

    /// What a part of the day says on its right. Earlier parts of today have nothing left to say.
    public static func status(_ part: HubPart, isEarlier: Bool) -> String {
        if isEarlier { return "Earlier" }
        return part.isClosed ? "Out" : free(part.freeMinutes)
    }

    /// The card's heading: in this part of the day, coming up in a later one, or still there from
    /// earlier, which is no failure: it can still be done today, and if it isn't it moves on.
    public static func heading(_ item: HubItem, at part: DayPart) -> String {
        if item.part < part { return "Still today" }
        return "\(item.part == part ? "Now" : "Next"), \(item.part.label.lowercased())"
    }

    /// A line under the day's name: the room left.
    public static func summary(_ day: HubDay) -> String {
        // A day you've gone out of isn't full, and the note above it already says so.
        day.parts.contains(where: \.isClosed) && day.freeMinutes < 30 ? "" : free(day.freeMinutes)
    }

    /// A word on what's different about a day, if anything is. It never says what's been skipped or
    /// asks why.
    public static func note(on day: Day, changes: [DayChange]) -> String? {
        let tonight = changes.live.contains { $0.kind == DayChange.out && $0.day == day }
        let lighter = changes.isLighter(day.startOfWeek)
        switch (tonight, lighter) {
        case (true, true): return "Out tonight, in a lighter week. Whatever was tonight moves on."
        case (true, false): return "Out tonight. Whatever was tonight moves on."
        case (false, true): return "Lighter week, ends Sunday. A shorter gym session."
        case (false, false): return nil
        }
    }
}

extension HubItem {
    /// The button for it, if there's an app to open. Anything else passes by itself.
    public var action: String? { app.map { "Open \($0.displayName)" } }
}

/// How to open another app. Each one's scheme is its own, and a link never does more than open it:
/// the hub logs nothing.
public enum HubLink {
    public static func url(for app: AppID) -> URL? {
        switch app {
        case .liftTrack: URL(string: "lifttrack://today")
        case .macroTrack: URL(string: "macrotrack://today")
        // Stadig Mind isn't one of the family's apps any more: nothing in the hub opens it.
        case .knowledge, .hub: nil
        }
    }
}

/// A stretch of a day's bar.
public struct BarSegment: Hashable, Sendable {
    public var kind: HubItem.Kind
    public var minutes: Int

    public init(kind: HubItem.Kind, minutes: Int) {
        self.kind = kind
        self.minutes = minutes
    }
}

extension HubDay {
    /// The day in order, with each run of one kind joined up. What's missing is free.
    public var bar: [BarSegment] {
        var out: [BarSegment] = []
        for item in items {
            if out.last?.kind == item.kind {
                out[out.count - 1].minutes += item.minutes
            } else {
                out.append(BarSegment(kind: item.kind, minutes: item.minutes))
            }
        }
        return out
    }
}

/// One line of the Rhythm screen: what's known, and which app it came from. Each app stays the
/// owner of its own part, so the hub only shows them.
public struct RhythmLine: Hashable, Sendable, Identifiable {
    public var label: String
    public var value: String
    public var source: String

    public var id: String { label }

    public init(label: String, value: String, source: String) {
        self.label = label
        self.value = value
        self.source = source
    }
}

public enum RhythmSummary {
    /// Lines for the apps that have published, and nothing for those that haven't.
    public static func lines(_ inputs: HubInputs) -> [RhythmLine] {
        var out: [RhythmLine] = []
        let commitments = HubPlanner.commitments(inputs)
        let days = Weekday.allCases.map { ($0, commitments.on($0)) }
        let lifts = days.filter { $0.1.contains { $0.title == WeekCommitments.liftTitle } }
        if !lifts.isEmpty, let minutes = lifts.first?.1.first(where: { $0.title == WeekCommitments.liftTitle })?.minutes {
            out.append(
                RhythmLine(
                    label: "Gym", value: "\(list(lifts.map(\.0))), about \(HubText.length(minutes))", source: AppID.liftTrack.displayName))
        }
        var classes: [(title: String, days: [Weekday])] = []
        for (weekday, commitments) in days {
            for commitment in commitments where commitment.title != WeekCommitments.liftTitle {
                if let index = classes.firstIndex(where: { $0.title == commitment.title }) {
                    classes[index].days.append(weekday)
                } else {
                    classes.append((commitment.title, [weekday]))
                }
            }
        }
        if !classes.isEmpty {
            let value = classes.map { "\($0.title) \(list($0.days))" }.joined(separator: ", ")
            out.append(RhythmLine(label: "Classes", value: value, source: AppID.liftTrack.displayName))
        }
        if let meals = inputs.meals, HubPlanner.fresh(meals.updated, inputs), !meals.usual.isEmpty {
            let parts = meals.usual.map(\.label).joined(separator: ", ")
            out.append(RhythmLine(label: "Meals", value: parts, source: AppID.macroTrack.displayName))
        } else if let meals = inputs.meals, HubPlanner.fresh(meals.updated, inputs) {
            out.append(
                RhythmLine(label: "Meals", value: "Your usual times show up after a few days of logging", source: AppID.macroTrack.displayName))
        } else if inputs.macro.map({ HubPlanner.fresh($0.updated, inputs) }) == true {
            // It's in use, but this build of it doesn't publish meal times, or hasn't since it updated.
            out.append(RhythmLine(label: "Meals", value: "Nothing yet. Update Stadig Macro and open it once", source: AppID.macroTrack.displayName))
        }
        return out
    }

    static func list(_ weekdays: [Weekday]) -> String { weekdays.map(\.short).joined(separator: ", ") }
}

extension WorkPattern {
    /// Which week of its cycle a week is, from 0.
    public func cycleWeek(of monday: Day) -> Int {
        guard !weeks.isEmpty else { return 0 }
        let week = anchor.days(until: monday.startOfWeek) / 7
        return ((week % weeks.count) + weeks.count) % weeks.count
    }

    /// The same cycle with the week of `monday` as its `week`th. Every other Friday is only known
    /// once the person says which.
    public func settingWeek(_ week: Int, of monday: Day) -> WorkPattern {
        var moved = self
        moved.anchor = monday.startOfWeek.adding(weeks: -week)
        return moved
    }

    /// The commute each way, the first one found. Zero if there isn't one.
    public var commuteMinutes: Int {
        let days = weeks.flatMap { $0 } + overrides.keys.sorted().compactMap { overrides[$0] }
        return days.flatMap { $0 }.first { $0.kind == .commute }?.minutes ?? 0
    }

    /// Every day that has work or school gets a commute either side of it, and no other does.
    public func withCommute(_ minutes: Int) -> WorkPattern {
        func commuted(_ spans: [DaySpan]) -> [DaySpan] {
            let kept = spans.filter { $0.kind != .commute }
            let away = kept.filter { $0.kind == .work || $0.kind == .school }
            guard minutes > 0, let first = away.map(\.start).min(), let last = away.map(\.end).max() else { return kept }
            // Hours worked at home happen before leaving and after getting back, so the commute
            // pushes them out of its way rather than running over them.
            let moved = kept.map { span -> DaySpan in
                guard span.kind == .home else { return span }
                var span = span
                let early = span.end - (first - minutes)
                let late = last + minutes - span.start
                if span.end <= first, early > 0 {
                    span.start -= early
                    span.end -= early
                } else if span.start >= last, late > 0 {
                    span.start += late
                    span.end += late
                }
                return span
            }
            return [DaySpan(.commute, "Commute", from: max(0, first - minutes), to: first)] + moved + [
                DaySpan(.commute, "Commute", from: last, to: last + minutes)
            ]
        }
        var changed = self
        changed.weeks = weeks.map { $0.map(commuted) }
        changed.overrides = overrides.mapValues(commuted)
        return changed
    }
}

extension SchedulePreset {
    /// The preset a pattern is, if it's still one, whatever its commute.
    public static func matching(_ pattern: WorkPattern) -> SchedulePreset? {
        if HybridWeek(pattern) != nil { return .hybrid }
        return allCases.first { $0.pattern(anchor: pattern.anchor).withCommute(pattern.commuteMinutes) == pattern }
    }
}
