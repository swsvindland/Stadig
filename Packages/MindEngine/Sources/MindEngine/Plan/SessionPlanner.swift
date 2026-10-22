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

    public init(
        settings: MindSettings, cards: [MemoryCard] = [], sessions: [StudySession] = [], tests: [TestResult] = [],
        books: [Book] = [], reflections: [Reflection] = [], pieces: [WritingPiece] = [], comparisons: [BlindComparison] = [],
        lifeModes: [LifeModePeriod] = [], calendar: SystemCalendar? = nil, recommendations: [Recommendation] = [], today: Day,
        now: Date
    ) {
        self.settings = settings
        self.cards = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
        self.sessions = sessions.sorted { $0.start < $1.start }
        self.tests = tests.sorted { $0.date < $1.date }
        self.books = books
        self.reflections = reflections
        self.pieces = pieces.sorted { $0.date < $1.date }
        self.comparisons = comparisons.sorted { $0.date < $1.date }
        // Deleted periods travel as tombstones so the delete reaches every app; the engine never sees them.
        self.lifeModes = lifeModes.live
        self.calendar = calendar
        self.recommendations = recommendations
        self.today = today
        self.now = now
    }

    /// The day study began: onboarding, or today before it.
    public var start: Day { settings.onboardedAt.map { Day($0) } ?? today }

    public var phase: StudyPhase { StudyCalendar.phase(on: today, start: start, calendar: calendar, lifeModes: lifeModes) }

    /// The last day today's phase holds (`StudyCalendar.lastDay(ofPhaseOn:)`); nil for a pause
    /// with no end set.
    public var phaseLastDay: Day? { StudyCalendar.lastDay(ofPhaseOn: today, start: start, calendar: calendar, lifeModes: lifeModes) }

    public func latest(_ kind: TestKind) -> TestResult? { tests.last { $0.test == kind } }

    /// The latest result of a test in a course (a language's own vocabulary test, say).
    public func latest(_ kind: TestKind, in domain: Domain) -> TestResult? { tests.last { $0.test == kind && $0.domain == domain } }

    /// Review cards due, across every active course: Focus and Maintenance alike.
    public func due(on day: Day) -> [MemoryCard] {
        cards.values.filter { settings.has($0.domain) && $0.isDue(on: day) }
    }

    /// The due cards that can be asked: their catalog is installed and their item still exists.
    /// Counts and warm-up minutes use these, so the plan matches what the reviews can show.
    public func due(on day: Day, catalogs: Catalogs) -> [MemoryCard] {
        due(on: day).filter { Subjects.module($0.domain).usable($0.key, catalogs: catalogs) }
    }

    /// Whether a course still needs its placement. Main and Secondary courses place before new
    /// material. A Maintenance course places only where the placement cards what it finds known
    /// (maths, writing): reviews only of nothing would leave a course chosen as Maintenance from
    /// the start empty for good. Otherwise it keeps what's known and never places.
    public func needsPlacement(_ domain: Domain, catalogs: Catalogs) -> Bool {
        guard let mode = settings.mode(domain) else { return false }
        let module = Subjects.module(domain)
        return (mode.learns || module.placementCardsKnown) && module.needsPlacement(domain, state: self, catalogs: catalogs)
    }

    /// The English book on the go. A reader in a language being learned has its own level; see `GradedReaders`.
    public var currentBook: Book? { books.filter { $0.status == .reading && $0.language == nil }.max { $0.updatedAt < $1.updatedAt } }

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
/// included), then the day's Main courses, then a short block of one Secondary course, the
/// Secondary courses taking turns. Nothing new in a review week; tests at a check-in; placement
/// first wherever a course's level isn't known yet.
public enum SessionPlanner {
    static func reviewSeconds(_ card: MemoryCard) -> Double { Subjects.module(card.domain).reviewSeconds(card) }

    /// The Main courses studied on a day, from the weekly split. Pass `priorities` when they're
    /// already worked out; they're computed otherwise.
    public static func domains(on day: Day, state: StudyState, priorities: Set<Domain>? = nil) -> [Domain] {
        Split.week(starting: day.startOfWeek, settings: state.settings, priorities: priorities ?? self.priorities(state))[day] ?? []
    }

    /// Lagging courses: stalled or slipping at the last check-ins, or named by the hub.
    public static func priorities(_ state: StudyState) -> Set<Domain> {
        var out: Set<Domain> = []
        for domain in state.settings.focus {
            let trajectory = Analyst.trajectory(domain, state: state)
            if trajectory == .stalled || trajectory == .regressing { out.insert(domain) }
        }
        for recommendation in state.recommendations
        where recommendation.to == .knowledge && recommendation.isActive(at: state.now)
            && recommendation.kind == .prioritise
        {
            if case .stat(let stat) = recommendation.subject {
                out.formUnion(state.settings.focus.filter { $0.stat == stat })
            }
        }
        return out
    }

    /// Today's session, or nil on a rest or paused day.
    public static func today(_ state: StudyState, catalogs: Catalogs, priorities: Set<Domain>? = nil) -> SessionPlan? {
        if state.phase.isPaused { return nil }
        let placing = state.settings.domains.filter { state.needsPlacement($0, catalogs: catalogs) }
        if state.sessions.isEmpty || !placing.isEmpty && state.sessions.allSatisfy({ $0.purpose == .placement }) {
            let domains = Set(state.settings.studied + placing).sorted()
            return plan(.placement, domains: domains, state: state, catalogs: catalogs)
        }
        if StudyCalendar.checkInDue(
            on: state.today, start: state.start, calendar: state.calendar, lifeModes: state.lifeModes,
            lastCheckIn: state.lastCheckIn)
        {
            return plan(.checkIn, domains: state.settings.domains, state: state, catalogs: catalogs)
        }
        let domains = domains(on: state.today, state: state, priorities: priorities)
        guard !domains.isEmpty else { return nil }
        return plan(state.phase.isReview ? .review : .regular, domains: domains, state: state, catalogs: catalogs)
    }

    /// A session of any courses on demand: an extra one, or a different course than planned.
    public static func plan(_ kind: StudyKind, domains: [Domain], state: StudyState, catalogs: Catalogs, minutes: Int? = nil) -> SessionPlan {
        let total = minutes ?? (kind == .extra ? 5 : state.settings.schedule.minutes)
        var parts: [PlanPart] = []
        var notes: [String] = []
        let due = state.due(on: state.today, catalogs: catalogs)
        let dueSeconds = due.map(reviewSeconds).reduce(0, +)
        // The day's courses, then the Secondary course whose block it is.
        var courses = domains.sorted()

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
            // What's left of the first session goes to the first language's new material, a Main
            // one before a Secondary one.
            let used = parts.map(\.minutes).reduce(0, +)
            let languages = domains.sorted().filter { $0.isLanguage && state.settings.mode($0)?.learns == true }
            if let language = languages.first(where: { state.settings.mode($0) == .focus }) ?? languages.first, total - used >= 4 {
                parts.append(
                    LanguageModule.learnPart(
                        language, minutes: total - used, session: total - used, state: state,
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
            func minutes(_ parts: [PlanPart]) -> Int { parts.map(\.minutes).reduce(0, +) }
            // A Maintenance course with nothing learned yet places once, one a session.
            if let course = state.settings.maintenance.first(where: { state.needsPlacement($0, catalogs: catalogs) }) {
                let placement = Subjects.module(course).placementParts(course, state: state, catalogs: catalogs)
                parts += placement
                remaining = max(3, remaining - minutes(placement))
                notes.append("\(course.label) is on Maintenance with nothing learned yet: a short placement finds what you know, to keep it up.")
            }
            for domain in main where state.needsPlacement(domain, catalogs: catalogs) {
                let placement = Subjects.module(domain).placementParts(domain, state: state, catalogs: catalogs)
                parts += placement
                remaining = max(3, remaining - minutes(placement))
            }
            var block: [PlanPart] = []
            if let course = secondaryCourse(state, excluding: main, catalogs: catalogs) {
                let module = Subjects.module(course)
                if state.needsPlacement(course, catalogs: catalogs) {
                    block = module.placementParts(course, state: state, catalogs: catalogs)
                } else {
                    block = module.mainParts(
                        course, minutes: CourseLoad.secondaryMinutes(remaining), kind: kind, state: state, catalogs: catalogs, notes: &notes)
                }
                remaining = max(3, remaining - minutes(block))
                courses.append(course)
            }
            let learning = main.filter { !state.needsPlacement($0, catalogs: catalogs) }
            for (index, domain) in learning.enumerated() {
                let first = Int((Double(remaining) * 0.65).rounded())
                let share = learning.count == 1 ? remaining : (index == 0 ? first : remaining - first)
                parts += Subjects.module(domain).mainParts(domain, minutes: share, kind: kind, state: state, catalogs: catalogs, notes: &notes)
            }
            parts += block
            if kind == .review { notes.insert("Review week: nothing new. Reviews, practice and reading for pleasure.", at: 0) }
        }
        let minutesTotal = max(total, parts.map(\.minutes).reduce(0, +))
        let names = courses.map(\.label)
        let headline: String
        switch kind {
        case .checkIn: headline = "Check-in · about \(parts.map(\.minutes).reduce(0, +)) min"
        case .placement: headline = "Finding your level · \(minutesTotal) min"
        case .extra: headline = "Quick review · \(total) min"
        default: headline = "\(ListFormatter.localizedString(byJoining: names)) · \(minutesTotal) min"
        }
        return SessionPlan(
            day: state.today, kind: kind, minutes: minutesTotal, domains: courses, parts: parts, headline: headline,
            notes: notes, planned: kind != .extra)
    }

    /// The Secondary course whose turn it is for a session's block: one still to be placed first,
    /// then the one that has waited longest since a session last had it (today's left out, so the
    /// plan holds all day), ties in course order. Never one already in the session.
    static func secondaryCourse(_ state: StudyState, excluding: [Domain], catalogs: Catalogs) -> Domain? {
        let candidates = state.settings.secondary.filter { !excluding.contains($0) }
        if let unplaced = candidates.first(where: { state.needsPlacement($0, catalogs: catalogs) }) { return unplaced }
        func last(_ domain: Domain) -> Date {
            state.sessions.last { session in
                session.day < state.today && (session.purpose == .regular || session.purpose == .review) && session.domains.contains(domain)
            }?.start ?? .distantPast
        }
        return candidates.min { (last($0), $0) < (last($1), $1) }
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
