import Foundation
import Testing
import SystemCore
@testable import MindEngine

@Suite("Plans and the calendar")
struct PlanTests {
    let monday = Fixtures.monday
    let deck = Fixtures.deck()

    @Test("the split: five days rotate Japanese, maths with writing, and reading, never the same two days running")
    func split() {
        let week = Split.week(starting: monday, settings: Fixtures.settings())
        let days = week.keys.sorted()
        #expect(days.count == 5)
        let groups = days.map { week[$0]! }
        #expect(groups.filter { $0 == [.japanese] }.count == 2)
        #expect(groups.filter { $0 == [.maths, .writing] }.count >= 1)
        #expect(groups.filter { $0 == [.reading] }.count >= 1)
        #expect(zip(groups, groups.dropFirst()).allSatisfy { $0 != $1 }, "\(groups)")

        // A lagging domain gets more of the week.
        let prioritised = Split.week(starting: monday, settings: Fixtures.settings(), priorities: [.reading])
        #expect(prioritised.values.filter { $0 == [.reading] }.count >= 2)

        // Two days with three groups: every group still comes round within two weeks.
        let two = Fixtures.settings(days: 2)
        let first = Set(Split.week(starting: monday, settings: two).values)
        let second = Set(Split.week(starting: monday.adding(weeks: 1), settings: two).values)
        #expect(first.union(second).count == 3, "\(first) \(second)")
    }

    @Test("on its own: two weeks of assessment, five weeks of blocks, a review week, and a check-in at its end")
    func calendar() {
        func phase(_ offset: Int, calendar: SystemCalendar? = nil, modes: [LifeModePeriod] = []) -> StudyPhase {
            StudyCalendar.phase(on: monday.adding(days: offset), start: monday, calendar: calendar, lifeModes: modes)
        }
        #expect(phase(0) == .assessment(day: 1, of: 14))
        #expect(phase(14) == .loading(week: 0, of: 5))
        #expect(phase(48) == .loading(week: 4, of: 5))
        #expect(phase(49).isReview && phase(55).isReview)
        #expect(phase(56) == .loading(week: 0, of: 5))
        #expect(StudyCalendar.checkInDue(on: monday.adding(days: 54), start: monday, calendar: nil, lifeModes: [], lastCheckIn: nil))
        #expect(!StudyCalendar.checkInDue(on: monday.adding(days: 50), start: monday, calendar: nil, lifeModes: [], lastCheckIn: nil))
        #expect(StudyCalendar.checkInDue(on: monday.adding(days: 57), start: monday, calendar: nil, lifeModes: [], lastCheckIn: nil),
                "missed at the end of the review week, it comes the next days")
        #expect(!StudyCalendar.checkInDue(on: monday.adding(days: 57), start: monday, calendar: nil, lifeModes: [],
                                          lastCheckIn: monday.adding(days: 55)))

        // Lift Track's deload is the review week.
        let deload = DayRange(monday.adding(days: 20), monday.adding(days: 26))
        let lift = SystemCalendar(currentBlock: DayRange(monday.adding(days: -15), monday.adding(days: 26)), deloads: [deload], checkIns: [deload.end],
                                  publishedBy: .liftTrack)
        #expect(phase(21, calendar: lift).isReview)
        #expect(phase(16, calendar: lift) == .loading(week: 4, of: 5))

        // Vacation, illness and crunch pause; an injury doesn't.
        let vacation = LifeModePeriod(kind: .vacation, start: monday.adding(days: 30), end: monday.adding(days: 36), createdBy: .liftTrack)
        #expect(phase(31, modes: [vacation]).isPaused)
        let injury = LifeModePeriod(kind: .injury(Injury(parts: [InjuredPart(.knee)], severity: .moderate)), start: monday, createdBy: .liftTrack)
        #expect(!phase(31, modes: [injury]).isPaused)
    }

    @Test("crunch mode: nothing planned, a five-minute review offered, and the days left out of Discipline")
    func crunch() {
        var store = Store(settings: Fixtures.settings())
        store.sessions = [StudySession(purpose: .placement, start: monday.date(), end: monday.date(), plannedMinutes: 25, domains: Domain.allCases,
                                       planned: true, ranToEnd: true)]
        store.tests = [TestResult(test: .vocabulary, date: monday.date(), score: 200), TestResult(test: .mathsPlacement, date: monday.date(), score: 5),
                       TestResult(test: .numeracy, date: monday.date(), score: 0.8, detail: ["level": 6], placement: true),
                       TestResult(test: .writing, date: monday.date(), score: 0.5, placement: true)]
        let word = deck.word(100_100)!
        store.cards[word.key] = MemoryCard(key: word.key, memory: Scheduler.known(stability: 1, at: monday.date()), introduced: monday.date())
        store.lifeModes = [LifeModePeriod(kind: .crunch(CrunchDials(minutesAvailable: 0)), start: monday.adding(days: 1),
                                          end: monday.adding(days: 12), createdBy: .liftTrack)]
        let state = store.state(on: monday.adding(days: 8))
        #expect(SessionPlanner.today(state, catalogs: Fixtures.catalogs(deck)) == nil)
        let analysis = Analyst.analyse(state, catalogs: Fixtures.catalogs(deck))
        #expect(analysis.actions.contains { $0.kind == .extraReview })
        #expect(analysis.discipline.planned == 1, "only the placement day counts: \(analysis.discipline)")
    }

    @Test("Discipline: one missed session in four weeks is in the zone; there's no credit above it")
    func discipline() {
        var store = Store(settings: Fixtures.settings())
        let today = monday.adding(days: 34)
        let studyDays = Set(store.settings.schedule.studyDays)
        var missed = false
        for offset in 0..<34 where studyDays.contains(monday.adding(days: offset).weekday) {
            let day = monday.adding(days: offset)
            if offset > 20 && !missed {
                missed = true
                continue
            }
            store.sessions.append(StudySession(purpose: .regular, start: day.date().addingTimeInterval(64_800), end: day.date().addingTimeInterval(66_300),
                                               plannedMinutes: 25, domains: [.japanese], planned: true, activeSeconds: 1500))
        }
        let score = Analyst.discipline(store.state(on: today))
        #expect(score.planned - score.completed == 1)
        #expect(score.band != .below && score.credit == 1, "one miss in twenty still earns full credit: \(score)")
    }

    @Test("review weeks plan practice and reading for pleasure, never new material")
    func reviewWeek() throws {
        var store = Store(settings: Fixtures.settings())
        store.sessions = [StudySession(purpose: .placement, start: monday.date(), end: monday.date(), plannedMinutes: 25, domains: Domain.allCases,
                                       planned: true, ranToEnd: true)]
        store.tests = [TestResult(test: .vocabulary, date: monday.date(), score: 200), TestResult(test: .mathsPlacement, date: monday.date(), score: 5),
                       TestResult(test: .numeracy, date: monday.date(), score: 0.8, detail: ["level": 6], placement: true),
                       TestResult(test: .writing, date: monday.date(), score: 0.5, placement: true),
                       TestResult(test: .readingTest, date: monday.date(), score: 0.8, detail: ["tier": 5], placement: true)]
        for offset in 49...53 {
            let state = store.state(on: monday.adding(days: offset))
            guard let plan = SessionPlanner.today(state, catalogs: Fixtures.catalogs(deck)) else { continue }
            #expect(plan.kind == .review || plan.kind == .checkIn)
            #expect(!plan.parts.contains { if case .learn = $0.kind { true } else { false } }, "\(plan.parts.map(\.kind))")
        }
    }

    @Test("new words slow when recall slips or reviews pile up, and stop in a review week")
    func pacing() {
        #expect(LanguagePlan.newWords(retention: 0.9, dueThisWeek: 50, minutes: 25, reviewWeek: false).count == 15)
        #expect(LanguagePlan.newWords(retention: 0.75, dueThisWeek: 50, minutes: 25, reviewWeek: false).count == 6)
        #expect(LanguagePlan.newWords(retention: 0.95, dueThisWeek: 50, minutes: 25, reviewWeek: false).count > 15)
        #expect(LanguagePlan.newWords(retention: 0.9, dueThisWeek: 260, minutes: 25, reviewWeek: false).count <= 4)
        #expect(LanguagePlan.newWords(retention: 0.9, dueThisWeek: 50, minutes: 25, reviewWeek: true).count == 0)
        let slipping = LanguagePlan.newWords(retention: 0.75, dueThisWeek: 50, minutes: 25, reviewWeek: false)
        #expect(slipping.reason?.contains("75%") == true)
    }
}

@Suite("Japanese measures")
struct JapaneseMeasureTests {
    func attempts(_ band: Int, right: Int, wrong: Int, skipped: Int) -> [Attempt] {
        let make = { (correct: Bool, skip: Bool) in
            Attempt(key: .word(1), kind: .test, correct: correct, skipped: skip, seconds: 3, at: Date(), test: .vocabulary, band: band)
        }
        return Array(repeating: make(true, false), count: right) + Array(repeating: make(false, false), count: wrong)
            + Array(repeating: make(false, true), count: skipped)
    }

    @Test("words known: each band's size times the share known, with lucky guesses taken out")
    func estimate() {
        // Knows the first 1,000 words, none after.
        let knower = (0..<3).flatMap { attempts($0, right: 5, wrong: 0, skipped: 0) } + (3..<8).flatMap { attempts($0, right: 0, wrong: 0, skipped: 5) }
        #expect(LanguageTests.estimate(knower).words == 1000)
        // A guesser who never says "don't know": one right in four is luck, and comes out.
        let guesser = (0..<8).flatMap { attempts($0, right: 1, wrong: 3, skipped: 0) }
        #expect(LanguageTests.estimate(guesser).words == 0)
        // Saying "don't know" costs nothing.
        let honest = (0..<8).flatMap { attempts($0, right: 1, wrong: 0, skipped: 4) }
        #expect(LanguageTests.estimate(honest).words == 4000)
        let range = LanguageTests.estimate(knower)
        #expect(range.low <= 1000 && range.high >= 1000)
        #expect(LanguageTests.vocabularyScore(10_000) == 100 && LanguageTests.vocabularyScore(1000) > 50)
    }

    @Test("placement stops once a band is mostly unknown")
    func placementStop() {
        let deck = Fixtures.deck()
        #expect(LanguageTests.continuePlacement(after: 0, attempts: attempts(0, right: 4, wrong: 1, skipped: 0), deck: deck))
        #expect(!LanguageTests.continuePlacement(after: 2, attempts: attempts(2, right: 1, wrong: 0, skipped: 4), deck: deck))
    }

    @Test("the real catalog, when it's been built: common words first, believable wrong answers, sentences at every level")
    func realCatalog() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../Apps/MindTrack/Catalogs/japanese.db")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let opened = Date()
        let deck = try #require(LanguageDeck(url: url))
        print("Opened the Japanese catalog in \(Int(Date().timeIntervalSince(opened) * 1000)) ms")
        #expect(deck.words.count == 20_000)
        let eat = try #require(deck.words.first { $0.text == "食べる" })
        #expect(eat.rank < 400 && eat.meaning == "to eat" && eat.kana == "たべる")
        #expect(deck.words.prefix(100).contains { $0.text == "行く" })
        #expect(!deck.words.prefix(500).contains { ["は", "が", "を", "の", "に"].contains($0.text) }, "particles aren't cards")
        #expect(deck.kanji(in: eat).first?.meanings.contains("eat") == true)
        let examples = deck.sentences(with: eat.id, maxLevel: 500)
        #expect(!examples.isEmpty && examples.allSatisfy { $0.level <= 500 && $0.words.contains(eat.id) })
        let question = LanguageQuiz.question(eat, ask: .meaning, kind: .review, deck: deck, seed: "t")
        #expect(question.choices.count == 4 && question.choices[question.correctChoice!] == "to eat")
        let reading = LanguageQuiz.question(eat, ask: .reading, kind: .review, deck: deck, seed: "t")
        #expect(reading.choices.count == 4 && reading.choices.contains("たべる"))
        let listening = LanguageTests.listening(deck: deck, seed: "t", offset: 0)
        #expect(listening.count == 10 && listening.allSatisfy { $0.choices.count == 4 })
        for band in 0..<LanguageTests.bands.count { #expect(LanguageTests.vocabulary(band: band, deck: deck, seed: "t").count == 5) }
    }
}

@Suite("Mastery")
struct MasteryTests {
    @Test("four of the last five, ending on a right one; three wrong sets it aside")
    func rules() {
        #expect(Mastery.mastered([true, true, true, true]))
        #expect(!Mastery.mastered([true, true, true]))
        #expect(!Mastery.mastered([true, true, true, true, false]), "a miss last means not yet")
        #expect(Mastery.mastered([false, true, true, true, true]))
        #expect(Mastery.struggling([false, true, false, false]))
    }

    @Test("a topic missed on two reviews running goes back to learning, and what builds on it waits")
    func demotion() throws {
        let monday = Fixtures.monday
        var store = Store(settings: Fixtures.settings([.maths]))
        let now = monday.date()
        for id in ["order-of-operations", "negative-numbers", "linear-equations"] {
            var memory = Scheduler.known(stability: 3, at: now.addingTimeInterval(-5 * 86_400))
            memory.due = now.addingTimeInterval(-86_400)
            store.cards[.topic(id)] = MemoryCard(key: .topic(id), memory: memory, introduced: now)
        }
        store.sessions = [StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.maths], planned: true, ranToEnd: true)]
        store.tests = [TestResult(test: .mathsPlacement, date: now, score: 3)]
        for day in [monday.adding(days: 1), monday.adding(days: 3)] {
            let state = store.state(on: day)
            let plan = SessionPlanner.plan(.extra, domains: [], state: state, catalogs: Catalogs(), minutes: 5)
            var run = StudyRun(plan: plan, state: state, catalogs: Catalogs(), now: state.now)
            var clock = state.now
            while case .question(let question) = run.step {
                clock += 30
                if question.key == .topic("linear-equations") && question.kind == .review {
                    if let index = question.correctChoice { run.choose((index + 1) % question.choices.count, now: clock) } else { run.type("12345", now: clock) }
                } else if let index = question.correctChoice {
                    run.choose(index, now: clock)
                } else if case .number(let value, _) = question.answer {
                    run.type(value.description, now: clock)
                }
                run.next(now: clock + 2)
            }
            run.finish(now: clock)
            store.save(run)
            // Make it due again for the second review.
            if var card = store.cards[.topic("linear-equations")], card.memory != nil {
                card.memory!.due = day.date()
                store.cards[card.key] = card
            }
        }
        let card = try #require(store.cards[.topic("linear-equations")])
        #expect(card.memory == nil, "back to learning")
        #expect(MathsPlan.next(store.cards)?.id == "linear-equations", "it's what comes next")
        #expect(!MathsPlan.frontier(store.cards).contains { $0.prerequisites.contains("linear-equations") })
    }
}

@Suite("Quick review")
struct QuickReviewTests {
    @Test("five minutes of reviews is five minutes of reviews, not a warm-up's share of it")
    func quickReview() throws {
        var store = Store(settings: Fixtures.settings([.maths]))
        let now = Fixtures.monday.date()
        for topic in MathCurriculum.topics.prefix(8) {
            var memory = Scheduler.known(stability: 3, at: now.addingTimeInterval(-5 * 86_400))
            memory.due = now
            store.cards[topic.key] = MemoryCard(key: topic.key, memory: memory, introduced: now)
        }
        store.sessions = [StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.maths], planned: true, ranToEnd: true)]
        let plan = SessionPlanner.plan(.extra, domains: [], state: store.state(on: Fixtures.monday), catalogs: Catalogs(), minutes: 5)
        let part = try #require(plan.parts.first)
        #expect(plan.parts.count == 1 && part.kind == .reviews && part.minutes == 5, "\(plan.parts.map { ($0.kind, $0.minutes) })")
    }
}
