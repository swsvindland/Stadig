import Foundation
import SystemCore

/// Everything Mind Track knows, for planning and analysis.
public struct StudyState: Sendable {
    public var settings: MindSettings
    public var cards: [CardKey: MemoryCard]
    public var sessions: [StudySession]
    public var tests: [TestResult]
    public var books: [Book]
    public var reflections: [Reflection]
    public var pieces: [WritingPiece]
    public var comparisons: [BlindComparison]
    public var lifeModes: [LifeModePeriod]
    public var calendar: SystemCalendar?
    public var recommendations: [Recommendation]
    public var today: Day
    public var now: Date

    public init(settings: MindSettings, cards: [MemoryCard] = [], sessions: [StudySession] = [], tests: [TestResult] = [],
                books: [Book] = [], reflections: [Reflection] = [], pieces: [WritingPiece] = [], comparisons: [BlindComparison] = [],
                lifeModes: [LifeModePeriod] = [], calendar: SystemCalendar? = nil, recommendations: [Recommendation] = [], today: Day,
                now: Date) {
        self.settings = settings
        self.cards = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
        self.sessions = sessions.sorted { $0.start < $1.start }
        self.tests = tests.sorted { $0.date < $1.date }
        self.books = books
        self.reflections = reflections
        self.pieces = pieces.sorted { $0.date < $1.date }
        self.comparisons = comparisons.sorted { $0.date < $1.date }
        self.lifeModes = lifeModes
        self.calendar = calendar
        self.recommendations = recommendations
        self.today = today
        self.now = now
    }

    /// The day study began: onboarding, or today before it.
    public var start: Day { settings.onboardedAt.map { Day($0) } ?? today }

    public var phase: StudyPhase { StudyCalendar.phase(on: today, start: start, calendar: calendar, lifeModes: lifeModes) }

    public func latest(_ kind: TestKind) -> TestResult? { tests.last { $0.test == kind } }

    /// The latest result of a test in a course (a language's own vocabulary test, say).
    public func latest(_ kind: TestKind, in domain: Domain) -> TestResult? { tests.last { $0.test == kind && $0.domain == domain } }

    /// Review cards due, across every active course: Focus and Maintenance alike.
    public func due(on day: Day) -> [MemoryCard] {
        cards.values.filter { settings.has($0.domain) && $0.isDue(on: day) }
    }

    /// Whether a Focus course still needs its placement. Maintenance courses keep what's known
    /// and never place.
    public func needsPlacement(_ domain: Domain, catalogs: Catalogs) -> Bool {
        settings.mode(domain) == .focus && Subjects.module(domain).needsPlacement(domain, state: self, catalogs: catalogs)
    }

    public var currentBook: Book? { books.filter { $0.status == .reading }.max { $0.updatedAt < $1.updatedAt } }

    public var lastCheckIn: Day? { sessions.last { $0.purpose == .checkIn && $0.finished }?.day }
}

/// One part of a session, as Today lists it and the session runs it.
public struct PlanPart: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// Spaced reviews across every course: the warm-up, or a quick review.
        case reviews
        case placement
        /// New material.
        case learn
        /// A language's sentence practice.
        case sentences
        /// Review week: reviews ahead of schedule in one course.
        case practice
        case read
        case test(TestKind)
        /// A subject's own kind of part ("numeracy", "speaking", "franklin"), run by its module.
        case custom(String)
    }

    public var kind: Kind
    /// The course it belongs to. Nil for reviews across every course.
    public var domain: Domain?
    public var minutes: Int
    public var title: String
    public var detail: String
    /// New items to learn, for a language's new material.
    public var items: Int

    public init(kind: Kind, domain: Domain? = nil, minutes: Int, title: String, detail: String, items: Int = 0) {
        self.kind = kind
        self.domain = domain
        self.minutes = minutes
        self.title = title
        self.detail = detail
        self.items = items
    }

    public var id: String { "\(domain?.rawValue ?? "all").\(kind)" }
}

public struct SessionPlan: Hashable, Sendable {
    public var day: Day
    public var kind: StudyKind
    public var minutes: Int
    public var domains: [Domain]
    public var parts: [PlanPart]
    /// "Japanese · 25 min".
    public var headline: String
    /// Why it looks the way it does: review week, recall slipping, placement.
    public var notes: [String]
    /// Counts toward Discipline.
    public var planned: Bool
}

/// Turns a day into a session: reviews first (the warm-up, across every course, Maintenance ones
/// included), then the day's Focus courses. Nothing new in a review week; tests at a check-in;
/// placement first wherever a Focus course's level isn't known yet.
public enum SessionPlanner {
    static func reviewSeconds(_ card: MemoryCard) -> Double { Subjects.module(card.domain).reviewSeconds(card) }

    /// The Focus courses studied on a day, from the weekly split.
    public static func domains(on day: Day, state: StudyState) -> [Domain] {
        Split.week(starting: day.startOfWeek, settings: state.settings, priorities: priorities(state))[day] ?? []
    }

    /// Lagging courses: stalled or slipping at the last check-ins, or named by the hub.
    public static func priorities(_ state: StudyState) -> Set<Domain> {
        var out: Set<Domain> = []
        for domain in state.settings.focus where Analyst.trajectory(domain, state: state) == .stalled
            || Analyst.trajectory(domain, state: state) == .regressing {
            out.insert(domain)
        }
        for recommendation in state.recommendations where recommendation.to == .knowledge && recommendation.isActive(at: state.now)
            && recommendation.kind == .prioritise {
            if case .stat(let stat) = recommendation.subject {
                out.formUnion(state.settings.focus.filter { $0.stat == stat })
            }
        }
        return out
    }

    /// Today's session, or nil on a rest or paused day.
    public static func today(_ state: StudyState, catalogs: Catalogs) -> SessionPlan? {
        if state.phase.isPaused { return nil }
        let placing = state.settings.focus.contains { state.needsPlacement($0, catalogs: catalogs) }
        if state.sessions.isEmpty || placing && state.sessions.allSatisfy({ $0.purpose == .placement }) {
            return plan(.placement, domains: state.settings.focus, state: state, catalogs: catalogs)
        }
        if StudyCalendar.checkInDue(on: state.today, start: state.start, calendar: state.calendar, lifeModes: state.lifeModes,
                                    lastCheckIn: state.lastCheckIn) {
            return plan(.checkIn, domains: state.settings.domains, state: state, catalogs: catalogs)
        }
        let domains = domains(on: state.today, state: state)
        guard !domains.isEmpty else { return nil }
        return plan(state.phase.isReview ? .review : .regular, domains: domains, state: state, catalogs: catalogs)
    }

    /// A session of any courses on demand: an extra one, or a different course than planned.
    public static func plan(_ kind: StudyKind, domains: [Domain], state: StudyState, catalogs: Catalogs, minutes: Int? = nil) -> SessionPlan {
        let total = minutes ?? (kind == .extra ? 5 : state.settings.schedule.minutes)
        var parts: [PlanPart] = []
        var notes: [String] = []
        let due = state.due(on: state.today)
        let dueSeconds = due.map(reviewSeconds).reduce(0, +)

        switch kind {
        case .checkIn:
            for domain in domains.sorted() {
                parts += Subjects.module(domain).checkInParts(domain, state: state, catalogs: catalogs)
            }
            notes.append("A plain check-in at the end of the review week. These tests are the only thing that moves Intelligence.")
        case .placement:
            for domain in domains.sorted() where state.needsPlacement(domain, catalogs: catalogs) {
                parts += Subjects.module(domain).placementParts(domain, state: state, catalogs: catalogs)
            }
            // What's left of the first session goes to the first language's new material.
            let used = parts.map(\.minutes).reduce(0, +)
            if let language = domains.sorted().first(where: \.isLanguage), total - used >= 4 {
                parts.append(LanguageModule.learnPart(language, minutes: total - used, session: total - used, state: state,
                                                      catalogs: catalogs, notes: &notes))
            }
            notes.append("The first session finds where you are, so nothing is too easy or out of reach.")
        default:
            // A quick review is all reviews; otherwise they're the warm-up before the day's subjects.
            let share = kind == .extra ? 1 : kind == .review ? 0.5 : 0.35
            let warmUp = due.isEmpty ? 0 : Int(min(Double(total) * share, max(1, (dueSeconds / 60).rounded(.up))).rounded(.up))
            if warmUp > 0 {
                parts.append(PlanPart(kind: .reviews, minutes: warmUp, title: "Warm-up reviews", detail: reviewDetail(due)))
            }
            var remaining = max(kind == .extra ? 0 : 5, total - warmUp)
            let main = domains.sorted()
            guard kind != .extra else { break }
            for domain in main where state.needsPlacement(domain, catalogs: catalogs) {
                let placement = Subjects.module(domain).placementParts(domain, state: state, catalogs: catalogs)
                parts += placement
                remaining = max(3, remaining - placement.map(\.minutes).reduce(0, +))
            }
            let learning = main.filter { !state.needsPlacement($0, catalogs: catalogs) }
            for (index, domain) in learning.enumerated() {
                let first = Int((Double(remaining) * 0.65).rounded())
                let share = learning.count == 1 ? remaining : (index == 0 ? first : remaining - first)
                parts += Subjects.module(domain).mainParts(domain, minutes: share, kind: kind, state: state, catalogs: catalogs, notes: &notes)
            }
            if kind == .review { notes.insert("Review week: nothing new. Reviews, practice and reading for pleasure.", at: 0) }
        }
        let minutesTotal = max(total, parts.map(\.minutes).reduce(0, +))
        let names = domains.sorted().map(\.label)
        let headline: String
        switch kind {
        case .checkIn: headline = "Check-in · about \(parts.map(\.minutes).reduce(0, +)) min"
        case .placement: headline = "Finding your level · \(minutesTotal) min"
        case .extra: headline = "Quick review · \(total) min"
        default: headline = "\(ListFormatter.localizedString(byJoining: names)) · \(minutesTotal) min"
        }
        return SessionPlan(day: state.today, kind: kind, minutes: minutesTotal, domains: domains.sorted(), parts: parts, headline: headline,
                           notes: notes, planned: kind != .extra)
    }

    static func reviewDetail(_ due: [MemoryCard]) -> String {
        var parts: [String] = []
        for language in Domain.languages {
            let words = due.filter { $0.domain == language && !$0.key.isKana }.count
            if words > 0 { parts.append("\(words) \(language.label) word\(words == 1 ? "" : "s")") }
        }
        let kana = due.filter(\.key.isKana).count
        let topics = due.filter { $0.domain == .maths }.count
        let skills = due.filter { $0.domain == .writing }.count
        if kana > 0 { parts.append("\(kana) kana") }
        if topics > 0 { parts.append("\(topics) maths topic\(topics == 1 ? "" : "s")") }
        if skills > 0 { parts.append("\(skills) writing skill\(skills == 1 ? "" : "s")") }
        return "\(due.count) due: " + parts.joined(separator: ", ")
    }
}
