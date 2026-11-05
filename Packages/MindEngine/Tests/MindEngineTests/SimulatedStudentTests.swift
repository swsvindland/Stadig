import Foundation
import SystemCore
import Testing

@testable import MindEngine

@Suite("Simulated students")
struct SimulatedStudentTests {
    let deck = Fixtures.deck()

    @Test("each course's first block finds its level, and a language's goes on to teach the first words")
    func firstSession() throws {
        var store = Store(settings: Fixtures.settings([.japanese, .maths, .writing]))
        var student = Student(vocabulary: 1200, mathsLevel: 5, writingLevel: 1, deck: deck)
        let catalogs = Fixtures.catalogs(deck)
        var runs: [Domain: StudyRun] = [:]
        for (index, domain) in [Domain.japanese, .maths, .writing].enumerated() {
            let state = store.state(on: Fixtures.monday, at: 18 + Double(index))
            let plan = SessionPlanner.block(domain, state: state, catalogs: catalogs)
            #expect(plan.kind == .placement)
            #expect(plan.domains == [domain])
            let expected = domain == .japanese ? ["placement japanese", "learn japanese"] : ["placement \(domain.rawValue)"]
            #expect(plan.parts.map { "\($0.kind) \($0.domain?.rawValue ?? "")" } == expected)
            var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
            _ = student.run(&run, from: state.now)
            store.save(run)
            runs[domain] = run
        }
        let run = try #require(runs[.japanese])

        let vocabulary = try #require(store.tests.first { $0.test == .vocabulary })
        #expect(vocabulary.placement)
        #expect(vocabulary.score > 700 && vocabulary.score < 1900, "true 1,200, estimated \(vocabulary.score)")

        let placement = try #require(store.tests.first { $0.test == .mathsPlacement })
        let known = MathsPlan.known(store.cards)
        let levels = known.compactMap { MathCurriculum.topic($0)?.level }
        #expect(levels.max() ?? 0 >= 4 && levels.max() ?? 0 <= 6, "placed at \(placement.detail), topics \(known.sorted())")
        #expect(known.contains("order-of-operations") && known.contains("factorising"), "\(known.sorted())")
        #expect(
            (4...6).contains(MathsPlan.placedLevel(store.cards, strand: .classic)) && store.tests.contains { $0.test == .numeracy && $0.placement })
        #expect(!known.contains("derivatives") && !known.contains("integration"))

        let writing = try #require(store.tests.first { $0.test == .writing })
        #expect(writing.placement && writing.score > 0.2)
        #expect(!WritingPlan.known(store.cards).isEmpty)

        // Words below the level the placement just measured were checked, not taught; the block
        // was a real sitting.
        let words = store.cards.values.filter { $0.key.wordID != nil }
        #expect(!words.isEmpty)
        var firstAsked: [CardKey: AttemptKind] = [:]
        for attempt in run.session.attempts where attempt.key.wordID != nil && attempt.kind != .test && firstAsked[attempt.key] == nil {
            firstAsked[attempt.key] = attempt.kind
        }
        #expect(!firstAsked.isEmpty)
        for (key, kind) in firstAsked {
            let id = try #require(key.wordID)
            let rank = try #require(deck.word(id)).rank
            #expect(kind == (rank <= Int(vocabulary.score) ? .probe : .learn), "word \(rank) first asked as \(kind), placed at \(vocabulary.score)")
        }
        #expect(run.session.minutes > 2 && run.session.minutes < 40, "\(run.session.minutes) minutes")
        #expect(SessionPlanner.today(store.state(on: Fixtures.monday.adding(days: 1)), catalogs: Fixtures.catalogs(deck))?.kind == .regular)
    }

    @Test("someone who can't read kana learns words from the first session with hiragana beside them, and practises from the second")
    func kanaBesideWords() throws {
        var store = Store(settings: Fixtures.settings([.japanese], readsKana: false))
        var student = Student(vocabulary: 0, mathsLevel: 0, writingLevel: 0, deck: deck)
        let plan = try #require(SessionPlanner.today(store.state(on: Fixtures.monday), catalogs: Fixtures.catalogs(deck)))
        let learn = try #require(plan.parts.first { $0.kind == .learn })
        #expect(learn.detail.contains("kana") && learn.detail.contains("words"), "\(learn.detail)")
        store.study(on: Fixtures.monday, student: &student, deck: deck)
        let words = store.cards.keys.filter { $0.wordID != nil }
        #expect(words.count >= LanguageModule.practiceFrom, "\(words.count) words in the first session")
        #expect(store.cards.keys.contains { $0.isKana })
        #expect(store.cards.keys.filter(\.isKana).allSatisfy { KanaTable.byKana[$0.item]?.script == .hiragana })

        // The next Japanese day says, hears and writes what the first one taught.
        var practised = false
        for offset in 1..<5 where !practised {
            if let run = store.study(on: Fixtures.monday.adding(days: offset), student: &student, deck: deck) {
                practised = run.plan.parts.contains { $0.kind == .sentences }
            }
        }
        #expect(practised)
        // Kana keep coming in until hiragana is done, then katakana.
        for offset in 5..<42 { store.study(on: Fixtures.monday.adding(days: offset), student: &student, deck: deck) }
        #expect(LanguagePlan.kanaIntroduced(.hiragana, cards: Set(store.cards.keys)))
        #expect(store.cards.keys.contains { $0.isKana && KanaTable.byKana[$0.item]?.script == .katakana })
    }

    @Test("a word's reading isn't asked of someone still on the first hiragana: listening asks it again instead")
    func noReadingBeforeKana() throws {
        let store = Store(settings: Fixtures.settings([.japanese], readsKana: false))
        let state = store.state(on: Fixtures.monday)
        let plan = try #require(SessionPlanner.today(state, catalogs: Fixtures.catalogs(deck)))
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        var now = state.now
        var asked: [String] = []
        var steps = 0
        while let step = run.step, steps < 500 {
            steps += 1
            now += 5
            if case .question(let question) = step, let index = question.correctChoice {
                if question.key.wordID != nil { asked.append(question.instruction) }
                run.choose(index, now: now)
            }
            run.next(now: now)
        }
        #expect(asked.contains("What did you hear?"), "a kanji word's second ask: \(asked)")
        #expect(!asked.contains("How is it read?"))
    }

    @Test("seven weeks: the assessment, five weeks of learning, a review week with nothing new, then a check-in")
    func sevenWeeks() throws {
        var store = Store(settings: Fixtures.settings())
        var student = Student(vocabulary: 300, mathsLevel: 4, writingLevel: 1, deck: deck)
        var kinds: [Day: StudyKind] = [:]
        var newDuringReview = 0
        for offset in 0..<(7 * 7 + 3) {
            let day = Fixtures.monday.adding(days: offset)
            let before = store.cards.count
            for run in store.studyAll(on: day, student: &student, deck: deck) {
                kinds[day] = run.plan.kind
                if run.plan.kind == .review {
                    #expect(!run.plan.parts.contains { if case .learn = $0.kind { true } else { false } }, "nothing new in a review week")
                }
            }
            if kinds[day] == .review { newDuringReview += store.cards.count - before }
        }
        let state = store.state(on: Fixtures.monday.adding(days: 51))
        // Days 0–13 assessment, then weeks 1–5 loading (days 14–48), review days 49–55.
        #expect(StudyCalendar.phase(on: Fixtures.monday.adding(days: 13), start: state.start, calendar: nil, lifeModes: []).isAssessment)
        #expect(state.phase.isReview)
        #expect(newDuringReview == 0)
        #expect(kinds.values.contains(.review))

        let words = store.cards.values.filter { $0.key.wordID != nil && $0.memory != nil }.count
        #expect(words > 150, "\(words) words learned")
        let topics = MathsPlan.known(store.cards).count
        let placed = store.cards.values.filter { $0.domain == .maths && $0.knownBefore }.count
        #expect(topics > placed + 3, "\(topics) maths topics known, \(placed) from placement")
        #expect(store.books.contains { $0.status == .reading } && !store.reflections.isEmpty)

        // Check-ins on the last days of the review week, a course at a time.
        var checkIns: [StudyRun] = []
        for offset in 52...56 { checkIns += store.takeCheckIns(on: Fixtures.monday.adding(days: offset), student: &student, deck: deck) }
        #expect(checkIns.allSatisfy { $0.plan.domains.count == 1 })
        let kindsTested = Set(checkIns.flatMap(\.newTests).map(\.test))
        #expect(kindsTested.isSuperset(of: [.vocabulary, .listening, .maths, .writing]), "\(kindsTested)")
        #expect(checkIns.allSatisfy { run in run.changedCards.allSatisfy { store.cards[$0]?.memory != nil } }, "tests don't schedule")

        let final = store.state(on: Fixtures.monday.adding(days: 57))
        let analysis = Analyst.analyse(final, catalogs: Fixtures.catalogs(deck))
        let intelligence = try #require(analysis.stats.first { $0.stat == .intelligence })
        #expect(intelligence.score != nil)
        #expect(analysis.discipline.band == .inZone || analysis.discipline.band == .above, "\(analysis.discipline)")
        let summary = Analyst.appSummary(final, analysis)
        #expect(summary.app == .knowledge && !summary.sessions.isEmpty && summary.sessions.allSatisfy { $0.kind == .study })
        #expect(
            StudyCalendar.checkInDue(on: final.today, start: final.start, calendar: nil, lifeModes: [], lastCheckIn: final.lastCheckIn(.japanese))
                == false)
    }

    @Test("a wrong review comes round again in the same session without being rescheduled twice")
    func relearn() throws {
        var store = Store(settings: Fixtures.settings([.japanese]))
        let now = Fixtures.monday.date()
        let word = try #require(deck.word(100_500))
        var card = MemoryCard(key: word.key, memory: Scheduler.first(.good, at: now.addingTimeInterval(-10 * 86_400)), introduced: now)
        card.memory!.due = now.addingTimeInterval(-86_400)
        store.cards[word.key] = card
        store.tests = [TestResult(test: .vocabulary, date: now, score: 100)]
        store.sessions = [StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.japanese], planned: true)]
        let state = store.state(on: Fixtures.monday.adding(days: 1))
        let plan = SessionPlanner.plan(.extra, domains: [], state: state, catalogs: Fixtures.catalogs(deck))
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        guard case .question(let first) = run.step else {
            Issue.record("no question")
            return
        }
        run.choose((first.correctChoice! + 1) % first.choices.count, now: state.now + 5)
        let after = try #require(run.cards[word.key]?.memory)
        #expect(after.lapses == 1 && Day(after.due) == state.today.adding(days: 1))
        run.next(now: state.now + 7)
        guard case .question(let again) = run.step else {
            Issue.record("not asked again")
            return
        }
        #expect(again.key == word.key && again.kind == .learn)
        run.choose(again.correctChoice!, now: state.now + 12)
        #expect(run.cards[word.key]?.memory == after, "the re-ask doesn't touch the schedule")
    }
}

extension SimulatedStudentTests {
    /// A Japanese learner on day 40 with one card due today and a dozen due later.
    func reviewState() throws -> (state: StudyState, due: CardKey, ahead: [CardKey]) {
        let today = Fixtures.monday.adding(days: 40)
        let now = today.date().addingTimeInterval(18 * 3600)
        var cards: [MemoryCard] = []
        let dueWord = try #require(deck.word(100_050))
        cards.append(
            MemoryCard(
                key: dueWord.key, memory: Memory(stability: 30, difficulty: 5, lastReview: now - 30 * 86_400, due: now - 3600),
                introduced: now - 60 * 86_400))
        var ahead: [CardKey] = []
        for rank in 100...111 {
            let word = try #require(deck.word(100_000 + rank))
            ahead.append(word.key)
            cards.append(
                MemoryCard(
                    key: word.key, memory: Memory(stability: 10, difficulty: 5, lastReview: now - 3 * 86_400, due: now + Double(rank - 95) * 86_400),
                    introduced: now - 20 * 86_400))
        }
        let state = StudyState(
            settings: Fixtures.settings([.japanese]), cards: cards,
            sessions: [
                StudySession(
                    purpose: .placement, start: Fixtures.monday.date(), end: Fixtures.monday.date(), plannedMinutes: 25,
                    domains: [.japanese], planned: true)
            ],
            tests: [TestResult(test: .vocabulary, date: Fixtures.monday.date(), score: 500, language: .japanese)], today: today, now: now)
        return (state, dueWord.key, ahead)
    }

    @Test("extra practice at the end leaves today's cards alone, so a miss still comes back tomorrow, and comes only once")
    func extraPractice() throws {
        let (state, missed, ahead) = try reviewState()
        let plan = SessionPlan(
            day: state.today, kind: .regular, minutes: 10, domains: [.japanese],
            parts: [PlanPart(kind: .reviews, minutes: 5, title: "Warm-up reviews", detail: "")], headline: "", notes: [], planned: true)
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        var now = state.now
        var reviewed: [CardKey] = []
        var extraKeys: [CardKey] = []
        var steps = 0
        while case .question(let question) = run.step, steps < 200 {
            steps += 1
            now += 4
            if run.partIndex >= plan.parts.count { extraKeys.append(question.key) }
            if question.kind == .review { reviewed.append(question.key) }
            // The due card is missed in the warm-up; everything else is right.
            let wrong = question.key == missed && reviewed.count == 1 && question.kind == .review
            run.choose(wrong ? (question.correctChoice! + 1) % question.choices.count : question.correctChoice!, now: now)
            now += 1
            run.next(now: now)
        }
        #expect(run.isComplete)
        #expect(run.planParts.count == plan.parts.count + 1 && run.planParts.last?.title == "Extra practice", "\(run.planParts.map(\.title))")
        #expect(!extraKeys.isEmpty && !extraKeys.contains(missed), "the missed card isn't reviewed ahead of schedule the same day")
        #expect(Set(extraKeys).isSubset(of: Set(ahead)))
        #expect(reviewed.count == Set(reviewed).count, "nothing is reviewed twice in a session: \(reviewed)")
        let memory = try #require(run.cards[missed]?.memory)
        #expect(Day(memory.due) == state.today.adding(days: 1), "a miss comes back tomorrow")
        #expect(run.session.ranToEnd)
    }

    @Test("ending during extra practice: the plan ran its course, so the session counts")
    func endDuringExtraPractice() throws {
        let (state, _, _) = try reviewState()
        let plan = SessionPlan(
            day: state.today, kind: .regular, minutes: 25, domains: [.japanese],
            parts: [PlanPart(kind: .reviews, minutes: 5, title: "Warm-up reviews", detail: "")], headline: "", notes: [], planned: true)
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        guard case .question(let first) = run.step else {
            Issue.record("no warm-up question")
            return
        }
        run.choose(first.correctChoice!, now: state.now + 4)
        run.next(now: state.now + 5)
        #expect(run.partIndex == plan.parts.count && run.currentPart?.title == "Extra practice")
        run.finish(now: state.now + 60)
        #expect(run.session.ranToEnd && run.session.counts, "a minute in, after everything planned")
    }

    @Test("a review week's practice leaves a card answered earlier today alone")
    func reviewWeekPractice() throws {
        var (state, _, ahead) = try reviewState()
        // Missed in a quick review this morning: back tomorrow, so it would sort first.
        let missed = ahead[5]
        state.cards[missed]?.memory = Memory(stability: 1, difficulty: 6, lastReview: state.now - 8 * 3600, due: state.now + 86_400)
        let plan = SessionPlan(
            day: state.today, kind: .review, minutes: 5, domains: [.japanese],
            parts: [PlanPart(kind: .practice, domain: .japanese, minutes: 5, title: "Japanese reviews", detail: "")], headline: "",
            notes: [], planned: true)
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        var now = state.now
        var asked: [CardKey] = []
        while case .question(let question) = run.step, asked.count < 100 {
            asked.append(question.key)
            now += 4
            run.choose(question.correctChoice!, now: now)
            run.next(now: now + 1)
        }
        #expect(!asked.isEmpty && !asked.contains(missed), "\(asked)")
        #expect(Day(try #require(run.cards[missed]?.memory).due) == state.today.adding(days: 1))
    }

    @Test("skipping a part before its time is up means the plan didn't run its course")
    func skippedPart() throws {
        let (state, _, _) = try reviewState()
        let plan = SessionPlan(
            day: state.today, kind: .regular, minutes: 25, domains: [.japanese],
            parts: [
                PlanPart(kind: .reviews, minutes: 5, title: "Warm-up reviews", detail: ""),
                PlanPart(kind: .practice, domain: .japanese, minutes: 20, title: "Japanese reviews", detail: ""),
            ],
            headline: "", notes: [], planned: true)
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        guard case .question(let first) = run.step else {
            Issue.record("no warm-up question")
            return
        }
        run.choose(first.correctChoice!, now: state.now + 4)
        run.next(now: state.now + 5)
        // The warm-up's one card is done; the practice part is skipped straight away.
        #expect(run.partIndex == 1)
        run.skipPart(now: state.now + 8)
        #expect(run.isComplete)
        run.finish(now: state.now + 10)
        #expect(!run.session.ranToEnd && !run.session.counts, "a two-minute session with a part skipped doesn't count")
    }
}

extension SimulatedStudentTests {
    @Test("moving on after an answer only moves on from that answer: an auto-advance after Continue doesn't skip a question")
    func moveOnOnce() throws {
        let store = Store(settings: Fixtures.settings([.japanese]))
        let state = store.state(on: Fixtures.monday)
        let plan = try #require(SessionPlanner.today(state, catalogs: Fixtures.catalogs(deck)))
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        #expect(run.stepNumber == 0)
        guard case .question(let first) = run.step else {
            Issue.record("no question: \(String(describing: run.step))")
            return
        }

        run.next(after: first.id, now: state.now + 1)
        #expect(run.stepNumber == 0 && run.step == .question(first), "not answered yet: nothing to move on from")
        run.choose(first.correctChoice ?? 0, now: state.now + 3)
        #expect(run.stepNumber == 0 && run.feedback != nil, "feedback alone isn't a new step")

        // Continue, then the auto-advance for the same answer.
        run.next(now: state.now + 4)
        #expect(run.stepNumber == 1)
        guard case .question(let second) = run.step else {
            Issue.record("no second question")
            return
        }
        #expect(second.id != first.id)
        run.next(after: first.id, now: state.now + 5)
        #expect(run.stepNumber == 1 && run.step == .question(second), "the first answer's auto-advance doesn't skip the second question")
        run.next(after: second.id, now: state.now + 5)
        #expect(run.stepNumber == 1, "the second isn't answered yet")

        run.choose(second.correctChoice ?? 0, now: state.now + 7)
        run.next(after: second.id, now: state.now + 8)
        #expect(run.stepNumber == 2 && run.step != .question(second))
        run.skipPart(now: state.now + 9)
        #expect(run.stepNumber == 3)
    }
}
