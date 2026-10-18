import Foundation
import SystemCore

/// A session in progress: a pure state machine the screen drives. It hands out one step at a time
/// (a lesson, a question, a passage, something to say or write, the reading timer), takes the
/// response, schedules what was reviewed and graduates what was learned. Each part of the plan is
/// run by its subject's `PartRunner`. Time is whatever the screen reports, with long gaps (the
/// phone put down) left out except while reading.
public struct StudyRun: Sendable {
    public enum Step: Hashable, Sendable {
        case lesson(Lesson)
        case question(Question)
        /// No book on the go: choose one from the ladder (or add your own).
        case pickBook([LadderBook])
        case read(Book, minutes: Int)
        case reflect(Book, finished: Bool)
        /// A reading-test passage: read it, then its questions follow.
        case passage(Passage)
        /// Say something; the app listens and responds with `.spoken`.
        case speak(SpeakingTask)
        /// Write something; the app responds with `.written`.
        case compose(WritingTask)
        /// Two pieces, unlabelled: pick the stronger with `.picked`.
        case compare(BlindPair)
    }

    public struct Feedback: Hashable, Sendable {
        public var question: Question
        public var correct: Bool
        public var skipped: Bool
        public var chosen: Int?
        public var typed: String?
    }

    public let plan: SessionPlan
    public internal(set) var session: StudySession
    /// Every card, with this session's changes.
    public internal(set) var cards: [CardKey: MemoryCard]
    public internal(set) var changedCards: Set<CardKey> = []
    public internal(set) var newTests: [TestResult] = []
    public internal(set) var books: [Book]
    public internal(set) var changedBooks: Set<UUID> = []
    public internal(set) var newReflections: [Reflection] = []
    public internal(set) var newPieces: [WritingPiece] = []
    public internal(set) var newComparisons: [BlindComparison] = []
    public private(set) var step: Step? {
        didSet { stepNumber += 1 }
    }
    /// Counts the steps handed out, so a screen can tell a new step from the same one with its
    /// feedback added: it moves each time a step is handed out (and when the run ends), never when
    /// only the feedback changes. The first step is 0.
    public private(set) var stepNumber = 0
    public internal(set) var feedback: Feedback?
    public private(set) var partIndex = 0
    /// The plan's parts, plus extra practice when time is left at the end.
    public private(set) var planParts: [PlanPart]

    private var runners: [any PartRunner]
    /// Seconds for each part. Time a part doesn't use carries on to the next.
    private var budgets: [Double]
    private(set) var partSeconds = 0.0
    private var partAttemptStart = 0
    /// A planned part was skipped before its time was up: the plan didn't run its course.
    private var skippedPart = false
    /// Extra practice comes once a run, so its reviews never repeat in rounds.
    private var addedExtraPractice = false
    private(set) var stepShownAt = 0.0
    private(set) var lastNow: Date
    private(set) var asked = 0
    let catalogs: Catalogs
    let settings: MindSettings
    let tests: [TestResult]
    let pieces: [WritingPiece]
    let today: Day

    /// Gaps longer than this (the phone put down) don't count as study, except while reading.
    static let idleCap = 90.0

    public init(plan: SessionPlan, state: StudyState, catalogs: Catalogs, now: Date) {
        self.plan = plan
        self.catalogs = catalogs
        settings = state.settings
        tests = state.tests
        pieces = state.pieces
        today = state.today
        cards = state.cards
        books = state.books
        lastNow = now
        session = StudySession(purpose: plan.kind, start: now, plannedMinutes: plan.minutes, domains: plan.domains, planned: plan.planned)
        planParts = plan.parts
        budgets = plan.parts.map { Double($0.minutes) * 60 }
        runners = []
        runners = plan.parts.map { Subjects.runner(for: $0, state: state, catalogs: catalogs) }
        step = nextStep(now: now)
    }

    // MARK: Reading the state

    public var currentPart: PlanPart? { planParts[safe: partIndex] }
    public var isComplete: Bool { step == nil && feedback == nil }
    public var minutesLeft: Double { Double(plan.minutes) - session.activeSeconds / 60 }
    public var answered: [Attempt] { session.attempts }

    /// Seconds this part may run before handing on.
    var budget: Double { budgets[safe: partIndex] ?? 0 }
    /// Attempts since this part began.
    var partAttempts: [Attempt] { Array(session.attempts[min(partAttemptStart, session.attempts.count)...]) }
    var now: Date { lastNow }
    /// Words up to here are checked rather than taught in a language. A placement earlier in this
    /// run counts, so the first session's new words start above the level it just measured.
    func frontier(_ language: Language) -> Int { LanguagePlan.frontier(tests + newTests, language) }

    // MARK: Driving it

    /// Counts the time since the last call. Call it as the clock ticks and before every action.
    public mutating func tick(now: Date) {
        let reading = if case .read = step { true } else { false }
        let delta = min(max(0, now.timeIntervalSince(lastNow)), reading ? 3 * 3600 : Self.idleCap)
        session.activeSeconds += delta
        partSeconds += delta
        lastNow = now
    }

    public mutating func choose(_ index: Int, now: Date) {
        guard case .question(let question) = step, feedback == nil else { return }
        answer(question, correct: question.correctChoice == index, skipped: false, chosen: index, typed: nil, now: now)
    }

    public mutating func type(_ text: String, now: Date) {
        guard case .question(let question) = step, feedback == nil else { return }
        answer(question, correct: question.check(typed: text), skipped: false, chosen: nil, typed: text, now: now)
    }

    /// "Don't know" on a test, or "I haven't learned this" in a placement.
    public mutating func dontKnow(now: Date) {
        guard case .question(let question) = step, feedback == nil else { return }
        answer(question, correct: false, skipped: true, chosen: nil, typed: nil, now: now)
    }

    /// On from a lesson, an answered question or any other finished step.
    public mutating func next(now: Date) {
        tick(now: now)
        if case .question = step, feedback == nil { return }
        feedback = nil
        step = nextStep(now: now)
    }

    /// On from this answered question, and only from it. A screen that moves on by itself after
    /// an answer (a test, a fluent timed problem) calls this, so it can't also skip whatever came
    /// next when Continue or skipping the part got there first.
    public mutating func next(after questionID: String, now: Date) {
        guard case .question(let question) = step, question.id == questionID, feedback != nil else { return }
        next(now: now)
    }

    /// Anything other than answering a question: a passage read, something said or written, a
    /// pick, a book. The current part handles it; the run moves on unless the part set feedback
    /// to show first.
    public mutating func respond(_ response: StepResponse, now: Date) {
        tick(now: now)
        guard partIndex < runners.count else { return }
        var runner = runners[partIndex]
        let handled = runner.respond(response, &self)
        runners[partIndex] = runner
        guard handled else { return }
        if feedback == nil { step = nextStep(now: now) }
    }

    /// Moves on to the next part now (out of time for this one, or not today).
    public mutating func skipPart(now: Date) {
        tick(now: now)
        feedback = nil
        guard partIndex < runners.count else { return }
        // A part that has used its time is over, not skipped; extra practice was never planned.
        if partIndex < plan.parts.count && partSeconds < budget { skippedPart = true }
        finishPart()
        partIndex += 1
        partSeconds = 0
        partAttemptStart = session.attempts.count
        step = nextStep(now: now)
    }

    public mutating func pickBook(_ book: LadderBook, now: Date) {
        respond(.bookPicked(book.book(status: .reading, started: today)), now: now)
    }

    public mutating func addBook(_ book: Book, now: Date) { respond(.bookPicked(book), now: now) }

    /// The reading timer ended: where the bookmark is now, how it felt if it's finished, and how
    /// focus held.
    public mutating func finishReading(page: Int, finished: Bool, feel: BookFeel?, minutes: Double, focus: ReadingFocus? = nil, now: Date) {
        respond(.readingDone(page: page, finished: finished, feel: feel, minutes: minutes, focus: focus), now: now)
    }

    /// A few sentences after reading, or nil to skip.
    public mutating func reflect(_ text: String?, now: Date) { respond(.reflection(text), now: now) }

    /// Ends the session: what was learned so far is kept, and anything taught but not yet
    /// graduated comes back tomorrow.
    public mutating func finish(now: Date) {
        tick(now: now)
        if partIndex < runners.count { finishPart() }
        partIndex = runners.count
        step = nil
        feedback = nil
        session.end = now
        session.updatedAt = now
    }

    // MARK: Answers

    private mutating func answer(_ question: Question, correct: Bool, skipped: Bool, chosen: Int?, typed: String?, now: Date) {
        tick(now: now)
        log(question.key, kind: question.kind, correct: correct, skipped: skipped, expected: question.expectedSeconds,
            test: question.test, band: question.band)
        if partIndex < runners.count {
            var runner = runners[partIndex]
            runner.record(question, correct: correct, &self)
            runners[partIndex] = runner
        }
        feedback = Feedback(question: question, correct: correct, skipped: skipped, chosen: chosen, typed: typed)
    }

    /// Logs an attempt at the current step and, for a review, schedules the card. Speaking and
    /// other non-question steps call this from their runner.
    mutating func log(_ key: CardKey, kind: AttemptKind, correct: Bool, skipped: Bool = false, expected: Double, test: TestKind? = nil,
                      band: Int? = nil) {
        let seconds = max(0.5, session.activeSeconds - stepShownAt)
        session.attempts.append(Attempt(key: key, kind: kind, correct: correct, skipped: skipped, seconds: seconds, at: lastNow,
                                        test: test, band: band))
        session.updatedAt = lastNow
        asked += 1
        guard kind == .review, var card = cards[key], let memory = card.memory else { return }
        let grade = Grade.from(correct: correct, seconds: seconds, expected: expected)
        card.memory = Scheduler.review(memory, grade: grade, at: lastNow)
        // A maths topic or writing skill missed on two reviews running wasn't mastered after
        // all: it goes back to learning, and what builds on it waits until it's mastered again.
        if card.domain == .maths || card.domain == .writing {
            if !correct && card.recent.last == false {
                card.memory = nil
                card.recent = []
            } else {
                card.recent = Array((card.recent + [correct]).suffix(Mastery.window))
            }
        }
        card.updatedAt = lastNow
        save(card)
    }

    mutating func save(_ card: MemoryCard) {
        cards[card.key] = card
        changedCards.insert(card.key)
    }

    /// A card leaves learning with its first memory.
    mutating func graduate(_ key: CardKey, memory: Memory, knownBefore: Bool = false) {
        var card = cards[key] ?? MemoryCard(key: key, introduced: lastNow, knownBefore: knownBefore)
        card.memory = memory
        card.recent = []
        card.knownBefore = card.knownBefore || knownBefore
        card.updatedAt = lastNow
        save(card)
    }

    /// A question about a card, from its subject, varied by how often it's been seen.
    func question(for key: CardKey, kind: AttemptKind) -> Question? {
        Subjects.module(key.domain).question(for: key, kind: kind, run: self)
    }

    func usable(_ key: CardKey) -> Bool { Subjects.module(key.domain).usable(key, catalogs: catalogs) }

    /// Questions vary by day and by how many have been asked.
    var seed: String { "\(today.iso).\(asked)" }

    // MARK: Stepping

    private mutating func nextStep(now: Date) -> Step? {
        while partIndex < runners.count {
            var runner = runners[partIndex]
            let step = runner.next(&self)
            runners[partIndex] = runner
            if let step {
                stepShownAt = session.activeSeconds
                return step
            }
            let leftover = max(0, budgets[partIndex] - partSeconds)
            finishPart()
            partIndex += 1
            partSeconds = 0
            partAttemptStart = session.attempts.count
            // The plan is done once its own parts are: ending during extra practice still counts.
            if partIndex == plan.parts.count { session.ranToEnd = !skippedPart }
            if partIndex < runners.count {
                budgets[partIndex] += leftover
            } else if leftover >= 120 {
                addExtraPractice(seconds: leftover)
            }
        }
        // Everything planned ran its course: the session counts in full, whatever the clock says.
        // With a part skipped it counts only on the time it took.
        session.ranToEnd = !skippedPart
        return nil
    }

    private mutating func finishPart() {
        guard partIndex < runners.count else { return }
        var runner = runners[partIndex]
        runner.finish(&self)
        runners[partIndex] = runner
    }

    /// Time left once the plan is done goes to reviews ahead of schedule in the session's
    /// courses, so a 25-minute block stays one, unless there's nothing to review. Cards answered
    /// or learned today stay out: a second review the same day would undo a miss's return
    /// tomorrow and stretch the rest for nothing.
    private mutating func addExtraPractice(seconds: Double) {
        guard !addedExtraPractice, plan.kind == .regular || plan.kind == .review || plan.kind == .placement else { return }
        let domains = Set(plan.domains.filter { $0 != .reading })
        let ahead = cards.values.filter { card in
            guard domains.contains(card.domain), let memory = card.memory, !changedCards.contains(card.key) else { return false }
            return Day(memory.lastReview) != today && !card.isDue(on: today) && usable(card.key)
        }.sorted { ($0.memory?.due ?? .distantFuture, $0.key) < ($1.memory?.due ?? .distantFuture, $1.key) }
        guard !ahead.isEmpty else { return }
        addedExtraPractice = true
        planParts.append(PlanPart(kind: .reviews, minutes: Int((seconds / 60).rounded()), title: "Extra practice",
                                  detail: "Reviews ahead of schedule"))
        budgets.append(seconds)
        runners.append(ReviewsRunner(queue: Array(ahead.prefix(80)).map(\.key)))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
