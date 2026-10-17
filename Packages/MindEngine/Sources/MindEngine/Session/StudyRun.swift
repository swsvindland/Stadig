import Foundation
import SystemCore

/// A session in progress: a pure state machine the screen drives. It hands out one step at a time
/// (a lesson, a question, the reading timer), takes the answer, schedules what was reviewed and
/// graduates what was learned. Time is whatever the screen reports, with long gaps (the phone put
/// down) left out except while reading.
public struct StudyRun: Sendable {
    public enum Step: Hashable, Sendable {
        case lesson(Lesson)
        case question(Question)
        /// No book on the go: choose one from the ladder (or add your own).
        case pickBook([LadderBook])
        case read(Book, minutes: Int)
        case reflect(Book, finished: Bool)
    }

    public struct Feedback: Hashable, Sendable {
        public var question: Question
        public var correct: Bool
        public var skipped: Bool
        public var chosen: Int?
        public var typed: String?
    }

    public let plan: SessionPlan
    public private(set) var session: StudySession
    /// Every card, with this session's changes.
    public private(set) var cards: [CardKey: MemoryCard]
    public private(set) var changedCards: Set<CardKey> = []
    public private(set) var newTests: [TestResult] = []
    public private(set) var books: [Book]
    public private(set) var changedBooks: Set<UUID> = []
    public private(set) var newReflections: [Reflection] = []
    public private(set) var step: Step?
    public private(set) var feedback: Feedback?
    public private(set) var partIndex = 0
    /// The plan's parts, plus extra practice when time is left at the end.
    public private(set) var planParts: [PlanPart]

    private var parts: [Part]
    /// Seconds for each part. Time a part doesn't use carries on to the next.
    private var budgets: [Double]
    private var partSeconds = 0.0
    private var partAttemptStart = 0
    private var stepShownAt = 0.0
    private var lastNow: Date
    private var asked = 0
    private let deck: JapaneseDeck?
    private let writing: WritingBank
    private let ladder: ReadingLadder
    private let settings: MindSettings
    private let frontier: Int
    private let today: Day

    /// Gaps longer than this (the phone put down) don't count as study, except while reading.
    static let idleCap = 90.0

    public init(plan: SessionPlan, state: StudyState, deck: JapaneseDeck?, writing: WritingBank = .standard,
                ladder: ReadingLadder = .standard, now: Date) {
        self.plan = plan
        self.deck = deck
        self.writing = writing
        self.ladder = ladder
        settings = state.settings
        frontier = JapanesePlan.frontier(state.tests)
        today = state.today
        cards = state.cards
        books = state.books
        lastNow = now
        session = StudySession(purpose: plan.kind, start: now, plannedMinutes: plan.minutes, domains: plan.domains, planned: plan.planned)
        planParts = plan.parts
        budgets = plan.parts.map { Double($0.minutes) * 60 }
        parts = []
        parts = plan.parts.map { makePart($0, state: state) }
        step = nextStep(now: now)
    }

    // MARK: Reading the state

    public var currentPart: PlanPart? { planParts[safe: partIndex] }
    public var isComplete: Bool { step == nil && feedback == nil }
    public var minutesLeft: Double { Double(plan.minutes) - session.activeSeconds / 60 }
    public var answered: [Attempt] { session.attempts }

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
        record(question, correct: question.correctChoice == index, skipped: false, chosen: index, typed: nil, now: now)
    }

    public mutating func type(_ text: String, now: Date) {
        guard case .question(let question) = step, feedback == nil else { return }
        record(question, correct: question.check(typed: text), skipped: false, chosen: nil, typed: text, now: now)
    }

    /// "Don't know" on a test, or "I haven't learned this" in a placement.
    public mutating func dontKnow(now: Date) {
        guard case .question(let question) = step, feedback == nil else { return }
        record(question, correct: false, skipped: true, chosen: nil, typed: nil, now: now)
    }

    /// On from a lesson or an answered question.
    public mutating func next(now: Date) {
        tick(now: now)
        if case .question = step, feedback == nil { return }
        feedback = nil
        step = nextStep(now: now)
    }

    /// Moves on to the next part now (out of time for this one, or not today).
    public mutating func skipPart(now: Date) {
        tick(now: now)
        feedback = nil
        guard partIndex < parts.count else { return }
        finishPart(now: now)
        partIndex += 1
        partSeconds = 0
        partAttemptStart = session.attempts.count
        step = nextStep(now: now)
    }

    public mutating func pickBook(_ book: LadderBook, now: Date) {
        addBook(book.book(status: .reading, started: today), now: now)
    }

    public mutating func addBook(_ book: Book, now: Date) {
        guard case .reading(var reading) = parts[safe: partIndex] else { return }
        tick(now: now)
        var book = book
        book.status = .reading
        book.started = book.started ?? today
        book.updatedAt = now
        books.append(book)
        changedBooks.insert(book.id)
        reading.bookID = book.id
        reading.stage = .read
        parts[partIndex] = .reading(reading)
        step = nextStep(now: now)
    }

    /// The reading timer ended: where the bookmark is now, and how it felt if it's finished.
    public mutating func finishReading(page: Int, finished: Bool, feel: BookFeel?, minutes: Double, now: Date) {
        guard case .reading(var reading) = parts[safe: partIndex], let id = reading.bookID,
              let index = books.firstIndex(where: { $0.id == id }) else { return }
        tick(now: now)
        var book = books[index]
        let from = book.page
        book.page = finished ? book.pages : clamp(page, 0, book.pages)
        if finished {
            book.status = .finished
            book.finished = today
            book.feel = feel
        }
        book.updatedAt = now
        books[index] = book
        changedBooks.insert(id)
        session.reading = ReadingLog(bookID: id, fromPage: from, toPage: book.page, minutes: minutes)
        reading.stage = .reflect
        parts[partIndex] = .reading(reading)
        step = nextStep(now: now)
    }

    /// A few sentences after reading, or nil to skip.
    public mutating func reflect(_ text: String?, now: Date) {
        guard case .reading(var reading) = parts[safe: partIndex], let id = reading.bookID else { return }
        tick(now: now)
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, let book = books.first(where: { $0.id == id }) {
            newReflections.append(Reflection(bookID: id, date: now, kind: book.status == .finished ? .book : .section, page: book.page,
                                             text: trimmed, updatedAt: now))
        }
        reading.stage = .done
        parts[partIndex] = .reading(reading)
        step = nextStep(now: now)
    }

    /// Ends the session: what was learned so far is kept, and anything taught but not yet
    /// graduated comes back tomorrow.
    public mutating func finish(now: Date) {
        tick(now: now)
        if partIndex < parts.count { finishPart(now: now) }
        partIndex = parts.count
        step = nil
        feedback = nil
        session.end = now
        session.updatedAt = now
    }

    // MARK: Answers

    private mutating func record(_ question: Question, correct: Bool, skipped: Bool, chosen: Int?, typed: String?, now: Date) {
        tick(now: now)
        let seconds = max(0.5, session.activeSeconds - stepShownAt)
        session.attempts.append(Attempt(key: question.key, kind: question.kind, correct: correct, skipped: skipped, seconds: seconds,
                                        at: now, test: question.test, band: question.band))
        session.updatedAt = now
        asked += 1
        if question.kind == .review, var card = cards[question.key], let memory = card.memory {
            let grade = Grade.from(correct: correct, seconds: seconds, expected: question.expectedSeconds)
            card.memory = Scheduler.review(memory, grade: grade, at: now)
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
            card.updatedAt = now
            save(card)
        }
        recordInPart(question, correct: correct, now: now)
        feedback = Feedback(question: question, correct: correct, skipped: skipped, chosen: chosen, typed: typed)
    }

    private mutating func save(_ card: MemoryCard) {
        cards[card.key] = card
        changedCards.insert(card.key)
    }

    /// A card leaves learning with its first memory.
    private mutating func graduate(_ key: CardKey, memory: Memory, knownBefore: Bool = false, now: Date) {
        var card = cards[key] ?? MemoryCard(key: key, introduced: now, knownBefore: knownBefore)
        card.memory = memory
        card.recent = []
        card.knownBefore = card.knownBefore || knownBefore
        card.updatedAt = now
        save(card)
    }

    // MARK: Parts

    private enum Part: Sendable {
        case reviews(Reviews)
        case japanese(JapaneseLearning)
        case sentences(Sentences)
        case topics(Topics)
        case vocabulary(Vocabulary)
        case list(QuestionList)
        case mathsPlacement(MathsPlacement, current: String?)
        case reading(ReadingPart)
        case empty
    }

    private struct Again: Sendable {
        var key: CardKey
        var after: Int
    }

    private struct Reviews: Sendable {
        var queue: [CardKey]
        var again: [Again] = []
        /// Misses per card this session: each comes round again at most twice.
        var misses: [CardKey: Int] = [:]
    }

    private struct LearnTask: Sendable {
        enum Stage: Sendable { case teach, probe, first, second }
        var item: JapanesePlan.NewItem
        var stage: Stage
        var notBefore: Int
    }

    private struct JapaneseLearning: Sendable {
        var fresh: [JapanesePlan.NewItem]
        var tasks: [LearnTask] = []
        var wrong: [CardKey: Int] = [:]
        var tick = 0
        var current: Int?
    }

    private struct Sentences: Sendable {
        var pool: [Sentence]
        var used = 0
    }

    private struct Topics: Sendable {
        var domain: Domain
        var current: String?
        var probing = false
        var probeRight = 0
        var needsLesson = false
        var visit = 0
        var done: Set<String> = []
    }

    private struct Vocabulary: Sendable {
        var band = 0
        var queue: [Question]
        var placement: Bool
    }

    private struct QuestionList: Sendable {
        var kind: TestKind
        var placement: Bool
        var queue: [Question]
    }

    private struct ReadingPart: Sendable {
        enum Stage: Sendable { case pick, read, reflect, done }
        var stage: Stage
        var bookID: UUID?
    }

    private func makePart(_ part: PlanPart, state: StudyState) -> Part {
        switch part.kind {
        case .reviews:
            let due = state.due(on: today).filter { usable($0.key) }
            // Most forgotten first; ties in key order, so a session is the same on every run.
            return .reviews(Reviews(queue: due.sorted { (retrievability($0), $0.key) < (retrievability($1), $1.key) }.map(\.key)))
        case .practice(let domain):
            // Review week: the soonest-due cards of the domain, reviewed ahead of schedule.
            let ahead = state.cards.values.filter { $0.domain == domain && $0.memory != nil && !$0.isDue(on: today) && usable($0.key) }
                .sorted { ($0.memory?.due ?? .distantFuture) < ($1.memory?.due ?? .distantFuture) }
            return .reviews(Reviews(queue: Array(ahead.prefix(60)).map(\.key)))
        case .learn(.japanese):
            guard let deck else { return .empty }
            let items = JapanesePlan.next(count: part.items, cards: Set(state.cards.keys), deck: deck,
                                          readsKana: settings.readsKana, frontier: frontier)
            return .japanese(JapaneseLearning(fresh: items))
        case .learn(.reading):
            return .empty
        case .learn(let domain):
            return .topics(Topics(domain: domain))
        case .sentences:
            return .sentences(Sentences(pool: sentencePool(state)))
        case .placement(.japanese):
            guard let deck else { return .empty }
            return .vocabulary(Vocabulary(queue: JapaneseTests.vocabulary(band: 0, deck: deck, seed: "placement"), placement: true))
        case .placement(.maths):
            return .mathsPlacement(MathsPlacement(background: settings.mathsBackground), current: nil)
        case .placement(.writing):
            let questions = writing.skills.compactMap { skill in
                writing.item(for: skill.id, seen: 0, seed: "placement").map { testQuestion(writing.question($0, kind: .test, seed: "placement"), .writing) }
            }
            return .list(QuestionList(kind: .writing, placement: true, queue: questions))
        case .placement(.reading):
            return .empty
        case .read:
            let book = state.currentBook
            return .reading(ReadingPart(stage: book == nil ? .pick : .read, bookID: book?.id))
        case .test(.vocabulary):
            guard let deck else { return .empty }
            return .vocabulary(Vocabulary(queue: JapaneseTests.vocabulary(band: 0, deck: deck, seed: today.iso), placement: false))
        case .test(.listening):
            guard let deck else { return .empty }
            return .list(QuestionList(kind: .listening, placement: false,
                                      queue: JapaneseTests.listening(deck: deck, seed: today.iso, offset: today.ordinal)))
        case .test(.maths):
            return .list(QuestionList(kind: .maths, placement: false, queue: mathsCheck(state)))
        case .test(.writing):
            var rng = SeededRandom("writing-check", today.iso)
            let skills = writing.skills.shuffled(using: &rng).prefix(10)
            let questions = skills.compactMap { skill in
                writing.item(for: skill.id, seen: today.ordinal, seed: "check").map { testQuestion(writing.question($0, kind: .test, seed: today.iso), .writing) }
            }
            return .list(QuestionList(kind: .writing, placement: false, queue: questions))
        case .test:
            return .empty
        }
    }

    private func testQuestion(_ question: Question, _ kind: TestKind) -> Question {
        var question = question
        question.test = kind
        question.allowsDontKnow = true
        return question
    }

    private func usable(_ key: CardKey) -> Bool {
        switch key.domain {
        case .japanese: key.isKana ? KanaTable.byKana[key.item] != nil : (key.wordID.flatMap { deck?.word($0) } != nil)
        case .maths: MathCurriculum.topic(key.item) != nil
        case .writing: writing.skill(key.item) != nil
        case .reading: false
        }
    }

    private func retrievability(_ card: MemoryCard) -> Double {
        card.memory.map { Scheduler.retrievability($0, at: today.date()) } ?? 0
    }

    private func sentencePool(_ state: StudyState) -> [Sentence] {
        guard let deck else { return [] }
        let known = Set(state.cards.values.filter { $0.memory != nil }.compactMap(\.key.wordID))
        let ranks = known.compactMap { deck.word($0)?.rank }
        let top = max(frontier, ranks.max() ?? 0)
        guard top >= 30 else { return [] }
        let candidates = deck.sentences(levels: 1...top, limit: 300, skip: today.ordinal)
        // Sentences of known words, with at most one new one.
        return candidates.filter { sentence in
            sentence.words.filter { id in !known.contains(id) && (deck.word(id)?.rank ?? .max) > frontier }.count <= 1
        }
    }

    private func mathsCheck(_ state: StudyState) -> [Question] {
        let known = MathsPlan.known(state.cards).compactMap(MathCurriculum.topic).sorted { $0.level > $1.level }
        var rng = SeededRandom("maths-check", today.iso)
        let picked = Array(known.prefix(5)) + Array(known.dropFirst(5).shuffled(using: &rng).prefix(3))
        return picked.enumerated().map { index, topic in
            testQuestion(topic.problem(seed: "check.\(today.iso).\(index)").question(kind: .test, id: "check.\(topic.id).\(today.iso)"), .maths)
        }
    }

    // MARK: Stepping

    private mutating func nextStep(now: Date) -> Step? {
        while partIndex < parts.count {
            if let step = nextInPart(now: now) {
                stepShownAt = session.activeSeconds
                return step
            }
            let leftover = max(0, budgets[partIndex] - partSeconds)
            finishPart(now: now)
            partIndex += 1
            partSeconds = 0
            partAttemptStart = session.attempts.count
            if partIndex < parts.count {
                budgets[partIndex] += leftover
            } else if leftover >= 120 {
                addExtraPractice(seconds: leftover)
            }
        }
        // Everything planned ran its course: the session counts in full, whatever the clock says.
        session.ranToEnd = true
        return nil
    }

    /// Time left once the plan is done goes to reviews ahead of schedule in the session's
    /// domains, so a 25-minute block stays one, unless there's nothing to review.
    private mutating func addExtraPractice(seconds: Double) {
        guard plan.kind == .regular || plan.kind == .review || plan.kind == .placement else { return }
        let domains = Set(plan.domains.filter { $0 != .reading })
        let ahead = cards.values.filter { domains.contains($0.domain) && $0.memory != nil && !$0.isDue(on: today) && usable($0.key) }
            .sorted { ($0.memory?.due ?? .distantFuture) < ($1.memory?.due ?? .distantFuture) }
        guard !ahead.isEmpty else { return }
        planParts.append(PlanPart(kind: .reviews, minutes: Int((seconds / 60).rounded()), title: "Extra practice",
                                  detail: "Reviews ahead of schedule"))
        budgets.append(seconds)
        parts.append(.reviews(Reviews(queue: Array(ahead.prefix(80)).map(\.key))))
    }

    private var budget: Double { budgets[partIndex] }

    private mutating func nextInPart(now: Date) -> Step? {
        switch parts[partIndex] {
        case .reviews(var reviews):
            let step = nextReview(&reviews)
            parts[partIndex] = .reviews(reviews)
            return step
        case .japanese(var learning):
            let step = nextJapanese(&learning, now: now)
            parts[partIndex] = .japanese(learning)
            return step
        case .sentences(var sentences):
            guard partSeconds < budget, sentences.used < sentences.pool.count else { return nil }
            let sentence = sentences.pool[sentences.used]
            sentences.used += 1
            parts[partIndex] = .sentences(sentences)
            return .question(JapaneseQuiz.sentence(sentence, kind: .learn, others: sentences.pool, seed: today.iso, key: CardKey("jp.sentences")))
        case .topics(var topics):
            let step = nextTopic(&topics, now: now)
            parts[partIndex] = .topics(topics)
            return step
        case .vocabulary(var vocabulary):
            let step = nextVocabulary(&vocabulary)
            parts[partIndex] = .vocabulary(vocabulary)
            return step
        case .list(var list):
            guard !list.queue.isEmpty, partSeconds < budget * 2.5 else { return nil }
            let question = list.queue.removeFirst()
            parts[partIndex] = .list(list)
            return .question(question)
        case .mathsPlacement(let placement, _):
            guard !placement.done, let topic = placement.nextTopic() else { return nil }
            var question = topic.problem(seed: "placement.\(placement.asked)").question(kind: .test, id: "placement.\(topic.id)")
            question.test = .mathsPlacement
            question.allowsDontKnow = true
            parts[partIndex] = .mathsPlacement(placement, current: topic.id)
            return .question(question)
        case .reading(let reading):
            switch reading.stage {
            case .pick:
                return .pickBook(ReadingPlan.suggestions(shelf: books, genres: settings.genres, ladder: ladder))
            case .read:
                guard let book = books.first(where: { $0.id == reading.bookID }) else { return nil }
                return .read(book, minutes: Int((budgets[partIndex] / 60).rounded()))
            case .reflect:
                guard let book = books.first(where: { $0.id == reading.bookID }) else { return nil }
                return .reflect(book, finished: book.status == .finished)
            case .done:
                return nil
            }
        case .empty:
            return nil
        }
    }

    private mutating func recordInPart(_ question: Question, correct: Bool, now: Date) {
        guard partIndex < parts.count else { return }
        switch parts[partIndex] {
        case .reviews(var reviews):
            for i in reviews.again.indices { reviews.again[i].after -= 1 }
            // A miss comes round again a few questions later, at most twice: it's relearned
            // today, and the schedule already brings it back tomorrow.
            if !correct {
                reviews.misses[question.key, default: 0] += 1
                reviews.again.removeAll { $0.key == question.key }
                if reviews.misses[question.key, default: 0] <= 2 { reviews.again.append(Again(key: question.key, after: 3)) }
            }
            parts[partIndex] = .reviews(reviews)
        case .japanese(var learning):
            recordJapanese(&learning, key: question.key, correct: correct, now: now)
            parts[partIndex] = .japanese(learning)
        case .topics(var topics):
            recordTopic(&topics, correct: correct, now: now)
            parts[partIndex] = .topics(topics)
        case .mathsPlacement(var placement, let current):
            if let current { placement.record(topic: current, correct: correct) }
            parts[partIndex] = .mathsPlacement(placement, current: nil)
        default:
            break
        }
    }

    private mutating func nextReview(_ reviews: inout Reviews) -> Step? {
        // A missed card comes back once a few others have gone by, or straight away at the end.
        let waiting = partSeconds >= budget || reviews.queue.isEmpty ? reviews.again.indices.first : nil
        if let ready = reviews.again.firstIndex(where: { $0.after <= 0 }) ?? waiting {
            let again = reviews.again.remove(at: ready)
            if let question = question(for: again.key, kind: .learn) { return .question(question) }
        }
        guard partSeconds < budget else { return nil }
        while !reviews.queue.isEmpty {
            let key = reviews.queue.removeFirst()
            if let question = question(for: key, kind: .review) { return .question(question) }
        }
        return nil
    }

    /// A question about a card, varied by how often it's been seen.
    private func question(for key: CardKey, kind: AttemptKind) -> Question? {
        let reps = cards[key]?.memory?.reps ?? 0
        let seed = "\(today.iso).\(asked)"
        switch key.domain {
        case .japanese:
            if key.isKana, let kana = KanaTable.byKana[key.item] {
                let introduced = KanaTable.all.filter { cards[$0.key]?.memory != nil }
                return JapaneseQuiz.question(kana, reps: reps + (kind == .learn ? 1 : 0), kind: kind, introduced: introduced, seed: seed)
            }
            guard let deck, let id = key.wordID, let word = deck.word(id) else { return nil }
            let ask = kind == .learn ? .meaning : JapaneseQuiz.ask(for: word, reps: reps)
            return JapaneseQuiz.question(word, ask: ask, kind: kind, deck: deck, seed: seed)
        case .maths:
            return MathCurriculum.topic(key.item)?.problem(seed: seed).question(kind: kind, id: "\(key.raw).\(seed)")
        case .writing:
            return writing.item(for: key.item, seen: reps + asked, seed: today.iso).map { writing.question($0, kind: kind, seed: seed) }
        case .reading:
            return nil
        }
    }

    // MARK: New Japanese

    private mutating func nextJapanese(_ learning: inout JapaneseLearning, now: Date) -> Step? {
        learning.tick += 1
        // A new item joins while fewer than four are in flight and there's time for it.
        let ready = learning.tasks.indices.filter { learning.tasks[$0].notBefore <= learning.tick }
        if ready.isEmpty, !learning.fresh.isEmpty, learning.tasks.count < 4, partSeconds < budget * 0.8 {
            let item = learning.fresh.removeFirst()
            let probe = if case .probe = item { true } else { false }
            learning.tasks.append(LearnTask(item: item, stage: probe ? .probe : .teach, notBefore: learning.tick))
        }
        let index = learning.tasks.indices.filter { learning.tasks[$0].notBefore <= learning.tick }.first
            ?? (partSeconds < budget * 1.4 ? learning.tasks.indices.min { learning.tasks[$0].notBefore < learning.tasks[$1].notBefore } : nil)
        guard let index else { return nil }
        let task = learning.tasks[index]
        learning.current = index
        switch task.stage {
        case .teach:
            learning.tasks[index].stage = .first
            learning.tasks[index].notBefore = learning.tick + 2
            return .lesson(lesson(for: task.item))
        case .probe, .first, .second:
            return question(for: task, stage: task.stage).map(Step.question)
        }
    }

    private func lesson(for item: JapanesePlan.NewItem) -> Lesson {
        switch item {
        case .kana(let kana): return .kana(kana)
        case .teach(let word), .probe(let word):
            let example = deck?.sentences(with: word.id, maxLevel: max(frontier, word.rank + 200), limit: 1).first
            return .word(word, kanji: deck?.kanji(in: word) ?? [], example: example)
        }
    }

    private func question(for task: LearnTask, stage: LearnTask.Stage) -> Question? {
        let seed = "learn.\(today.iso)"
        switch task.item {
        case .kana(let kana):
            let introduced = KanaTable.all.filter { cards[$0.key] != nil || $0.group == kana.group }
            return JapaneseQuiz.question(kana, reps: stage == .second ? 1 : 0, kind: .learn, introduced: introduced, seed: seed)
        case .teach(let word), .probe(let word):
            guard let deck else { return nil }
            let ask: JapaneseQuiz.WordAsk = stage == .second ? (word.hasKanji ? .reading : .listening) : .meaning
            return JapaneseQuiz.question(word, ask: ask, kind: stage == .probe ? .probe : .learn, deck: deck, seed: seed)
        }
    }

    private mutating func recordJapanese(_ learning: inout JapaneseLearning, key: CardKey, correct: Bool, now: Date) {
        guard let index = learning.current, learning.tasks.indices.contains(index), learning.tasks[index].item.key == key else { return }
        let task = learning.tasks[index]
        switch task.stage {
        case .probe:
            if correct {
                // Known already: back for a check in about a week.
                graduate(key, memory: Scheduler.known(stability: 7, at: now), knownBefore: true, now: now)
                learning.tasks.remove(at: index)
            } else {
                learning.tasks[index].stage = .teach
                learning.tasks[index].notBefore = learning.tick
            }
        case .first:
            if correct {
                learning.tasks[index].stage = .second
                learning.tasks[index].notBefore = learning.tick + 3
            } else {
                learning.wrong[key, default: 0] += 1
                learning.tasks[index].notBefore = learning.tick + 2
            }
        case .second:
            if correct {
                graduate(key, memory: Scheduler.first(learning.wrong[key, default: 0] == 0 ? .good : .hard, at: now), now: now)
                learning.tasks.remove(at: index)
            } else {
                learning.wrong[key, default: 0] += 1
                learning.tasks[index].notBefore = learning.tick + 2
            }
        case .teach:
            break
        }
        learning.current = nil
    }

    // MARK: Maths topics and writing skills

    private func lesson(topic id: String, domain: Domain) -> Lesson? {
        if domain == .maths, let topic = MathCurriculum.topic(id) { return .topic(topic.info, example: topic.problem(seed: "lesson")) }
        return writing.skill(id).map(Lesson.skill)
    }

    private func nextCandidate(_ topics: Topics) -> String? {
        if topics.domain == .maths {
            return (MathsPlan.inProgress(cards) + MathsPlan.frontier(cards)).map(\.id).first { !topics.done.contains($0) }
        }
        let learning = cards.values.filter { $0.domain == .writing && $0.learning }.map(\.key.item)
        let started = Set(cards.values.filter { $0.domain == .writing }.map(\.key.item))
        let fresh = writing.skills.filter { !started.contains($0.id) }.sorted { $0.level < $1.level }.map(\.id)
        return (learning + fresh).first { !topics.done.contains($0) }
    }

    private mutating func nextTopic(_ topics: inout Topics, now: Date) -> Step? {
        if topics.current == nil {
            guard partSeconds < budget * 0.8, let id = nextCandidate(topics) else { return nil }
            topics.current = id
            topics.visit = 0
            topics.probeRight = 0
            let placed = MathsPlan.placedLevel(cards)
            let level = MathCurriculum.topic(id)?.level ?? 99
            topics.probing = topics.domain == .maths && cards[.topic(id)] == nil && level <= placed
            if !topics.probing {
                var card = cards[topics.domain == .maths ? .topic(id) : .skill(id)]
                    ?? MemoryCard(key: topics.domain == .maths ? .topic(id) : .skill(id), introduced: now)
                card.recent = []
                card.updatedAt = now
                save(card)
                topics.needsLesson = true
            }
        }
        guard let id = topics.current else { return nil }
        if topics.needsLesson {
            topics.needsLesson = false
            if let lesson = lesson(topic: id, domain: topics.domain) { return .lesson(lesson) }
        }
        guard partSeconds < budget * 1.3 else {
            topics.current = nil
            return nil
        }
        let seed = "\(today.iso).\(asked)"
        let kind: AttemptKind = topics.probing ? .probe : .learn
        if topics.domain == .maths {
            return MathCurriculum.topic(id).map { .question($0.problem(seed: seed).question(kind: kind, id: "\(id).\(seed)")) }
        }
        return writing.item(for: id, seen: asked, seed: today.iso).map { .question(writing.question($0, kind: kind, seed: seed)) }
    }

    private mutating func recordTopic(_ topics: inout Topics, correct: Bool, now: Date) {
        guard let id = topics.current else { return }
        let key: CardKey = topics.domain == .maths ? .topic(id) : .skill(id)
        topics.visit += 1
        if topics.probing {
            if correct {
                topics.probeRight += 1
                if topics.probeRight >= 2 {
                    graduate(key, memory: Scheduler.known(stability: 10, at: now), knownBefore: true, now: now)
                    topics.done.insert(id)
                    topics.current = nil
                }
            } else {
                // Not known after all: teach it.
                topics.probing = false
                topics.needsLesson = true
                save(MemoryCard(key: key, recent: [false], introduced: now, updatedAt: now))
            }
            return
        }
        guard var card = cards[key] else { return }
        card.recent = Array((card.recent + [correct]).suffix(10))
        card.updatedAt = now
        save(card)
        if Mastery.mastered(card.recent) {
            graduate(key, memory: Scheduler.first(Mastery.grade(card.recent), at: now), now: now)
            topics.done.insert(id)
            topics.current = nil
        } else if Mastery.struggling(card.recent) || topics.visit >= Mastery.maximumPerVisit {
            // Set aside for today: the worked solutions have been shown, and it comes back next time.
            topics.done.insert(id)
            topics.current = nil
        }
    }

    // MARK: Tests

    private mutating func nextVocabulary(_ vocabulary: inout Vocabulary) -> Step? {
        guard let deck else { return nil }
        if vocabulary.queue.isEmpty {
            let attempts = session.attempts[partAttemptStart...].filter { $0.test == .vocabulary }
            let goOn: Bool
            if vocabulary.placement {
                goOn = JapaneseTests.continuePlacement(after: vocabulary.band, attempts: Array(attempts), deck: deck)
            } else {
                // A check-in covers every band, but stops after two that are almost all unknown.
                let last = JapaneseTests.known(attempts.filter { $0.band == vocabulary.band })
                let before = vocabulary.band > 0 ? JapaneseTests.known(attempts.filter { $0.band == vocabulary.band - 1 }) : 1
                goOn = vocabulary.band + 1 < JapaneseTests.bandsAvailable(in: deck) && !(last < 0.2 && before < 0.2)
            }
            guard goOn else { return nil }
            vocabulary.band += 1
            vocabulary.queue = JapaneseTests.vocabulary(band: vocabulary.band, deck: deck, seed: vocabulary.placement ? "placement" : today.iso)
        }
        guard !vocabulary.queue.isEmpty else { return nil }
        return .question(vocabulary.queue.removeFirst())
    }

    private mutating func finishPart(now: Date) {
        guard partIndex < parts.count else { return }
        let attempts = Array(session.attempts[min(partAttemptStart, session.attempts.count)...])
        switch parts[partIndex] {
        case .japanese(var learning):
            // Taught but not yet shown to stick: back tomorrow.
            for task in learning.tasks where task.stage == .first || task.stage == .second {
                graduate(task.item.key, memory: Scheduler.first(.again, at: now), now: now)
            }
            learning.tasks = []
            parts[partIndex] = .japanese(learning)
        case .vocabulary(let vocabulary):
            let tested = attempts.filter { $0.test == .vocabulary }
            // A placement needs at least a whole band to say anything.
            if tested.count >= JapaneseTests.wordsPerBand {
                newTests.append(JapaneseTests.result(tested, date: now, placement: vocabulary.placement))
            }
        case .list(let list):
            let tested = attempts.filter { $0.test == list.kind }
            guard tested.count >= (list.placement ? 8 : 4) else { break }
            switch list.kind {
            case .listening:
                newTests.append(JapaneseTests.listeningResult(tested, date: now))
            default:
                let right = tested.filter(\.correct)
                var detail = ["seconds": tested.map(\.seconds).reduce(0, +) / Double(tested.count), "asked": Double(tested.count)]
                if list.kind == .maths {
                    let levels = right.compactMap { MathCurriculum.topic($0.key.item)?.level }
                    detail["reach"] = Double(levels.max() ?? 0)
                    detail["level"] = Double(tested.compactMap { MathCurriculum.topic($0.key.item)?.level }.reduce(0, +)) / Double(tested.count)
                }
                newTests.append(TestResult(test: list.kind, date: now, score: Double(right.count) / Double(tested.count), detail: detail,
                                           placement: list.placement))
                if list.placement && list.kind == .writing {
                    for attempt in right where cards[attempt.key]?.memory == nil {
                        graduate(attempt.key, memory: Scheduler.known(stability: 7, at: now), knownBefore: true, now: now)
                    }
                }
            }
        case .mathsPlacement(let placement, _):
            guard placement.asked >= 6 || placement.done else { break }
            for card in placement.cards(at: now) where cards[card.key]?.memory == nil { save(card) }
            newTests.append(placement.result(at: now))
        default:
            break
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
