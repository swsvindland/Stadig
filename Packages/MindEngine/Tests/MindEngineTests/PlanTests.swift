import Foundation
import SQLite3
import SystemCore
import Testing

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
        #expect(
            StudyCalendar.checkInDue(on: monday.adding(days: 57), start: monday, calendar: nil, lifeModes: [], lastCheckIn: nil),
            "missed at the end of the review week, it comes the next days")
        #expect(
            !StudyCalendar.checkInDue(
                on: monday.adding(days: 57), start: monday, calendar: nil, lifeModes: [],
                lastCheckIn: monday.adding(days: 55)))

        // Stadig Lift's deload is the review week.
        let deload = DayRange(monday.adding(days: 20), monday.adding(days: 26))
        let lift = SystemCalendar(
            currentBlock: DayRange(monday.adding(days: -15), monday.adding(days: 26)), deloads: [deload], checkIns: [deload.end],
            publishedBy: .liftTrack)
        #expect(phase(21, calendar: lift).isReview)
        #expect(phase(16, calendar: lift) == .loading(week: 4, of: 5))

        // Vacation, illness and crunch pause; an injury doesn't.
        let vacation = LifeModePeriod(kind: .vacation, start: monday.adding(days: 30), end: monday.adding(days: 36), createdBy: .liftTrack)
        #expect(phase(31, modes: [vacation]).isPaused)
        let injury = LifeModePeriod(kind: .injury(Injury(parts: [InjuredPart(.knee)], severity: .moderate)), start: monday, createdBy: .liftTrack)
        #expect(!phase(31, modes: [injury]).isPaused)
    }

    @Test("how long a phase holds: the assessment's day, a week of the block, the review week, a pause to its end or open-ended")
    func phaseLastDay() {
        func last(_ offset: Int, calendar: SystemCalendar? = nil, modes: [LifeModePeriod] = []) -> Day? {
            StudyCalendar.lastDay(ofPhaseOn: monday.adding(days: offset), start: monday, calendar: calendar, lifeModes: modes)
        }
        #expect(last(3) == monday.adding(days: 3), "the assessment counts its days")
        #expect(last(15) == monday.adding(days: 20), "a week of the block, to its last day")
        #expect(last(13) == monday.adding(days: 13), "the assessment's last day hands on to the block")
        #expect(last(50) == monday.adding(days: 55), "the review week")

        let vacation = LifeModePeriod(kind: .vacation, start: monday.adding(days: 30), end: monday.adding(days: 36), createdBy: .liftTrack)
        #expect(last(31, modes: [vacation]) == monday.adding(days: 36))
        // Illness straight after: still paused, but it reads as illness, not vacation.
        let ill = LifeModePeriod(kind: .illness(.systemic), start: monday.adding(days: 37), end: monday.adding(days: 40), createdBy: .macroTrack)
        #expect(last(31, modes: [vacation, ill]) == monday.adding(days: 36))
        let open = LifeModePeriod(kind: .illness(.aboveNeck), start: monday.adding(days: 30), createdBy: .liftTrack)
        #expect(last(31, modes: [open]) == nil, "no end set: nobody knows")
    }

    @Test("crunch mode: nothing planned, a five-minute review offered, and the days left out of Discipline")
    func crunch() {
        var store = Store(settings: Fixtures.settings())
        store.sessions = [
            StudySession(
                purpose: .placement, start: monday.date(), end: monday.date(), plannedMinutes: 25, domains: Domain.allCases,
                planned: true, ranToEnd: true)
        ]
        store.tests = [
            TestResult(test: .vocabulary, date: monday.date(), score: 200), TestResult(test: .mathsPlacement, date: monday.date(), score: 5),
            TestResult(test: .numeracy, date: monday.date(), score: 0.8, detail: ["level": 6], placement: true),
            TestResult(test: .writing, date: monday.date(), score: 0.5, placement: true),
        ]
        let word = deck.word(100_100)!
        store.cards[word.key] = MemoryCard(key: word.key, memory: Scheduler.known(stability: 1, at: monday.date()), introduced: monday.date())
        store.lifeModes = [
            LifeModePeriod(
                kind: .crunch(CrunchDials(minutesAvailable: 0)), start: monday.adding(days: 1),
                end: monday.adding(days: 12), createdBy: .liftTrack)
        ]
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
            store.sessions.append(
                StudySession(
                    purpose: .regular, start: day.date().addingTimeInterval(64_800), end: day.date().addingTimeInterval(66_300),
                    plannedMinutes: 25, domains: [.japanese], planned: true, activeSeconds: 1500))
        }
        let score = Analyst.discipline(store.state(on: today))
        #expect(score.planned - score.completed == 1)
        #expect(score.band != .below && score.credit == 1, "one miss in twenty still earns full credit: \(score)")
    }

    @Test("review weeks plan practice and reading for pleasure, never new material")
    func reviewWeek() throws {
        var store = Store(settings: Fixtures.settings())
        store.sessions = [
            StudySession(
                purpose: .placement, start: monday.date(), end: monday.date(), plannedMinutes: 25, domains: Domain.allCases,
                planned: true, ranToEnd: true)
        ]
        store.tests = [
            TestResult(test: .vocabulary, date: monday.date(), score: 200), TestResult(test: .mathsPlacement, date: monday.date(), score: 5),
            TestResult(test: .numeracy, date: monday.date(), score: 0.8, detail: ["level": 6], placement: true),
            TestResult(test: .writing, date: monday.date(), score: 0.5, placement: true),
            TestResult(test: .readingTest, date: monday.date(), score: 0.8, detail: ["tier": 5], placement: true),
        ]
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
        let knower =
            (0..<3).flatMap { attempts($0, right: 5, wrong: 0, skipped: 0) } + (3..<8).flatMap { attempts($0, right: 0, wrong: 0, skipped: 5) }
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
        store.sessions = [
            StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.maths], planned: true, ranToEnd: true)
        ]
        store.tests = [TestResult(test: .mathsPlacement, date: now, score: 3)]
        for day in [monday.adding(days: 1), monday.adding(days: 3)] {
            let state = store.state(on: day)
            let plan = SessionPlanner.plan(.extra, domains: [], state: state, catalogs: Catalogs(), minutes: 5)
            var run = StudyRun(plan: plan, state: state, catalogs: Catalogs(), now: state.now)
            var clock = state.now
            while case .question(let question) = run.step {
                clock += 30
                if question.key == .topic("linear-equations") && question.kind == .review {
                    if let index = question.correctChoice {
                        run.choose((index + 1) % question.choices.count, now: clock)
                    } else {
                        run.type("12345", now: clock)
                    }
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
        store.sessions = [
            StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.maths], planned: true, ranToEnd: true)
        ]
        let plan = SessionPlanner.plan(.extra, domains: [], state: store.state(on: Fixtures.monday), catalogs: Catalogs(), minutes: 5)
        let part = try #require(plan.parts.first)
        #expect(plan.parts.count == 1 && part.kind == .reviews && part.minutes == 5, "\(plan.parts.map { ($0.kind, $0.minutes) })")
    }
}

extension PlanTests {
    @Test("Discipline judges each day by the schedule in force then: more days a week doesn't rescore the weeks before")
    func scheduleChange() throws {
        var store = Store(settings: Fixtures.settings(days: 3))
        let threeDays = Set(store.settings.schedule.studyDays)
        #expect(threeDays == [.monday, .wednesday, .friday])
        for offset in 0...37 where threeDays.contains(monday.adding(days: offset).weekday) {
            let day = monday.adding(days: offset)
            store.sessions.append(
                StudySession(
                    purpose: .regular, start: day.date().addingTimeInterval(64_800), end: day.date().addingTimeInterval(66_300),
                    plannedMinutes: 25, domains: [.japanese], planned: true, activeSeconds: 1500))
        }
        // On a Wednesday, four days a week from now on.
        let change = monday.adding(days: 37)
        let old = store.settings.schedule
        store.settings.schedule = StudySchedule(daysPerWeek: 4)
        store.settings.recordScheduleChange(from: old, on: change)
        let state = store.state(on: change.adding(days: 1))
        let score = Analyst.discipline(state)
        #expect(score.rate == 1 && score.planned >= 10, "\(score)")
        // Tuesday was a rest day then, though it's a study day now.
        let week = Analyst.week(state)
        #expect(week.first { $0.day == monday.adding(days: 36) }?.status == .rest, "\(week.map(\.status))")
        #expect(week.first { $0.day == monday.adding(days: 35) }?.status == .done)

        // Without the old schedule, every Tuesday and Thursday before would read as missed.
        var forgotten = state
        forgotten.settings.earlierSchedules = []
        #expect((Analyst.discipline(forgotten).rate ?? 1) < 0.8)
    }

    @Test("the week shows the days before a schedule change as that schedule had them, as Discipline counts them")
    func weekAcrossScheduleChange() {
        var store = Store(settings: Fixtures.settings(days: 3))
        let old = store.settings.schedule
        // From the second week's Thursday: Tuesdays and Thursdays.
        store.settings.schedule = StudySchedule(daysPerWeek: 2, preferredDays: [.tuesday, .thursday])
        store.settings.recordScheduleChange(from: old, on: monday.adding(days: 10))
        let state = store.state(on: monday.adding(days: 11))
        let week = Analyst.week(state)
        func day(_ offset: Int) -> StudyDay? { week.first { $0.day == monday.adding(days: offset) } }
        #expect(day(7)?.status == .missed && day(7)?.domains.isEmpty == false, "Monday was a study day then: \(week.map(\.status))")
        #expect(day(8)?.status == .rest && day(8)?.domains.isEmpty == true, "Tuesday was a rest day then")
        #expect(day(9)?.status == .missed && day(10)?.status == .missed && day(11)?.status == .rest)
        // Monday, Wednesday and Friday of the first week, then Monday, Wednesday and Thursday.
        let discipline = Analyst.discipline(state)
        #expect(discipline.planned == 6 && discipline.completed == 0, "\(discipline)")
    }

    @Test("a due card whose word left the catalog isn't counted, planned for or asked")
    func unusableDueCards() throws {
        var store = Store(settings: Fixtures.settings([.japanese], days: 7))
        let now = monday.date()
        var memory = Scheduler.known(stability: 2, at: now)
        memory.due = now
        let gone = MemoryCard(key: .word(999_999), memory: memory, introduced: now)
        store.cards[gone.key] = gone
        store.sessions = [StudySession(purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.japanese], planned: true)]
        store.tests = [TestResult(test: .vocabulary, date: now, score: 300, language: .japanese)]
        let catalogs = Fixtures.catalogs(deck)
        var state = store.state(on: monday.adding(days: 3))
        #expect(state.due(on: state.today).count == 1 && state.due(on: state.today, catalogs: catalogs).isEmpty)
        var analysis = Analyst.analyse(state, catalogs: catalogs)
        #expect(analysis.dueToday == 0)
        #expect(analysis.today?.parts.contains { $0.kind == .reviews } == false, "\(analysis.today?.parts.map(\.title) ?? [])")

        let word = try #require(deck.word(100_020))
        store.cards[word.key] = MemoryCard(key: word.key, memory: memory, introduced: now)
        state = store.state(on: monday.adding(days: 3))
        analysis = Analyst.analyse(state, catalogs: catalogs)
        #expect(analysis.dueToday == 1)
        #expect(analysis.today?.parts.first { $0.kind == .reviews }?.detail == "1 due: 1 Japanese word")
    }
}

extension JapaneseMeasureTests {
    /// A catalog file with a few thousand sentences, all in one band, as the app's catalogs store them.
    func sentenceCatalog(count: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "mind-sentences-\(UUID().uuidString).db")
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var sql = """
            CREATE TABLE words (id INTEGER, rank INTEGER, word TEXT, kana TEXT, kanji TEXT, meaning TEXT, meanings TEXT, pos TEXT, kanji_chars TEXT);
            CREATE TABLE meta (key TEXT, value TEXT);
            CREATE TABLE sentences (id INTEGER PRIMARY KEY, jp TEXT, en TEXT, level INTEGER, words TEXT, length INTEGER);
            INSERT INTO words VALUES (1, 1, 'uno', 'uno', NULL, 'one', 'one', 'number', '');
            BEGIN;
            """
        for i in 1...count {
            // Ids spread like a real catalog's, with gaps.
            sql += "INSERT INTO sentences VALUES (\(i * 7 + 1000), 'Frase \(i).', 'Sentence \(i).', \(1 + i % 500), '1', 10);\n"
        }
        sql += "COMMIT;"
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        return url
    }

    @Test("sentence samples move on from day to day, and the in-memory deck samples like the catalog")
    func sentenceSamples() throws {
        let count = 5000
        let url = try sentenceCatalog(count: count)
        defer { try? FileManager.default.removeItem(at: url) }
        let catalog = try #require(LanguageDeck(url: url, language: .spanish))
        let day = 20_744
        let first = catalog.sentences(levels: 1...500, limit: 24, skip: day).map(\.id)
        #expect(first.count == 24)
        for later in [1, 7, 14, 42, 91] {
            let next = catalog.sentences(levels: 1...500, limit: 24, skip: day + later).map(\.id)
            #expect(Set(first).intersection(next).count <= 3, "\(later) days on, \(Set(first).intersection(next).count) of 24 again")
        }
        // The reading test's own offset gives it a different sample from listening's.
        #expect(Set(first).intersection(catalog.sentences(levels: 1...500, limit: 24, skip: day + 11).map(\.id)).count <= 3)

        let sentences = (1...count).map { i in
            Sentence(id: i * 7 + 1000, text: "Frase \(i).", english: "Sentence \(i).", level: 1 + i % 500, words: [1])
        }
        let memory = LanguageDeck(
            language: .spanish, words: [Word(id: 1, language: .spanish, rank: 1, text: "uno", kana: "uno", meaning: "one", pos: "number")],
            sentences: sentences)
        for skip in [0, day, day + 11] {
            #expect(
                memory.sentences(levels: 1...500, limit: 24, skip: skip).map(\.id)
                    == catalog.sentences(levels: 1...500, limit: 24, skip: skip).map(\.id))
            #expect(
                memory.sentences(levels: 100...200, limit: 10, skip: skip).map(\.id)
                    == catalog.sentences(levels: 100...200, limit: 10, skip: skip).map(\.id))
        }
    }

    @Test("the real catalog, when it's been built: a check-in's tests ask other sentences than the last one's")
    func realCatalogSamples() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../Apps/MindTrack/Catalogs/japanese.db")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let deck = try #require(LanguageDeck(url: url))
        let day = 20_744
        for levels in LanguageTests.listeningLevels {
            let now = deck.sentences(levels: levels, limit: 24, skip: day).map(\.id)
            let later = deck.sentences(levels: levels, limit: 24, skip: day + 49).map(\.id)
            #expect(Set(now).intersection(later).count <= 4, "\(levels): \(Set(now).intersection(later).count) of 24 again seven weeks on")
        }
        let listening = LanguageTests.listening(deck: deck, seed: "t", offset: day).map(\.prompt)
        let next = LanguageTests.listening(deck: deck, seed: "t", offset: day + 49).map(\.prompt)
        #expect(Set(listening).intersection(next).count <= 1)
    }
}

extension PlanTests {
    /// A Japanese learner on day 30: `due` cards due within the week, and a fortnight of reviews
    /// recalled at `recall`.
    func paceState(due: Int, recall: Double) -> StudyState {
        let today = monday.adding(days: 30)
        let now = today.date().addingTimeInterval(18 * 3600)
        var store = Store(settings: Fixtures.settings([.japanese]))
        for rank in 1...due {
            let word = deck.word(100_000 + rank)!
            var card = MemoryCard(key: word.key, memory: Scheduler.known(stability: 10, at: now - 10 * 86_400), introduced: now - 20 * 86_400)
            card.memory?.due = now + Double(rank % 6) * 86_400
            store.cards[word.key] = card
        }
        let reviews = (0..<40).map { i in
            Attempt(key: deck.word(100_500 + i)!.key, kind: .review, correct: Double(i) < recall * 40, seconds: 5, at: now - 3 * 86_400)
        }
        store.sessions = [
            StudySession(
                purpose: .regular, start: now - 3 * 86_400, end: now - 3 * 86_400 + 1500, plannedMinutes: 25,
                domains: [.japanese], planned: true, attempts: reviews, ranToEnd: true)
        ]
        store.tests = [TestResult(test: .vocabulary, date: monday.date(), score: 300, language: .japanese)]
        return store.state(on: today)
    }

    @Test("a language's pace reads its own recall and week of reviews, and the session plan teaches what the Plan tab says")
    func paceFromState() throws {
        let steady = paceState(due: 50, recall: 0.9)
        let pace = LanguagePlan.pace(.japanese, state: steady, reviewWeek: false)
        #expect(pace.dueThisWeek == 50 && pace.count == 15 && pace.reason == nil, "\(pace)")
        #expect(LanguagePlan.pace(.japanese, state: steady, reviewWeek: true).count == 0)
        #expect(LanguagePlan.pace(.japanese, state: steady, reviewWeek: false, minutes: 50).count == 25, "twice the time, capped at 25")
        #expect(LanguagePlan.pace(.spanish, state: steady, reviewWeek: false).dueThisWeek == 0, "another language's cards aren't counted")

        let slipping = LanguagePlan.pace(.japanese, state: paceState(due: 50, recall: 0.7), reviewWeek: false)
        #expect(slipping.count == 6 && slipping.reason?.contains("70%") == true, "\(slipping)")
        let piled = LanguagePlan.pace(.japanese, state: paceState(due: 210, recall: 0.9), reviewWeek: false)
        #expect(piled.dueThisWeek == 210 && piled.count <= 4 && piled.reason?.contains("210 reviews") == true, "\(piled)")

        var notes: [String] = []
        let learn = LanguageModule.learnPart(
            .japanese, minutes: 10, session: 25, state: paceState(due: 50, recall: 0.7),
            catalogs: Fixtures.catalogs(deck), notes: &notes)
        #expect(learn.items == slipping.count && notes.contains { $0.contains("70%") }, "\(learn) \(notes)")
    }

    @Test("Today's actions carry what they start: minutes of reviews, the missed session's domains, the episode's language")
    func actionCommands() {
        var store = Store(settings: Fixtures.settings())
        store.sessions = [
            StudySession(
                purpose: .placement, start: monday.date(), end: monday.date(), plannedMinutes: 25, domains: Domain.allCases,
                planned: true, ranToEnd: true)
        ]
        store.tests = [
            TestResult(test: .vocabulary, date: monday.date(), score: 200), TestResult(test: .mathsPlacement, date: monday.date(), score: 5),
            TestResult(test: .numeracy, date: monday.date(), score: 0.8, detail: ["level": 6], placement: true),
            TestResult(test: .writing, date: monday.date(), score: 0.5, placement: true),
            TestResult(test: .readingTest, date: monday.date(), score: 0.8, detail: ["tier": 5], placement: true),
        ]
        for rank in 1...100 {
            let word = deck.word(100_000 + rank)!
            store.cards[word.key] = MemoryCard(key: word.key, memory: Scheduler.known(stability: 1, at: monday.date()), introduced: monday.date())
        }
        var seen: Set<MindAction.Kind> = []
        for offset in 49...55 {
            let state = store.state(on: monday.adding(days: offset))
            let analysis = Analyst.analyse(state, catalogs: Fixtures.catalogs(deck))
            for action in analysis.actions {
                seen.insert(action.kind)
                #expect(action.command.kind == action.kind, "\(action.id)")
                switch action.command {
                case .extraReview(let minutes): #expect(minutes == (action.id == "pile" ? 10 : 5), "\(action.id)")
                case .episode(let language): #expect(action.id == "episode.\(language.domain.rawValue)" && language == .japanese)
                case .catchUp(let domains):
                    let yesterday = analysis.week.first { $0.day == state.today.adding(days: -1) }
                    #expect(!domains.isEmpty && domains == yesterday?.domains, "\(domains)")
                case .pickBook, .stalledBook: break
                }
            }
        }
        #expect(seen.isSuperset(of: [.extraReview, .episode, .catchUp]), "\(seen)")
    }
}
