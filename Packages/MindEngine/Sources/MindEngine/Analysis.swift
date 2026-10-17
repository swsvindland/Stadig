import Foundation
import SystemCore

/// One concrete next step on Today. Every insight ends in one, or it isn't shown.
public struct MindAction: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        /// A few minutes of reviews on a rest or paused day.
        case extraReview
        case pickBook
        case stalledBook
        /// Yesterday's planned session didn't happen.
        case catchUp
        /// Watch an episode without subtitles and say how much you followed.
        case episode
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var priority: Double
}

/// A day of the week as the Plan tab shows it.
public struct StudyDay: Hashable, Sendable, Identifiable {
    public enum Status: Hashable, Sendable { case done, missed, today, planned, rest, paused }

    public var day: Day
    public var domains: [Domain]
    public var status: Status
    public var id: Int { day.ordinal }
}

public struct JapaneseSummary: Hashable, Sendable {
    public var wordsLearned: Int
    public var kanaLearned: Int
    public var vocabulary: TestResult?
    public var listening: TestResult?
    public var episodes: [TestResult]
    public var retention: Double?
}

public struct MathsSummary: Hashable, Sendable {
    public var known: Int
    public var total: Int
    public var next: MathTopic.Info?
    public var highestLevel: Int
    public var check: TestResult?
}

public struct WritingSummary: Hashable, Sendable {
    public var known: Int
    public var total: Int
    public var next: String?
    public var check: TestResult?
}

public struct ReadingSummary: Hashable, Sendable {
    public var current: Book?
    public var comfortTier: Int?
    public var targetTier: Int
    public var finished: [Book]
    public var pagesPerMinute: Double?
}

public struct MindAnalysis: Sendable {
    public var phase: StudyPhase
    public var today: SessionPlan?
    /// Finished sessions today.
    public var doneToday: [StudySession]
    public var week: [StudyDay]
    public var dueToday: Int
    public var actions: [MindAction]
    public var stats: [StatReading]
    public var discipline: DisciplineScore
    /// Weekly "what we've learned" notes while the assessment runs.
    public var learned: [String]
    public var japanese: JapaneseSummary
    public var maths: MathsSummary
    public var writing: WritingSummary
    public var reading: ReadingSummary
    public var quests: [Quest]
}

extension MathTopic {
    public struct Info: Hashable, Sendable {
        public var id: String
        public var title: String
        public var level: Int
    }
}

public enum Analyst {
    public static func analyse(_ state: StudyState, deck: JapaneseDeck?) -> MindAnalysis {
        let phase = state.phase
        let plan = SessionPlanner.today(state, deck: deck)
        let doneToday = state.sessions.filter { $0.day == state.today && $0.finished }
        let todayDone = doneToday.contains { $0.planned && $0.counts }
        let due = state.due(on: state.today)
        let discipline = discipline(state)
        let japanese = japaneseSummary(state)
        let maths = mathsSummary(state)
        let writing = writingSummary(state)
        let reading = readingSummary(state)
        var analysis = MindAnalysis(phase: phase, today: todayDone ? nil : plan, doneToday: doneToday, week: week(state),
                                    dueToday: due.count, actions: [], stats: stats(state), discipline: discipline,
                                    learned: learned(state, maths: maths, writing: writing, reading: reading), japanese: japanese,
                                    maths: maths, writing: writing, reading: reading, quests: [])
        analysis.actions = actions(state, analysis: analysis, plannedToday: plan != nil)
        analysis.quests = quests(state, analysis: analysis)
        return analysis
    }

    // MARK: Stats: only tests and finished books move them

    /// A domain's 0–100 reading from its tests, oldest first.
    public static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)] {
        switch domain {
        case .japanese:
            var listening: Double?
            var out: [(Day, Double)] = []
            for test in state.tests where test.test == .vocabulary || test.test == .listening {
                if test.test == .listening { listening = test.score * 100 }
                guard let vocabulary = state.tests.last(where: { $0.test == .vocabulary && $0.date <= test.date }) else { continue }
                let words = JapaneseTests.vocabularyScore(vocabulary.score)
                out.append((test.day, listening.map { 0.6 * words + 0.4 * $0 } ?? words))
            }
            return out
        case .maths:
            return state.tests.compactMap { test in
                switch test.test {
                case .mathsPlacement: return (test.day, min(100, 10 * (test.detail["level"] ?? 0)))
                case .maths: return (test.day, min(100, 10 * (test.detail["reach"] ?? 0) * (0.5 + 0.5 * test.score)))
                default: return nil
                }
            }
        case .writing:
            return state.tests.filter { $0.test == .writing }.map { ($0.day, $0.score * 100) }
        case .reading:
            return state.books.filter(\.done).compactMap { book in
                let day = book.finished ?? state.start
                let shelf = state.books.filter { $0.done && ($0.finished ?? state.start) <= day }
                return ReadingPlan.score(shelf).map { (day, $0) }
            }.sorted { $0.0 < $1.0 }
        }
    }

    /// Compares the last two readings: up, flat or down.
    public static func trajectory(_ domain: Domain, state: StudyState) -> Trajectory {
        let points = series(domain, state: state)
        guard points.count >= 2 else { return .notEnoughData }
        let change = points[points.count - 1].score - points[points.count - 2].score
        if change > 8 { return .ahead }
        if change > 2 { return .onPace }
        if change < -2 { return .regressing }
        return .stalled
    }

    /// The combined score's direction between the last two check-ins, over the subjects measured
    /// at both, so a subject measured for the first time doesn't read as a change.
    static func combinedTrajectory(_ domains: [Domain], state: StudyState) -> Trajectory {
        let series = Dictionary(uniqueKeysWithValues: domains.map { ($0, Analyst.series($0, state: state)) })
        let days = Set(series.values.flatMap { $0.map(\.day) }).sorted()
        guard let last = days.last, let previous = days.last(where: { $0.days(until: last) >= 7 }) else { return .notEnoughData }
        func score(_ domain: Domain, on day: Day) -> Double? { series[domain]?.last { $0.day <= day }?.score }
        let common = domains.filter { score($0, on: previous) != nil && score($0, on: last) != nil }
        guard !common.isEmpty else { return .notEnoughData }
        let change = common.map { score($0, on: last)! - score($0, on: previous)! }.reduce(0, +) / Double(common.count)
        if change > 8 { return .ahead }
        if change > 2 { return .onPace }
        if change < -2 { return .regressing }
        return .stalled
    }

    static func stats(_ state: StudyState) -> [StatReading] {
        var out: [StatReading] = []
        let intelligence = state.settings.domains.filter { $0.stat == .intelligence }
        let scored = intelligence.compactMap { domain in series(domain, state: state).last.map { (domain, $0.score) } }
        if !intelligence.isEmpty {
            let score = scored.isEmpty ? nil : scored.map(\.1).reduce(0, +) / Double(scored.count)
            let trend = combinedTrajectory(intelligence, state: state)
            let label = scored.isEmpty ? "Measured at the first placement" : scored.map { domain, _ in label(domain, state: state) }.joined(separator: " · ")
            out.append(StatReading(stat: .intelligence, score: score, label: label, trend: trend, updated: state.now))
        }
        if state.settings.has(.reading) {
            let shelf = state.books
            let finished = shelf.filter { $0.status == .finished && ($0.finished.map { $0.days(until: state.today) <= 84 } ?? false) }.count
            let comfort = ReadingPlan.comfortTier(shelf)
            out.append(StatReading(stat: .wisdom, score: ReadingPlan.score(shelf),
                                   label: comfort.map { "Comfortable at tier \($0) of 10 · \(finished) finished in 12 weeks" } ?? "Finish a book to place the ladder",
                                   trend: trajectory(.reading, state: state), updated: state.now))
        }
        return out
    }

    static func label(_ domain: Domain, state: StudyState) -> String {
        switch domain {
        case .japanese:
            let words = Int(state.latest(.vocabulary)?.score ?? 0)
            return "Japanese ~\(words.formatted()) words"
        case .maths:
            let level = Int(state.tests.last { $0.test == .maths }?.detail["reach"] ?? state.latest(.mathsPlacement)?.detail["level"] ?? 0)
            return "Maths level \(level)"
        case .writing:
            return "Writing \(Int(((state.latest(.writing)?.score ?? 0) * 100).rounded()))%"
        case .reading:
            return ""
        }
    }

    // MARK: Discipline

    /// Planned study days in the last four weeks with a session that counted. Rest days, paused
    /// days and days before starting aren't counted; today counts only once it's done.
    public static func discipline(_ state: StudyState) -> DisciplineScore {
        let window = Discipline.window(ending: state.today)
        var items: [AdherenceItem] = []
        let studyDays = Set(state.settings.schedule.studyDays)
        for day in window.days where day >= state.start && studyDays.contains(day.weekday) {
            guard StudyCalendar.pause(on: day, lifeModes: state.lifeModes) == nil else { continue }
            let done = state.sessions.contains { $0.day == day && $0.planned && $0.counts }
            if day == state.today && !done { continue }
            items.append(AdherenceItem(day: day, kind: .session, label: "Study session", done: done))
        }
        return Discipline.score(items, exempt: LifeModes.exemptDays(in: window, periods: state.lifeModes), window: window)
    }

    // MARK: The week

    static func week(_ state: StudyState) -> [StudyDay] {
        let monday = state.today.startOfWeek
        let split = Split.week(starting: monday, settings: state.settings, priorities: SessionPlanner.priorities(state))
        return (0..<7).map { offset in
            let day = monday.adding(days: offset)
            let domains = split[day] ?? []
            let done = state.sessions.contains { $0.day == day && $0.planned && $0.counts }
            let status: StudyDay.Status
            if StudyCalendar.pause(on: day, lifeModes: state.lifeModes) != nil { status = .paused }
            else if done { status = .done }
            else if domains.isEmpty { status = .rest }
            else if day == state.today { status = .today }
            else if day < state.today && day >= state.start { status = .missed }
            else { status = .planned }
            return StudyDay(day: day, domains: domains, status: status)
        }
    }

    // MARK: Summaries

    static func japaneseSummary(_ state: StudyState) -> JapaneseSummary {
        let cards = state.cards.values.filter { $0.domain == .japanese && $0.memory != nil }
        return JapaneseSummary(wordsLearned: cards.filter { !$0.key.isKana }.count, kanaLearned: cards.filter(\.key.isKana).count,
                               vocabulary: state.latest(.vocabulary), listening: state.latest(.listening),
                               episodes: state.tests.filter { $0.test == .episode },
                               retention: JapanesePlan.retention(state.sessions, today: state.today))
    }

    static func mathsSummary(_ state: StudyState) -> MathsSummary {
        let known = MathsPlan.known(state.cards)
        let next = MathsPlan.next(state.cards)
        return MathsSummary(known: known.count, total: MathCurriculum.topics.count,
                            next: next.map { MathTopic.Info(id: $0.id, title: $0.title, level: $0.level) },
                            highestLevel: known.compactMap { MathCurriculum.topic($0)?.level }.max() ?? 0,
                            check: state.tests.last { $0.test == .maths || $0.test == .mathsPlacement })
    }

    static func writingSummary(_ state: StudyState) -> WritingSummary {
        let bank = WritingBank.standard
        return WritingSummary(known: WritingPlan.known(state.cards).count, total: bank.skills.count,
                              next: WritingPlan.next(state.cards, bank: bank)?.title, check: state.latest(.writing))
    }

    static func readingSummary(_ state: StudyState) -> ReadingSummary {
        ReadingSummary(current: state.currentBook, comfortTier: ReadingPlan.comfortTier(state.books),
                       targetTier: ReadingPlan.targetTier(state.books),
                       finished: state.books.filter { $0.status == .finished }.sorted { ($0.finished ?? state.today) > ($1.finished ?? state.today) },
                       pagesPerMinute: ReadingPlan.pace(state.sessions))
    }

    // MARK: What we've learned

    static func learned(_ state: StudyState, maths: MathsSummary, writing: WritingSummary, reading: ReadingSummary) -> [String] {
        guard state.phase.isAssessment else { return [] }
        var notes: [String] = []
        if state.settings.has(.japanese) {
            if let vocabulary = state.latest(.vocabulary) {
                let words = Int(vocabulary.score)
                notes.append("Japanese: about \(words.formatted()) words known (\(JapaneseTests.level(words: Double(words)).lowercased())). Words up to there get a quick check instead of a lesson.")
            } else if state.settings.readsKana == false {
                let kana = state.cards.values.filter { $0.key.isKana && $0.memory != nil }.count
                notes.append("Japanese: \(kana) of \(KanaTable.all.count) kana in. Words start once hiragana is.")
            }
        }
        if state.settings.has(.maths), state.latest(.mathsPlacement) != nil {
            let next = maths.next.map { " Next up: \($0.title)." } ?? ""
            notes.append("Maths: solid up to level \(maths.highestLevel) of 10, \(maths.known) of \(maths.total) topics.\(next)")
        }
        if state.settings.has(.writing), let check = state.latest(.writing) {
            notes.append("Writing: \(Int((check.score * 100).rounded()))% on the first pass.\(writing.next.map { " Starting with \($0.lowercased())." } ?? "")")
        }
        if state.settings.has(.reading) {
            if let tier = reading.comfortTier {
                notes.append("Reading: comfortable at tier \(tier). The ladder suggests tier \(reading.targetTier) next.")
            }
        }
        return notes
    }

    // MARK: Actions and quests

    static func actions(_ state: StudyState, analysis: MindAnalysis, plannedToday: Bool) -> [MindAction] {
        var out: [MindAction] = []
        let due = analysis.dueToday
        if case .paused(let kind) = analysis.phase {
            if case .crunch = kind, due > 0 {
                out.append(MindAction(id: "extra", kind: .extraReview, title: "A five-minute review, if you want it",
                                      detail: "Crunch mode pauses Mind Track. \(due) reviews are waiting; nothing is expected.", priority: 1))
            }
            return out
        }
        if !plannedToday && analysis.doneToday.isEmpty && due >= 15 {
            out.append(MindAction(id: "extra", kind: .extraReview, title: "Optional: five minutes of reviews",
                                  detail: "Rest day. \(due) are due; clearing some now keeps tomorrow's warm-up short.", priority: 0.5))
        } else if due > 80 {
            out.append(MindAction(id: "pile", kind: .extraReview, title: "Clear the review pile",
                                  detail: "\(due) reviews are due. A ten-minute review session tonight clears about \(min(due, 80)).", priority: 1.5))
        }
        let yesterday = state.today.adding(days: -1)
        if let missed = analysis.week.first(where: { $0.day == yesterday && $0.status == .missed }), !plannedToday, analysis.doneToday.isEmpty {
            out.append(MindAction(id: "catch-up", kind: .catchUp, title: "Catch up on yesterday's \(ListFormatter.localizedString(byJoining: missed.domains.map(\.label)))",
                                  detail: "Today is a rest day, so there's room for it. Missing it is fine too; one day barely moves anything.", priority: 1))
        }
        if state.settings.has(.reading) {
            if let book = state.currentBook {
                let lastRead = state.sessions.last { $0.reading?.bookID == book.id }?.day ?? book.started ?? state.today
                if lastRead.days(until: state.today) >= 14 {
                    out.append(MindAction(id: "stalled-book", kind: .stalledBook, title: "Still reading \(book.title)?",
                                          detail: "Nothing logged for two weeks. Read twenty pages tonight, or set it aside and pick another from the ladder.", priority: 0.8))
                }
            } else if !state.phase.isAssessment || !state.sessions.isEmpty {
                let picks = ReadingPlan.suggestions(shelf: state.books, genres: state.settings.genres).map(\.title)
                if !picks.isEmpty {
                    out.append(MindAction(id: "pick-book", kind: .pickBook, title: "Pick your next book",
                                          detail: "The ladder suggests \(ListFormatter.localizedString(byJoining: picks)).", priority: 0.7))
                }
            }
        }
        if state.settings.has(.japanese), analysis.phase.isReview,
           !state.tests.contains(where: { $0.test == .episode && $0.day.days(until: state.today) < 7 }) {
            out.append(MindAction(id: "episode", kind: .episode, title: "Watch an episode without subtitles",
                                  detail: "Review week: something you enjoy, in Japanese, just for fun. Afterwards, say how much you followed.", priority: 0.6))
        }
        return out.sorted { $0.priority > $1.priority }
    }

    /// Study that didn't happen, offered to the hub for free time blocks.
    static func quests(_ state: StudyState, analysis: MindAnalysis) -> [Quest] {
        var out: [Quest] = []
        if let plan = analysis.today {
            let stat: StatKind = plan.domains == [.reading] ? .wisdom : .intelligence
            out.append(Quest(id: "mind.session.\(state.today.iso)", title: plan.headline, detail: plan.parts.map(\.title).joined(separator: ", "),
                             stat: stat, source: .knowledge, minutes: plan.minutes, day: state.today, timeOfDay: .evening, priority: 2))
        }
        if analysis.dueToday > 40 {
            out.append(Quest(id: "mind.reviews.\(state.today.iso)", title: "Clear \(min(analysis.dueToday, 60)) reviews",
                             detail: "About ten minutes in Mind Track", stat: .intelligence, source: .knowledge, minutes: 10, day: state.today,
                             priority: 1))
        }
        if let book = analysis.reading.current, analysis.today?.domains.contains(.reading) != true {
            out.append(Quest(id: "mind.read.\(state.today.iso)", title: "Read 20 pages of \(book.title)", stat: .wisdom, source: .knowledge,
                             minutes: 30, day: state.today, timeOfDay: .evening, priority: 0.8))
        }
        if analysis.actions.contains(where: { $0.kind == .episode }) {
            out.append(Quest(id: "mind.episode.\(state.today.iso)", title: "Watch an episode in Japanese without subtitles",
                             detail: "Just for fun, then note how much you followed", stat: .intelligence, source: .knowledge, minutes: 25,
                             day: state.today, timeOfDay: .evening, priority: 0.5))
        }
        return out
    }

    // MARK: Publishing

    /// What Mind Track publishes for the hub: stats, the last four weeks of sessions in the shared
    /// format, discipline and quests.
    public static func appSummary(_ state: StudyState, _ analysis: MindAnalysis) -> AppSummary {
        let since = state.today.adding(days: -27)
        let sessions = state.sessions.filter { $0.finished && $0.day >= since }.map { session -> SessionSummary in
            let attempts = session.attempts
            var metrics: [String: Double] = ["questions": Double(attempts.count)]
            if !attempts.isEmpty { metrics["accuracy"] = Double(attempts.filter(\.correct).count) / Double(attempts.count) }
            if let reading = session.reading { metrics["pages"] = Double(reading.pages) }
            return SessionSummary(id: session.id, app: .knowledge, kind: .study, start: session.start, minutes: Int(session.minutes.rounded()),
                                  metrics: metrics, planned: session.planned)
        }
        return AppSummary(app: .knowledge, updated: state.now, stats: analysis.stats, sessions: sessions, quests: analysis.quests,
                          discipline: analysis.discipline)
    }
}
