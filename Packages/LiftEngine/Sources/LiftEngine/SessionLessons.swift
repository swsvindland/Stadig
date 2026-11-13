import ExerciseLibrary
import Foundation
import SystemCore

// What a finished session taught, for its summary: what the next session with each lift will ask of
// it and why, how the rests went, and how the ratings held up. Next time is read from the planner
// itself (`SessionPlanner`, and through it `Progression`), never worked out a second way, so the
// summary can't promise what the next session won't do.

// MARK: - Next time

public enum NextTime {
    /// One of the program's sessions after today's: its day of the program, the training day it
    /// falls on, and how many sessions come before it that week (which spaces rep-outs).
    struct Upcoming {
        var day: PlannedDay
        var date: Day
        var indexInWeek: Int
    }

    /// The program's sessions after today's, one turn of the rotation from `next`, each on the next
    /// training day, as This week lays them out.
    static func upcoming(after next: NextSession, trainingDays: [Weekday], today: Day) -> [Upcoming] {
        let days = next.mesocycle.days
        guard !days.isEmpty, !trainingDays.isEmpty else { return [] }
        var result: [Upcoming] = []
        var perWeek: [Day: Int] = [today.startOfWeek: next.doneThisWeek]
        var date = next.scheduledToday ? today : today.adding(days: 1)
        while result.count < days.count {
            if trainingDays.contains(date.weekday) {
                let week = date.startOfWeek
                let before = perWeek[week, default: 0]
                perWeek[week] = before + 1
                result.append(Upcoming(day: days[(next.dayIndex + result.count) % days.count], date: date, indexInWeek: before))
            }
            date = date.adding(days: 1)
        }
        return result
    }

    /// Each exercise's item in the first session after today's that has it, planned as the planner
    /// will plan that day on the day it falls (its week of the block, a deload included). `context`
    /// is today's, with today's sets in its history. An exercise the rest of the block doesn't have
    /// again, or only after the block ends (when the next one isn't planned yet), has none.
    public static func items(
        for exerciseIDs: [String], after next: NextSession, trainingDays: [Weekday], today: Day, context: PlanningContext
    ) -> [String: PlannedItem] {
        var wanted = Set(exerciseIDs)
        var found: [String: PlannedItem] = [:]
        for upcoming in upcoming(after: next, trainingDays: trainingDays, today: today) where !wanted.isEmpty {
            if next.mesocycle.block.week(of: upcoming.date) == .after { break }
            var context = context
            context.sessionIndexInWeek = upcoming.indexInWeek
            let plan = SessionPlanner.plan(upcoming.day, of: next.mesocycle, on: upcoming.date, context: context)
            for item in plan.items where item.isStrength && wanted.contains(item.exerciseID) {
                found[item.exerciseID] = item
                wanted.remove(item.exerciseID)
            }
        }
        return found
    }

    /// Each of a finished session's lifts in the next session that has it, planned from what's known
    /// with the session saved (`state` and its `analysis`), as Today will plan that day.
    public static func items(after record: SessionRecord, state: LiftState, analysis: LiftAnalysis) -> [String: PlannedItem] {
        guard let next = analysis.next else { return [:] }
        var context = PlanningContext(
            catalog: state.catalog, gym: state.gym, profile: state.profile, settings: state.settings, trust: analysis.trust,
            phase: analysis.phase, life: analysis.life, history: analysis.history, bodyweightKg: state.effectiveBodyweight,
            enduranceScore: analysis.endurance.score, sessionIndexInWeek: 0)
        context.heat = analysis.heat
        return items(
            for: record.exercises.map(\.exerciseID), after: next, trainingDays: state.profile.schedule.trainingDays, today: state.today,
            context: context)
    }
}

// MARK: - Rests

/// How a session's rests went against the rests the plan set: each one between two work sets of an
/// exercise, outside supersets (where the partner's set fills the rest). Warm-ups rest a breather of
/// their own, so the rest before the first work set isn't one of them.
public struct RestReview: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        /// The rest the plan set, in seconds.
        public var planned: Int
        /// The rest taken: from the set before to this one, less the time doing this one.
        public var taken: Int
        /// Whether heart rate came back down (`Rest.recovered`) before the planned rest was up: nil
        /// without readings in the rest, or when heart rate doesn't guide it (heavy compounds).
        public var recoveredEarly: Bool?
        /// The set after it came out as asked: not missed, and the reps it asked for.
        public var setOnTarget: Bool

        public init(planned: Int, taken: Int, recoveredEarly: Bool?, setOnTarget: Bool) {
            self.planned = planned
            self.taken = taken
            self.recoveredEarly = recoveredEarly
            self.setOnTarget = setOnTarget
        }
    }

    public var rests: [Entry]

    /// A rest this many seconds under the plan ran short: a step of the timer's −15.
    static let shortBy = 15
    /// A rest this many seconds over the plan ran long.
    static let longBy = 60

    public init(rests: [Entry]) {
        self.rests = rests
    }

    /// From the session as it finished: each exercise's rest plan, the rests its sets record, and the
    /// heart rate the Watch sent, read as `LiveSession.record(heartRate:)` reads it while resting.
    public init(session: LiveSession, zones: HeartRateZones) {
        let samples = session.heartRateSamples
        var rests: [Entry] = []
        for item in session.items where item.plan.isStrength && item.plan.supersetGroup == nil && item.plan.rest.target > 0 {
            let plan = item.plan.rest
            let logged = item.loggedSets.sorted { $0.date < $1.date }
            for (before, set) in zip(logged, logged.dropFirst()) where before.kind.countsAsWork && set.kind.countsAsWork {
                // Counted from the set before's log to this one's, less doing this set (`SetFatigue`).
                var timed = set
                if timed.restBeforeSeconds == nil { timed.restBeforeSeconds = Int(set.date.timeIntervalSince(before.date)) }
                let taken = SetFatigue.rest(before: timed)
                let end = before.date.addingTimeInterval(TimeInterval(taken))
                let during = samples.filter { $0.date > before.date && $0.date <= end }
                var recovered: Bool?
                if plan.heartRateGuided, !during.isEmpty {
                    // Where the set began, as the rest took it when it started.
                    let preSet = samples.last { $0.date <= before.date.addingTimeInterval(-30) }?.bpm
                    recovered = during.contains { reading in
                        let elapsed = Int(reading.date.timeIntervalSince(before.date))
                        return elapsed < plan.target
                            && Rest.recovered(heartRate: reading.bpm, preSet: preSet, zones: zones, elapsed: elapsed, plan: plan)
                    }
                }
                // A rep-out asks for all there is, so whatever it got was on target.
                let onTarget = set.kind == .repOut || (set.rating != .red && set.reps >= (set.targetReps ?? 0))
                rests.append(Entry(planned: plan.target, taken: taken, recoveredEarly: recovered, setOnTarget: onTarget))
            }
        }
        self.rests = rests
    }

    public var short: [Entry] { rests.filter { $0.taken + Self.shortBy <= $0.planned } }
    public var long: [Entry] { rests.filter { $0.taken >= $0.planned + Self.longBy } }

    /// The one thing the rests say, if they say anything: short rests the sets after were fine with,
    /// more of them than not (with heart rate, it came back down early); short rests that cost the
    /// set after, as many as not; or rests running long, half of them or more. Two rests at least, so
    /// one long drink of water isn't a lesson.
    var lesson: SessionLesson? {
        let short = self.short
        let ready = short.filter(\.setOnTarget)
        let cost = short.count - ready.count
        let of = "of \(rests.count) rests"
        if ready.count >= 2, ready.count > cost {
            let recovered = ready.filter { $0.recoveredEarly == true }.count
            let detail =
                if recovered == ready.count {
                    "Heart rate recovered early on \(ready.count) \(of)"
                } else if recovered == 0 {
                    "You went before the timer on \(ready.count) \(of), reps on target"
                } else {
                    "Ready before the timer on \(ready.count) \(of)"
                }
            return SessionLesson(kind: .rest, tone: .accent, title: "Rest ran short and you were ready", detail: detail)
        }
        if cost >= 2 {
            return SessionLesson(
                kind: .rest, tone: .accent, title: "Short rests cost reps",
                detail: "\(cost) of the \(short.count) sets after a short rest fell short")
        }
        let long = self.long
        if long.count >= 2, 2 * long.count >= rests.count {
            let over = long.map { $0.taken - $0.planned }.reduce(0, +) / long.count
            return SessionLesson(
                kind: .rest, tone: .accent, title: "Rest ran long",
                detail: "Over the timer by \(over / 60):\(String(format: "%02d", over % 60)) on average, on \(long.count) \(of)")
        }
        return nil
    }
}

// MARK: - Lessons

/// One thing a session taught, as the summary lists it: a line, what's behind it, and a dot in what
/// it means.
public struct SessionLesson: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        /// Heavier next time (less help on an assisted lift).
        case up
        /// The same weight next time.
        case held
        /// Lighter next time, without a miss behind it.
        case down
        /// A set fell short: what next time does about it, or that it will.
        case missed
        case rest
        case ratings
        /// A working weight found by finding-weight sets.
        case found
    }

    /// The dot: green for up and found, amber for held, red for a miss, the accent for rest.
    public enum Tone: String, Hashable, Sendable {
        case good, ok, bad, accent
    }

    public var kind: Kind
    public var tone: Tone
    public var title: String
    public var detail: String
    public var exerciseID: String?

    public init(kind: Kind, tone: Tone, title: String, detail: String, exerciseID: String? = nil) {
        self.kind = kind
        self.tone = tone
        self.title = title
        self.detail = detail
        self.exerciseID = exerciseID
    }

    public var id: String { "\(kind.rawValue)-\(exerciseID ?? "")" }
}

public enum SessionLessons {
    /// The summary's card holds three or four.
    public static let limit = 4

    /// What the session taught, most important first, at most `limit`:
    ///
    /// 1. a main lift's miss and what next time does about it
    /// 2. a main lift's load moving next time
    /// 3. a working weight found
    /// 4. a main lift held (the first one only)
    /// 5. the rests
    /// 6. an accessory's miss
    /// 7. ratings that were off
    /// 8. an accessory's load moving
    /// 9. ratings that were right on
    ///
    /// `next` is each exercise's item in the next session that has it (`NextTime.items`); a lift
    /// without one (the block ends first, or next time is the deload) says nothing about next time.
    /// `plan` is today's, for what each lift was asked. Bodyweight and timed work have no load to
    /// move, and a deload's sets never set the next session's weights, so neither gets a load line.
    public static func lessons(
        record: SessionRecord, plan: SessionPlan?, next: [String: PlannedItem], rest: RestReview?, catalog: ExerciseCatalog,
        unit: WeightUnit
    ) -> [SessionLesson] {
        var ranked: [(rank: Int, lesson: SessionLesson)] = []
        let names = names(record, catalog: catalog)
        var heldShown = false
        var order: [String] = []
        for log in record.exercises where !order.contains(log.exerciseID) { order.append(log.exerciseID) }
        for id in order {
            let exercise = catalog.resolve(id)
            let name = names[id] ?? exercise.name
            let sets = record.exercises.filter { $0.exerciseID == id }.flatMap(\.sets).filter { $0.kind.countsAsWork && $0.reps > 0 }
            guard !sets.isEmpty else { continue }
            let today = plan?.items.first { item in
                item.exerciseID == id || record.exercises.contains { $0.exerciseID == id && $0.slotID != nil && $0.slotID == item.slotID }
            }
            let main = (today?.role ?? next[id]?.role) == .main
            if sets.contains(where: { $0.kind == .findingWeight }) {
                if let working = sets.last(where: { $0.rating == .orange }) {
                    ranked.append(
                        (
                            2,
                            SessionLesson(
                                kind: .found, tone: .good, title: "\(name): working weight found",
                                detail: "\(load(working.loadKg, basis: exercise.loadBasis, unit: unit)) for \(working.reps)", exerciseID: id)
                        ))
                } else if sets.contains(where: { $0.rating == .red }) {
                    ranked.append((main ? 0 : 5, missedSet(name, id: id)))
                }
                continue
            }
            if !record.deload, let item = next[id],
                let lesson = loadLesson(name: name, exercise: exercise, sets: sets, today: today, next: item, unit: unit)
            {
                switch lesson.kind {
                case .missed: ranked.append((main ? 0 : 5, lesson))
                case .up, .down: ranked.append((main ? 1 : 7, lesson))
                case .held where main && !heldShown:
                    heldShown = true
                    ranked.append((3, lesson))
                default: break
                }
            } else if sets.contains(where: { $0.rating == .red }) {
                ranked.append((main ? 0 : 5, missedSet(name, id: id)))
            }
        }
        if let lesson = rest?.lesson { ranked.append((4, lesson)) }
        if let ratings = ratings(record, catalog: catalog) { ranked.append((ratings.tone == .good ? 8 : 6, ratings)) }
        // A stable sort: within a rank, the order the session went in.
        return Array(ranked.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element.lesson).prefix(limit))
    }

    /// What next time does with a lift's load, and why: up, held or down against the heaviest sets
    /// today (the ones the progression builds on), or held or down after a miss. When the weight went
    /// up during the session (an easy first set) and next time starts between where today started and
    /// where it ended, it's set against today's start: next time starts heavier than today did. Nil
    /// for work with no load to move, and when next time isn't a loading session (a deload, or still
    /// finding a weight).
    static func loadLesson(
        name: String, exercise: Exercise, sets: [LoggedSet], today: PlannedItem?, next: PlannedItem, unit: WeightUnit
    ) -> SessionLesson? {
        let basis = exercise.loadBasis
        guard basis != .none, !exercise.timed, next.mode == .load || next.mode == .reps,
            let asked = next.workSets.first, let nextKg = asked.loadKg
        else { return nil }
        func effective(_ set: LoggedSet) -> Double { OneRepMax.effectiveLoad(set.loadKg, basis: basis, bodyweightKg: set.bodyweightKg) }
        guard let top = sets.max(by: { effective($0) < effective($1) }), let first = sets.min(by: { $0.date < $1.date }) else { return nil }
        // Bodyweight with nothing added has no load to move: its reps climb instead.
        if basis == .bodyweightPlus, top.loadKg <= 0, nextKg <= 0 { return nil }
        let topSets = sets.filter { abs($0.loadKg - top.loadKg) < 0.01 }
        let bestReps = topSets.map(\.reps).max() ?? top.reps
        let reds = topSets.filter { $0.rating == .red }
        // In the units the gym loads, to the hundredth, so 140 lb read back from kilograms is 140.
        func heavier(_ delta: Double) -> Bool { basis == .assisted ? delta < 0 : delta > 0 }
        let delta = shown(nextKg, unit) - shown(top.loadKg, unit)
        let id = exercise.id

        if abs(delta) < 0.005 {
            let ask = sameWeight(asked: asked.targetReps, best: bestReps, mode: reds.isEmpty ? next.mode : nil)
            let today = "\(ask) · \(setsLine(topSets, basis: basis, unit: unit))"
            if !reds.isEmpty { return SessionLesson(kind: .missed, tone: .bad, title: "\(name) held after a miss", detail: today, exerciseID: id) }
            return SessionLesson(kind: .held, tone: .ok, title: "\(name) held", detail: today, exerciseID: id)
        }
        if heavier(delta) {
            return SessionLesson(
                kind: .up, tone: .good, title: moved(name, by: delta, basis: basis, unit: unit),
                detail:
                    "\(upReason(topSets, best: bestReps, reds: reds, today: today, next: next)) · \(change(from: top.loadKg, to: nextKg, basis: basis, unit: unit))",
                exerciseID: id)
        }
        // Lighter than today's heaviest. After a climb within the session, set against the start.
        let fromStart = shown(nextKg, unit) - shown(first.loadKg, unit)
        if reds.isEmpty, heavier(shown(top.loadKg, unit) - shown(first.loadKg, unit)), !heavier(-fromStart) {
            let peak = "up to \(load(top.loadKg, basis: basis, unit: unit)) today"
            if abs(fromStart) < 0.005 {
                return SessionLesson(
                    kind: .held, tone: .ok, title: "\(name) held",
                    detail: "Starts at \(load(first.loadKg, basis: basis, unit: unit)) again · \(peak)",
                    exerciseID: id)
            }
            return SessionLesson(
                kind: .up, tone: .good, title: moved(name, by: fromStart, basis: basis, unit: unit, start: true),
                detail: "\(peak.prefix(1).uppercased() + peak.dropFirst()) · \(change(from: first.loadKg, to: nextKg, basis: basis, unit: unit))",
                exerciseID: id)
        }
        let numbers = change(from: top.loadKg, to: nextKg, basis: basis, unit: unit)
        if !reds.isEmpty {
            return SessionLesson(
                kind: .missed, tone: .bad, title: moved(name, by: delta, basis: basis, unit: unit),
                detail: "\(fellShort(reds.count, of: topSets.count)) · \(numbers)", exerciseID: id)
        }
        return SessionLesson(
            kind: .down, tone: .ok, title: moved(name, by: delta, basis: basis, unit: unit),
            detail: "A little lighter, for \(asked.targetReps) with \(asked.targetRIR.formatted()) in hand · \(numbers)", exerciseID: id)
    }

    /// "Row moves up 2.5 kg next time", "Squat comes down 5 kg next time", "Bench press starts 2.5 kg
    /// heavier next time"; an assisted lift's help: "Assisted Pull-Up: 5 kg less help next time".
    static func moved(_ name: String, by delta: Double, basis: LoadBasis, unit: WeightUnit, start: Bool = false) -> String {
        let amount = "\(number(abs(delta))) \(unit.symbol)"
        if basis == .assisted { return "\(name): \(amount) \(delta < 0 ? "less" : "more") help \(start ? "to start " : "")next time" }
        if start { return "\(name) starts \(amount) \(delta > 0 ? "heavier" : "lighter") next time" }
        return "\(name) \(delta > 0 ? "moves up" : "comes down") \(amount) next time"
    }

    /// Why the load goes up, as the progression has it: double progression moves the weight only at
    /// the top of the range; otherwise the estimate does, from how the sets went.
    static func upReason(_ topSets: [LoggedSet], best: Int, reds: [LoggedSet], today: PlannedItem?, next: PlannedItem) -> String {
        if next.mode == .reps, best >= next.repRange.upper { return "\(best) reps, the top of the range" }
        if topSets.allSatisfy({ $0.rating == .green }) { return "\(every(topSets.count)) felt easy" }
        if let red = reds.first {
            if reds.count == 1, red == topSets.last { return "Only the last set fell short" }
            return "\(fellShort(reds.count, of: topSets.count)); the rest held"
        }
        if let beat = beyond(topSets) { return beat }
        if let before = today?.workSets.first?.targetRIR, let after = next.workSets.first?.targetRIR, after < before {
            return "The block asks a little more next week"
        }
        return "\(every(topSets.count)) on target"
    }

    /// What a held lift asks next time: double progression's extra reps, or the reps it aims for
    /// (after a miss, `mode` is nil: the target, not a rep more).
    static func sameWeight(asked: Int, best: Int, mode: ProgressionMode?) -> String {
        let more = asked - best
        guard mode == .reps, more > 0 else { return "Same weight, aim for \(asked)" }
        return more == 1 ? "Same weight, one more rep" : "Same weight, \(spelled(more)) more reps"
    }

    /// Sets that went past their target reps: "The last set went 3 reps past the target".
    static func beyond(_ sets: [LoggedSet]) -> String? {
        let beat = sets.filter { set in set.targetReps.map { set.reps > $0 } ?? false }
        guard let first = beat.first, let target = first.targetReps else { return nil }
        if beat.count > 1 {
            return "\(beat.count == sets.count ? every(sets.count) : spelled(beat.count).capitalized + " sets") went past the target"
        }
        let which = first == sets.last && sets.count > 1 ? "The last set" : (first == sets.first && sets.count > 1 ? "The first set" : "One set")
        let extra = first.reps - target
        return "\(sets.count == 1 ? "The set" : which) went \(extra) \(extra == 1 ? "rep" : "reps") past the target"
    }

    /// "A set fell short", "Two sets fell short", "All three sets fell short".
    static func fellShort(_ count: Int, of total: Int) -> String {
        if count == total { return "\(every(total)) fell short" }
        return count == 1 ? "A set fell short" : "\(spelled(count).capitalized) sets fell short"
    }

    /// "The set", "Both sets", "All three sets".
    static func every(_ count: Int) -> String {
        switch count {
        case 1: "The set"
        case 2: "Both sets"
        default: "All \(spelled(count)) sets"
        }
    }

    static func spelled(_ count: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(count) ? words[count] : "\(count)"
    }

    /// The lesson a miss gets when there's nothing to say about next time.
    static func missedSet(_ name: String, id: String) -> SessionLesson {
        SessionLesson(kind: .missed, tone: .bad, title: "\(name): a missed set", detail: "That's data; next time adjusts", exerciseID: id)
    }

    /// Whether the ratings matched what the sets after them showed (`Calibration`).
    static func ratings(_ record: SessionRecord, catalog: ExerciseCatalog) -> SessionLesson? {
        let checks = record.exercises.flatMap { Calibration.observations(sets: $0.sets, exercise: catalog.resolve($0.exerciseID)) }
        guard !checks.isEmpty else { return nil }
        let counted = "\(checks.count) rating check\(checks.count == 1 ? "" : "s") this session"
        if checks.allSatisfy({ $0.error == 0 }) {
            return SessionLesson(kind: .ratings, tone: .good, title: "Your ratings were right on", detail: counted)
        }
        if checks.contains(where: { $0.error > 0 }) {
            return SessionLesson(
                kind: .ratings, tone: .accent, title: "You had more left than you said", detail: "\(counted) · the next sets push a little to confirm"
            )
        }
        return SessionLesson(
            kind: .ratings, tone: .ok, title: "You had less left than you said", detail: "\(counted) · estimates stay conservative for now")
    }

    /// Each lift as Progress names what it scores ("Row", "Overhead press") when it's that score's own
    /// lift and no other lift in the session shares the name; otherwise its own name.
    static func names(_ record: SessionRecord, catalog: ExerciseCatalog) -> [String: String] {
        let ids = Set(record.exercises.map(\.exerciseID))
        let short = Dictionary(
            uniqueKeysWithValues: ids.map { id in
                (id, catalog.resolve(id).strength.flatMap { $0.factor == 1 ? $0.category.label : nil })
            })
        return Dictionary(
            uniqueKeysWithValues: ids.map { id in
                let name = short[id].flatMap { label in short.values.filter { $0 == label }.count == 1 ? label : nil }
                return (id, name ?? catalog.resolve(id).name)
            })
    }

    // MARK: Loads in words

    static func shown(_ kg: Double, _ unit: WeightUnit) -> Double { (unit.fromKilograms(kg) * 100).rounded() / 100 }

    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }

    /// "40 kg", "24 kg each", "+10 kg", "30 kg assist".
    static func load(_ kg: Double, basis: LoadBasis, unit: WeightUnit) -> String {
        let value = number(shown(kg, unit))
        switch basis {
        case .bodyweightPlus: return kg <= 0 ? "Bodyweight" : "+\(value) \(unit.symbol)"
        case .assisted: return "\(value) \(unit.symbol) assist"
        case .perHand: return "\(value) \(unit.symbol) each"
        case .external, .none: return "\(value) \(unit.symbol)"
        }
    }

    /// "60 → 62.5 kg", "24 → 26 kg each", "+10 → +12.5 kg", "30 → 25 kg assist".
    static func change(from: Double, to: Double, basis: LoadBasis, unit: WeightUnit) -> String {
        let after = load(to, basis: basis, unit: unit)
        let before = basis == .bodyweightPlus && from > 0 ? "+\(number(shown(from, unit)))" : number(shown(from, unit))
        return basis == .bodyweightPlus && from <= 0 ? "Bodyweight → \(after)" : "\(before) → \(after)"
    }

    /// "40 kg × 6, 6, 6".
    static func setsLine(_ sets: [LoggedSet], basis: LoadBasis, unit: WeightUnit) -> String {
        guard let first = sets.first else { return "" }
        return "\(load(first.loadKg, basis: basis, unit: unit)) × \(sets.map { "\($0.reps)" }.joined(separator: ", "))"
    }
}
