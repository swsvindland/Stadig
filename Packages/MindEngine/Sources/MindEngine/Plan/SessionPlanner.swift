import Foundation
import SystemCore

/// Everything Stadig Mind knows, for planning and analysis.
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
    /// How the study week is set up, as stored. See `week`.
    public var weekSettings: WeekSettings?
    /// What the person's week already holds, from Stadig Lift.
    public var commitments: WeekCommitments

    public init(
        settings: MindSettings, cards: [MemoryCard] = [], sessions: [StudySession] = [], tests: [TestResult] = [],
        books: [Book] = [], reflections: [Reflection] = [], pieces: [WritingPiece] = [], comparisons: [BlindComparison] = [],
        lifeModes: [LifeModePeriod] = [], calendar: SystemCalendar? = nil, recommendations: [Recommendation] = [], today: Day,
        now: Date, weekSettings: WeekSettings? = nil, commitments: WeekCommitments = .none
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
        self.weekSettings = weekSettings
        self.commitments = commitments
    }

    /// The study week: as stored, or what the courses make of it before anything has been saved.
    public var week: WeekSettings { weekSettings ?? .seeded(from: settings, since: start, now: now) }

    /// The hour on the clock a study day begins (`MindSettings.dayStart`).
    public var dayStart: Int { settings.dayStart }

    /// The study day a moment falls on: before `dayStart`, the day before's.
    public func day(_ date: Date) -> Day { Day(date, dayStartsAt: settings.dayStart) }

    /// The day study began: onboarding, or today before it.
    public var start: Day { settings.onboardedAt.map(day) ?? today }

    public var phase: StudyPhase { StudyCalendar.phase(on: today, start: start, calendar: calendar, lifeModes: lifeModes) }

    /// The last day today's phase holds (`StudyCalendar.lastDay(ofPhaseOn:)`); nil for a pause
    /// with no end set.
    public var phaseLastDay: Day? { StudyCalendar.lastDay(ofPhaseOn: today, start: start, calendar: calendar, lifeModes: lifeModes) }

    public func latest(_ kind: TestKind) -> TestResult? { tests.last { $0.test == kind } }

    /// The latest result of a test in a course (a language's own vocabulary test, say).
    public func latest(_ kind: TestKind, in domain: Domain) -> TestResult? { tests.last { $0.test == kind && $0.domain == domain } }

    /// Review cards due, across every active course: Focus and Maintenance alike.
    public func due(on day: Day) -> [MemoryCard] {
        cards.values.filter { settings.has($0.domain) && $0.isDue(on: day, dayStart: dayStart) }
    }

    /// The due cards that can be asked: their catalog is installed and their item still exists.
    /// Counts and warm-up minutes use these, so the plan matches what the reviews can show.
    public func due(on day: Day, catalogs: Catalogs) -> [MemoryCard] {
        due(on: day).filter { Subjects.module($0.domain).usable($0.key, catalogs: catalogs) }
    }

    /// The due cards of one course that can be asked: a block's own reviews.
    public func due(on day: Day, catalogs: Catalogs, in domain: Domain) -> [MemoryCard] {
        due(on: day, catalogs: catalogs).filter { $0.domain == domain }
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

    /// The last day a course was actually tested at a check-in. Starting one and ending it straight
    /// away left nothing measured, so it doesn't use up the check-in.
    public func lastCheckIn(_ domain: Domain) -> Day? {
        sessions.last { session in
            guard session.purpose == .checkIn, session.finished, session.domains.contains(domain) else { return false }
            let day = session.day(startingAt: dayStart)
            return tests.contains { $0.domain == domain && $0.day(startingAt: dayStart) == day }
        }?.day(startingAt: dayStart)
    }
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

/// Turns a block of the week into a session: the course's own reviews first, then the course. Nothing
/// new in a review week; a course's first block is its placement. Check-ins and a reviews-only
/// course's short session sit beside the blocks.
public enum SessionPlanner {
    static func reviewSeconds(_ card: MemoryCard) -> Double { Subjects.module(card.domain).reviewSeconds(card) }

    /// Lagging courses: stalled or slipping at the last check-ins, or named by the hub.
    public static func priorities(_ state: StudyState) -> Set<Domain> {
        var out: Set<Domain> = []
        let week = state.week
        let courses = state.settings.domains.filter { week.blocks($0) > 0 }
        for domain in courses {
            let trajectory = Analyst.trajectory(domain, state: state)
            if trajectory == .stalled || trajectory == .regressing { out.insert(domain) }
        }
        for recommendation in state.recommendations
        where recommendation.to == .knowledge && recommendation.isActive(at: state.now)
            && recommendation.kind == .prioritise
        {
            if case .stat(let stat) = recommendation.subject {
                out.formUnion(courses.filter { $0.stat == stat })
            }
        }
        return out
    }

    /// The next block to do today, or nil on a day with none left, a rest day or a pause.
    public static func today(_ state: StudyState, catalogs: Catalogs) -> SessionPlan? {
        guard !state.phase.isPaused else { return nil }
        let next = WeekPlanner.layout(state, settings: state.week).blocks(on: state.today).first { !$0.done }
        return next.map { block($0.domain, state: state, catalogs: catalogs) }
    }

    /// Check-ins are per course: each course's plain tests, on the days it's due one. They sit beside
    /// the week's blocks rather than in them, so a course with no blocks gets its check-in and one
    /// that's used up its blocks still does. A course with nothing to test yet isn't offered one.
    public static func checkIns(_ state: StudyState, catalogs: Catalogs) -> [SessionPlan] {
        state.settings.domains.compactMap { domain in
            guard !state.needsPlacement(domain, catalogs: catalogs),
                StudyCalendar.checkInDue(
                    on: state.today, start: state.start, calendar: state.calendar, lifeModes: state.lifeModes, lastCheckIn: state.lastCheckIn(domain))
            else { return nil }
            var plan = plan(.checkIn, domains: [domain], state: state, catalogs: catalogs)
            plan.headline = "\(domain.label) check-in · about \(plan.parts.map(\.minutes).reduce(0, +)) min"
            return plan.parts.isEmpty ? nil : plan
        }
    }

    /// Due cards at which a course with no blocks gets a short review of its own.
    public static let reviewsOnlyMinimum = 15

    /// Courses with no blocks in the week still have what's been learned to keep: a short review of
    /// that course alone when enough has come due, or their placement if they've never had one,
    /// which is how a maths or writing course on reviews only gets cards at all.
    public static func reviewsOnly(_ state: StudyState, catalogs: Catalogs) -> [SessionPlan] {
        let week = state.week
        return state.settings.domains.filter { week.blocks($0) == 0 }.compactMap { domain in
            if state.needsPlacement(domain, catalogs: catalogs) {
                var plan = block(domain, state: state, catalogs: catalogs)
                plan.planned = false
                return plan
            }
            guard state.due(on: state.today, catalogs: catalogs, in: domain).count >= reviewsOnlyMinimum else { return nil }
            var plan = plan(.extra, domains: [domain], state: state, catalogs: catalogs)
            plan.headline = "\(domain.label) reviews · \(plan.minutes) min"
            return plan
        }
    }

    /// The most of a block its warm-up takes, in a normal week and a review week.
    static let warmUpShare = 0.35
    static let reviewWeekWarmUpShare = 0.5

    /// One block of one course: its own reviews first, as many as fit in the warm-up's share, then
    /// the course itself. A course's first block is its placement instead: the test, plus new words
    /// for a language, and as long as that takes. Reading has no reviews, and takes as long as focus
    /// has held rather than the whole block.
    public static func block(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> SessionPlan {
        block(domain, kind: state.phase.isReview ? .review : .regular, state: state, catalogs: catalogs)
    }

    static func block(_ domain: Domain, kind: StudyKind, state: StudyState, catalogs: Catalogs) -> SessionPlan {
        if state.needsPlacement(domain, catalogs: catalogs) {
            var plan = plan(.placement, domains: [domain], state: state, catalogs: catalogs)
            plan.minutes = plan.parts.map(\.minutes).reduce(0, +)
            plan.headline = "\(domain.label) level · \(plan.minutes) min"
            return plan
        }
        let total = state.settings.schedule.minutes
        let review = kind == .review
        var parts: [PlanPart] = []
        var notes: [String] = []
        let due = domain == .reading ? [] : state.due(on: state.today, catalogs: catalogs, in: domain)
        let share = review ? reviewWeekWarmUpShare : warmUpShare
        let warmUp = due.isEmpty ? 0 : warmUpMinutes(due, of: total, share: share)
        if warmUp > 0 {
            parts.append(PlanPart(kind: .reviews, domain: domain, minutes: warmUp, title: "Warm-up reviews", detail: reviewDetail(due)))
        }
        parts += Subjects.module(domain).mainParts(
            domain, minutes: max(5, total - warmUp), kind: kind, state: state, catalogs: catalogs, notes: &notes)
        if review { notes.insert("Review week: nothing new. Reviews, practice and reading for pleasure.", at: 0) }
        let length = parts.map(\.minutes).reduce(0, +)
        let minutes = domain == .reading ? length : max(total, length)
        return SessionPlan(
            day: state.today, kind: kind, minutes: minutes, domains: [domain], parts: parts, headline: "\(domain.label) · \(minutes) min",
            notes: notes, planned: true)
    }

    /// Minutes of reviews: as long as the due cards take, up to a share of the session.
    static func warmUpMinutes(_ due: [MemoryCard], of total: Int, share: Double) -> Int {
        let seconds = due.map(reviewSeconds).reduce(0, +)
        return Int(min(Double(total) * share, max(1, (seconds / 60).rounded(.up))).rounded(.up))
    }

    /// A session that isn't a course's ordinary block: its check-in, its placement, or a quick review
    /// of one course or of everything due.
    public static func plan(_ kind: StudyKind, domains: [Domain], state: StudyState, catalogs: Catalogs, minutes: Int? = nil) -> SessionPlan {
        let total = minutes ?? (kind == .extra ? 5 : state.settings.schedule.minutes)
        var parts: [PlanPart] = []
        var notes: [String] = []
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
            // What's left of the first block goes to a language's first new material.
            let used = parts.map(\.minutes).reduce(0, +)
            if let language = domains.sorted().first(where: { $0.isLanguage && state.settings.mode($0)?.learns == true }), total - used >= 4 {
                parts.append(
                    LanguageModule.learnPart(
                        language, minutes: total - used, session: total - used, state: state, catalogs: catalogs, notes: &notes))
            }
            notes.append("A course's first block finds where you are, so nothing is too easy or out of reach.")
        default:
            // A quick review of one course keeps to that course.
            let scoped = domains.count == 1 ? domains.first : nil
            let due = scoped.map { state.due(on: state.today, catalogs: catalogs, in: $0) } ?? state.due(on: state.today, catalogs: catalogs)
            if !due.isEmpty {
                parts.append(
                    PlanPart(
                        kind: .reviews, domain: scoped, minutes: warmUpMinutes(due, of: total, share: 1), title: "Quick review",
                        detail: reviewDetail(due)))
            }
        }
        let minutesTotal = max(total, parts.map(\.minutes).reduce(0, +))
        let headline: String
        switch kind {
        case .checkIn: headline = "Check-in · about \(parts.map(\.minutes).reduce(0, +)) min"
        case .placement: headline = "Finding your level · \(minutesTotal) min"
        default: headline = "Quick review · \(total) min"
        }
        return SessionPlan(
            day: state.today, kind: kind, minutes: minutesTotal, domains: domains.sorted(), parts: parts, headline: headline, notes: notes,
            planned: kind != .extra)
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
