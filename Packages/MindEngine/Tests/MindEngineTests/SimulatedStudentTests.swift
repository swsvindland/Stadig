import Foundation
import Testing
import SystemCore
@testable import MindEngine

@Suite("Simulated students")
struct SimulatedStudentTests {
    let deck = Fixtures.deck()

    @Test("the first session finds a level in each domain and teaches the first words")
    func firstSession() throws {
        // Reading's reading test is the rest of a first session with all four courses (ReadingTests);
        // without it, what's left goes to the first new words.
        var store = Store(settings: Fixtures.settings([.japanese, .maths, .writing]))
        var student = Student(vocabulary: 1200, mathsLevel: 5, writingLevel: 1, deck: deck)
        let state = store.state(on: Fixtures.monday)
        let plan = try #require(SessionPlanner.today(state, catalogs: Fixtures.catalogs(deck)))
        #expect(plan.kind == .placement)
        #expect(plan.parts.map { "\($0.kind) \($0.domain?.rawValue ?? "")" } == ["placement japanese", "placement maths", "placement writing", "learn japanese"])
        let run = try #require(store.study(on: Fixtures.monday, student: &student, deck: deck))

        let vocabulary = try #require(store.tests.first { $0.test == .vocabulary })
        #expect(vocabulary.placement)
        #expect(vocabulary.score > 700 && vocabulary.score < 1900, "true 1,200, estimated \(vocabulary.score)")

        let placement = try #require(store.tests.first { $0.test == .mathsPlacement })
        let known = MathsPlan.known(store.cards)
        let levels = known.compactMap { MathCurriculum.topic($0)?.level }
        #expect(levels.max() ?? 0 >= 4 && levels.max() ?? 0 <= 6, "placed at \(placement.detail), topics \(known.sorted())")
        #expect(known.contains("order-of-operations") && known.contains("linear-equations"))
        #expect(!known.contains("derivatives") && !known.contains("integration"))

        let writing = try #require(store.tests.first { $0.test == .writing })
        #expect(writing.placement && writing.score > 0.2)
        #expect(!WritingPlan.known(store.cards).isEmpty)

        // Words below the placement level were checked, not taught; the session ran about its length.
        let words = store.cards.values.filter { $0.key.wordID != nil }
        #expect(!words.isEmpty)
        #expect(words.allSatisfy { (deck.word($0.key.wordID!)?.rank ?? 0) > 0 })
        #expect(run.session.minutes > 12 && run.session.minutes < 40, "\(run.session.minutes) minutes")
        #expect(SessionPlanner.today(store.state(on: Fixtures.monday.adding(days: 1)), catalogs: Fixtures.catalogs(deck))?.kind == .regular)
    }

    @Test("someone who can't read kana starts with hiragana, and words wait for it")
    func kanaFirst() throws {
        var store = Store(settings: Fixtures.settings([.japanese], readsKana: false))
        var student = Student(vocabulary: 0, mathsLevel: 0, writingLevel: 0, deck: deck)
        let plan = try #require(SessionPlanner.today(store.state(on: Fixtures.monday), catalogs: Fixtures.catalogs(deck)))
        #expect(plan.parts.first?.detail.contains("kana") == true, "\(plan.parts)")
        store.study(on: Fixtures.monday, student: &student, deck: deck)
        #expect(store.cards.keys.contains { $0.isKana })
        #expect(!store.cards.keys.contains { $0.wordID != nil }, "no words before hiragana")
        #expect(store.cards.keys.filter(\.isKana).allSatisfy { KanaTable.byKana[$0.item]?.script == .hiragana })
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
            if let run = store.study(on: day, student: &student, deck: deck) {
                kinds[day] = run.plan.kind
                if run.plan.kind == .review {
                    newDuringReview += store.cards.count - before
                    #expect(!run.plan.parts.contains { if case .learn = $0.kind { true } else { false } }, "nothing new in a review week")
                }
            }
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

        // Check-in on the last days of the review week.
        var checkIn: StudyRun?
        for offset in 52...56 where checkIn == nil {
            if let run = store.study(on: Fixtures.monday.adding(days: offset), student: &student, deck: deck), run.plan.kind == .checkIn {
                checkIn = run
            }
        }
        let run = try #require(checkIn)
        let kindsTested = Set(run.newTests.map(\.test))
        #expect(kindsTested.isSuperset(of: [.vocabulary, .listening, .maths, .writing]), "\(kindsTested)")
        #expect(run.changedCards.isEmpty || run.changedCards.allSatisfy { store.cards[$0]?.memory != nil }, "tests don't schedule")

        let final = store.state(on: Fixtures.monday.adding(days: 57))
        let analysis = Analyst.analyse(final, catalogs: Fixtures.catalogs(deck))
        let intelligence = try #require(analysis.stats.first { $0.stat == .intelligence })
        #expect(intelligence.score != nil)
        #expect(analysis.discipline.band == .inZone || analysis.discipline.band == .above, "\(analysis.discipline)")
        let summary = Analyst.appSummary(final, analysis)
        #expect(summary.app == .knowledge && !summary.sessions.isEmpty && summary.sessions.allSatisfy { $0.kind == .study })
        #expect(StudyCalendar.checkInDue(on: final.today, start: final.start, calendar: nil, lifeModes: [], lastCheckIn: final.lastCheckIn) == false)
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
        guard case .question(let first) = run.step else { Issue.record("no question"); return }
        run.choose((first.correctChoice! + 1) % first.choices.count, now: state.now + 5)
        let after = try #require(run.cards[word.key]?.memory)
        #expect(after.lapses == 1 && Day(after.due) == state.today.adding(days: 1))
        run.next(now: state.now + 7)
        guard case .question(let again) = run.step else { Issue.record("not asked again"); return }
        #expect(again.key == word.key && again.kind == .learn)
        run.choose(again.correctChoice!, now: state.now + 12)
        #expect(run.cards[word.key]?.memory == after, "the re-ask doesn't touch the schedule")
    }
}
