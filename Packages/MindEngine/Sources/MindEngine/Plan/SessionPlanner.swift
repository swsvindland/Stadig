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
    public var lifeModes: [LifeModePeriod]
    public var calendar: SystemCalendar?
    public var recommendations: [Recommendation]
    public var today: Day
    public var now: Date

    public init(settings: MindSettings, cards: [MemoryCard] = [], sessions: [StudySession] = [], tests: [TestResult] = [],
                books: [Book] = [], reflections: [Reflection] = [], lifeModes: [LifeModePeriod] = [], calendar: SystemCalendar? = nil,
                recommendations: [Recommendation] = [], today: Day, now: Date) {
        self.settings = settings
        self.cards = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
        self.sessions = sessions.sorted { $0.start < $1.start }
        self.tests = tests.sorted { $0.date < $1.date }
        self.books = books
        self.reflections = reflections
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

    public func due(on day: Day) -> [MemoryCard] {
        cards.values.filter { settings.has($0.domain) && $0.isDue(on: day) }
    }

    /// Whether a domain still needs its placement.
    public func needsPlacement(_ domain: Domain) -> Bool {
        guard settings.has(domain) else { return false }
        switch domain {
        case .japanese: return settings.readsKana == true && !tests.contains { $0.test == .vocabulary }
        case .maths: return !tests.contains { $0.test == .mathsPlacement }
        case .writing: return !tests.contains { $0.test == .writing }
        case .reading: return false
        }
    }

    public var currentBook: Book? { books.filter { $0.status == .reading }.max { $0.updatedAt < $1.updatedAt } }

    public var lastCheckIn: Day? { sessions.last { $0.purpose == .checkIn && $0.finished }?.day }
}

/// One part of a session, as Today lists it and the session runs it.
public struct PlanPart: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case reviews
        case placement(Domain)
        case learn(Domain)
        case sentences
        /// Review week: reviews ahead of schedule in one domain.
        case practice(Domain)
        case read
        case test(TestKind)
    }

    public var kind: Kind
    public var minutes: Int
    public var title: String
    public var detail: String
    /// New items to learn, for new Japanese.
    public var items: Int

    public init(kind: Kind, minutes: Int, title: String, detail: String, items: Int = 0) {
        self.kind = kind
        self.minutes = minutes
        self.title = title
        self.detail = detail
        self.items = items
    }

    public var id: String { "\(kind)" }

    public var domain: Domain? {
        switch kind {
        case .reviews: nil
        case .placement(let d), .learn(let d), .practice(let d): d
        case .sentences: .japanese
        case .read: .reading
        case .test(let kind): kind.domain
        }
    }
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

/// Turns a day into a session: reviews first (the warm-up), then the day's domains. Nothing new in
/// a review week; tests at a check-in; placement first wherever a level isn't known yet.
public enum SessionPlanner {
    /// Seconds a review usually takes, by what it is.
    static func reviewSeconds(_ card: MemoryCard) -> Double {
        switch card.domain {
        case .japanese: card.key.isKana ? 5 : 8
        case .maths: 55
        case .writing: 25
        case .reading: 0
        }
    }

    public static func domains(on day: Day, state: StudyState) -> [Domain] {
        Split.week(starting: day.startOfWeek, settings: state.settings, priorities: priorities(state))[day] ?? []
    }

    /// Lagging domains: stalled or slipping at the last check-ins, or named by the hub.
    public static func priorities(_ state: StudyState) -> Set<Domain> {
        var out: Set<Domain> = []
        for domain in state.settings.domains where Analyst.trajectory(domain, state: state) == .stalled
            || Analyst.trajectory(domain, state: state) == .regressing {
            out.insert(domain)
        }
        for recommendation in state.recommendations where recommendation.to == .knowledge && recommendation.isActive(at: state.now)
            && recommendation.kind == .prioritise {
            if case .stat(let stat) = recommendation.subject {
                out.formUnion(state.settings.domains.filter { $0.stat == stat })
            }
        }
        return out
    }

    /// Today's session, or nil on a rest or paused day.
    public static func today(_ state: StudyState, deck: JapaneseDeck?) -> SessionPlan? {
        if state.phase.isPaused { return nil }
        if state.sessions.isEmpty || state.settings.domains.contains(where: state.needsPlacement) && state.sessions.allSatisfy({ $0.purpose == .placement }) {
            return plan(.placement, domains: state.settings.domains, state: state, deck: deck)
        }
        if StudyCalendar.checkInDue(on: state.today, start: state.start, calendar: state.calendar, lifeModes: state.lifeModes,
                                    lastCheckIn: state.lastCheckIn) {
            return plan(.checkIn, domains: state.settings.domains, state: state, deck: deck)
        }
        let domains = domains(on: state.today, state: state)
        guard !domains.isEmpty else { return nil }
        return plan(state.phase.isReview ? .review : .regular, domains: domains, state: state, deck: deck)
    }

    /// A session of any domains on demand: an extra one, or a different domain than planned.
    public static func plan(_ kind: StudyKind, domains: [Domain], state: StudyState, deck: JapaneseDeck?, minutes: Int? = nil) -> SessionPlan {
        let total = minutes ?? (kind == .extra ? 5 : state.settings.schedule.minutes)
        var parts: [PlanPart] = []
        var notes: [String] = []
        let due = state.due(on: state.today)
        let dueSeconds = due.map(reviewSeconds).reduce(0, +)

        switch kind {
        case .checkIn:
            for domain in domains.sorted() {
                switch domain {
                case .japanese:
                    parts.append(PlanPart(kind: .test(.vocabulary), minutes: 4, title: "Vocabulary",
                                          detail: "Five words from each frequency band, with “Don't know”"))
                    if deck.map({ $0.sentences(levels: 1...500, limit: 4).count >= 4 }) ?? false {
                        parts.append(PlanPart(kind: .test(.listening), minutes: 3, title: "Listening", detail: "Ten sentences by ear, easy to hard"))
                    }
                case .maths where MathsPlan.known(state.cards).count >= 3:
                    parts.append(PlanPart(kind: .test(.maths), minutes: 7, title: "Maths", detail: "Eight problems across what you've learned"))
                case .writing:
                    parts.append(PlanPart(kind: .test(.writing), minutes: 4, title: "Writing", detail: "Ten items across every skill"))
                default: break
                }
            }
            notes.append("A plain check-in at the end of the review week. These tests are the only thing that moves Intelligence.")
        case .placement:
            if state.needsPlacement(.japanese) {
                parts.append(PlanPart(kind: .placement(.japanese), minutes: 4, title: "Japanese level",
                                      detail: "Words from common to rare until they're mostly new"))
            }
            if state.needsPlacement(.maths) {
                parts.append(PlanPart(kind: .placement(.maths), minutes: 10, title: "Maths level",
                                      detail: "About a dozen problems, stepping up and down"))
            }
            if state.needsPlacement(.writing) {
                parts.append(PlanPart(kind: .placement(.writing), minutes: 5, title: "Writing level", detail: "One item for each skill"))
            }
            let used = parts.map(\.minutes).reduce(0, +)
            if state.settings.has(.japanese), total - used >= 4 {
                parts.append(learnJapanese(minutes: total - used, session: total - used, state: state, deck: deck, notes: &notes))
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
            for domain in main where state.needsPlacement(domain) && kind != .extra {
                let minutes = domain == .maths ? 10 : domain == .writing ? 5 : 4
                parts.append(PlanPart(kind: .placement(domain), minutes: minutes, title: "\(domain.label) level", detail: "Finding where you are"))
                remaining = max(3, remaining - minutes)
            }
            guard kind != .extra else { break }
            let learning = main.filter { !state.needsPlacement($0) }
            for (index, domain) in learning.enumerated() {
                let share = learning.count == 1 ? remaining : (index == 0 ? Int((Double(remaining) * 0.65).rounded()) : remaining - Int((Double(remaining) * 0.65).rounded()))
                parts += mainParts(domain, minutes: share, kind: kind, state: state, deck: deck, notes: &notes)
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

    static func mainParts(_ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, deck: JapaneseDeck?,
                          notes: inout [String]) -> [PlanPart] {
        let reviewWeek = kind == .review
        switch domain {
        case .japanese:
            if reviewWeek {
                return [PlanPart(kind: .practice(.japanese), minutes: max(2, minutes / 2), title: "Japanese practice", detail: "Reviews ahead of schedule"),
                        PlanPart(kind: .sentences, minutes: minutes - max(2, minutes / 2), title: "Listening", detail: "Sentences made of words you know")]
            }
            let learn = learnJapanese(minutes: Int((Double(minutes) * 0.65).rounded()), session: state.settings.schedule.minutes, state: state,
                                      deck: deck, notes: &notes)
            let known = state.cards.values.filter { $0.domain == .japanese && $0.memory != nil && !$0.key.isKana }.count
            if known < 15 && JapanesePlan.frontier(state.tests) < 100 {
                var all = learn
                all.minutes = minutes
                return [all]
            }
            return [learn, PlanPart(kind: .sentences, minutes: minutes - learn.minutes, title: "Listening", detail: "Sentences made of words you know")]
        case .maths:
            if reviewWeek {
                return [PlanPart(kind: .practice(.maths), minutes: minutes, title: "Maths practice", detail: "Mixed problems from what you've learned")]
            }
            let detail: String
            if let next = MathsPlan.next(state.cards) {
                detail = state.cards[next.key]?.learning == true ? "Carrying on: \(next.title)" : "Next: \(next.title)"
            } else {
                detail = "Everything in the graph is learned: mixed practice"
            }
            return [PlanPart(kind: .learn(.maths), minutes: minutes, title: "Maths", detail: detail)]
        case .writing:
            if reviewWeek {
                return [PlanPart(kind: .practice(.writing), minutes: minutes, title: "Writing practice", detail: "Mixed items from what you've learned")]
            }
            let next = WritingPlan.next(state.cards, bank: .standard)
            return [PlanPart(kind: .learn(.writing), minutes: minutes, title: "Writing", detail: next.map { "Next: \($0.title)" } ?? "Mixed practice")]
        case .reading:
            let detail: String
            if let book = state.currentBook {
                detail = "\(book.title) · page \(book.page) of \(book.pages)"
            } else {
                detail = reviewWeek ? "Read anything you enjoy" : "Pick your next book from the ladder"
            }
            return [PlanPart(kind: .read, minutes: minutes, title: reviewWeek ? "Reading for pleasure" : "Reading", detail: detail)]
        }
    }

    /// New Japanese for a part of `minutes`, paced for a session of `session` minutes.
    static func learnJapanese(minutes: Int, session: Int, state: StudyState, deck: JapaneseDeck?, notes: inout [String]) -> PlanPart {
        let retention = JapanesePlan.retention(state.sessions, today: state.today)
        let dueWeek = state.cards.values.filter { $0.domain == .japanese && ($0.memory.map { Day($0.due) <= state.today.adding(days: 6) } ?? false) }.count
        let pace = JapanesePlan.newWords(retention: retention, dueThisWeek: dueWeek, minutes: session, reviewWeek: false)
        if let reason = pace.reason { notes.append(reason) }
        let keys = Set(state.cards.keys)
        let items = deck.map { JapanesePlan.next(count: pace.count, cards: keys, deck: $0, readsKana: state.settings.readsKana,
                                                 frontier: JapanesePlan.frontier(state.tests)) } ?? []
        let kana = items.filter { if case .kana = $0 { true } else { false } }.count
        let words = items.count - kana
        var detail = [String]()
        if kana > 0 { detail.append("\(kana) new kana") }
        if words > 0 { detail.append("\(words) new words") }
        if deck == nil { detail = ["The Japanese catalog isn't installed"] }
        return PlanPart(kind: .learn(.japanese), minutes: minutes, title: "New Japanese", detail: detail.joined(separator: ", "), items: pace.count)
    }

    static func reviewDetail(_ due: [MemoryCard]) -> String {
        var parts: [String] = []
        let words = due.filter { $0.domain == .japanese && !$0.key.isKana }.count
        let kana = due.filter(\.key.isKana).count
        let topics = due.filter { $0.domain == .maths }.count
        let skills = due.filter { $0.domain == .writing }.count
        if words > 0 { parts.append("\(words) word\(words == 1 ? "" : "s")") }
        if kana > 0 { parts.append("\(kana) kana") }
        if topics > 0 { parts.append("\(topics) maths topic\(topics == 1 ? "" : "s")") }
        if skills > 0 { parts.append("\(skills) writing skill\(skills == 1 ? "" : "s")") }
        return "\(due.count) due: " + parts.joined(separator: ", ")
    }
}
