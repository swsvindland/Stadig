import Foundation
import SystemCore

@testable import MindEngine

enum Fixtures {
    /// A made-up deck: `count` words in rank order (every third written with a kanji) and
    /// sentences of three words each, from common to rare.
    static func deck(words count: Int = 3000, sentences: Int = 3000) -> LanguageDeck {
        let kinds = ["noun", "verb", "i-adjective"]
        let words = (1...count).map { i in
            Word(
                id: 100_000 + i, rank: i, text: i % 3 == 0 ? "語\(i)" : "ご\(i)", kana: "ご\(i)", meaning: "meaning \(i)",
                pos: kinds[i % 3])
        }
        let list = (1...sentences).map { i -> Sentence in
            let ranks = [1 + i % 40, 1 + (i * 13) % 400, 1 + (i * 31) % max(1, min(count, i * 3))]
            return Sentence(
                id: i, text: "文\(i)です。", english: "Sentence number \(i) in English.", level: ranks.max()!,
                words: ranks.map { 100_000 + $0 })
        }
        return LanguageDeck(words: words, sentences: list)
    }

    static let monday = Day(year: 2026, month: 3, day: 2)

    static func settings(
        _ domains: [Domain] = [.japanese, .maths, .writing, .reading], maintenance: [Domain] = [], readsKana: Bool = true,
        days: Int = 5, background: MathsBackground = .algebra
    ) -> MindSettings {
        var courses = Dictionary(uniqueKeysWithValues: domains.map { ($0, CourseMode.focus) })
        for domain in maintenance { courses[domain] = .maintenance }
        // The fixtures' moments are mostly midnights (`day.date()`), so their days start then;
        // `DayStartTests` covers the 4 a.m. start.
        return MindSettings(
            courses: courses, schedule: StudySchedule(daysPerWeek: days), onboardedAt: monday.date(), readsKana: readsKana,
            mathsBackground: background, genres: [.fantasy, .sciFi], dayStart: 0)
    }

    static func catalogs(_ deck: LanguageDeck) -> Catalogs { Catalogs(decks: [deck.language: deck]) }
}

/// A simulated student with a true level in each domain, who learns what's taught with a fixed
/// chance and forgets along the scheduler's curve.
struct Student {
    /// Words up to this rank are known before starting.
    var vocabulary: Int
    /// Maths topics up to this level are known before starting.
    var mathsLevel: Int
    /// Writing skills up to this level are known.
    var writingLevel: Int
    /// Numeracy: fluent up to this level, rarely right two above it.
    var numeracyLevel = 6
    /// Statistics and logic topics up to this level are known before starting.
    var discreteLevel = 3
    /// How likely a taught word or topic is right when asked again in the same session.
    var learnRate = 0.85
    /// Seconds an answer takes, as a share of the question's usual time.
    var pace = 0.8
    var rng = SeededRandom(seed: 42)
    /// What's been learned in the app, by card.
    var learned: Set<CardKey> = []
    var deck: LanguageDeck

    mutating func knows(_ question: Question, cards: [CardKey: MemoryCard], now: Date) -> Bool? {
        let key = question.key
        switch key.domain {
        case .japanese, .spanish:
            if key.raw == "jp.sentences" || key.raw == "jp.listening" { return Double.random(in: 0..<1, using: &rng) < 0.8 }
            if key.isKana { return Double.random(in: 0..<1, using: &rng) < (learned.contains(key) ? 0.95 : learnRate) }
            guard let id = key.wordID, let word = deck.word(id) else { return nil }
            if word.rank <= vocabulary { return Double.random(in: 0..<1, using: &rng) < 0.97 }
            if let memory = cards[key]?.memory {
                return Double.random(in: 0..<1, using: &rng) < Scheduler.retrievability(memory, at: now)
            }
            return question.kind == .learn ? Double.random(in: 0..<1, using: &rng) < learnRate : nil
        case .maths:
            if let numeracy = key.numeracy {
                let p = numeracy.level <= numeracyLevel ? 0.95 : numeracy.level == numeracyLevel + 1 ? 0.35 : 0.05
                return Double.random(in: 0..<1, using: &rng) < p
            }
            guard let topic = MathCurriculum.topic(key.item) else { return nil }
            let level = topic.strand == .discrete ? discreteLevel : mathsLevel
            if topic.level <= level { return Double.random(in: 0..<1, using: &rng) < 0.95 }
            if question.kind == .learn || cards[key]?.memory != nil {
                return Double.random(in: 0..<1, using: &rng) < (topic.level <= level + 2 ? learnRate : 0.3)
            }
            return nil
        case .writing:
            let level = WritingBank.standard.skill(key.item)?.level ?? 3
            if level <= writingLevel { return Double.random(in: 0..<1, using: &rng) < 0.95 }
            return Double.random(in: 0..<1, using: &rng) < (question.kind == .learn || cards[key]?.memory != nil ? learnRate : 0.4)
        case .reading:
            return nil
        }
    }

    /// Works through a whole session, answering as this student would.
    mutating func run(_ run: inout StudyRun, from start: Date) -> Date {
        var now = start
        var guardSteps = 0
        while let step = run.step, guardSteps < 2000 {
            guardSteps += 1
            switch step {
            case .lesson:
                now += 20
                run.next(now: now)
            case .question(let question):
                now += max(1, question.expectedSeconds * pace)
                let known = knows(question, cards: run.cards, now: now)
                if known == true {
                    if let index = question.correctChoice { run.choose(index, now: now) } else { run.type(answerText(question), now: now) }
                    learned.insert(question.key)
                } else if known == nil && question.allowsDontKnow && Double.random(in: 0..<1, using: &rng) < 0.7 {
                    run.dontKnow(now: now)
                } else if let index = question.correctChoice {
                    // A guess, wrong unless lucky.
                    run.choose(Double.random(in: 0..<1, using: &rng) < 0.25 ? index : (index + 1) % question.choices.count, now: now)
                } else {
                    run.type("999", now: now)
                }
                now += 2
                run.next(now: now)
            case .pickBook(let books):
                now += 10
                run.pickBook(books[0], now: now)
            case .read(let book, let minutes):
                now += Double(minutes) * 60
                run.finishReading(page: book.page + minutes * 2, finished: false, feel: nil, minutes: Double(minutes), now: now)
            case .reflect:
                now += 30
                run.reflect("The chapter turned on a choice the narrator didn't see coming.", now: now)
            case .passage:
                now += 60
                run.respond(.passageRead(seconds: 60), now: now)
            case .speak(let task):
                now += 6
                run.respond(.spoken(transcript: task.expected.first ?? "", seconds: 4), now: now)
            case .compose:
                now += 300
                run.respond(.written(text: "A short piece, written for the test.", source: .typed), now: now)
            case .compare:
                now += 30
                run.respond(.picked(1), now: now)
            }
            // What was said or written is marked before moving on, as Continue does on screen.
            if run.feedback != nil {
                now += 2
                run.next(now: now)
            }
        }
        run.finish(now: now)
        return now
    }

    func answerText(_ question: Question) -> String {
        guard case .number(let value, let tolerance) = question.answer else { return "" }
        return tolerance > 0 ? String(format: "%.2f", value.double) : value.description
    }
}

/// Keeps the records a run produces, the way the app's store would.
struct Store {
    var settings: MindSettings
    var cards: [CardKey: MemoryCard] = [:]
    var sessions: [StudySession] = []
    var tests: [TestResult] = []
    var books: [Book] = []
    var reflections: [Reflection] = []
    var pieces: [WritingPiece] = []
    var comparisons: [BlindComparison] = []
    var lifeModes: [LifeModePeriod] = []
    var calendar: SystemCalendar?

    func state(on day: Day, at hour: Double = 18) -> StudyState {
        StudyState(
            settings: settings, cards: Array(cards.values), sessions: sessions, tests: tests, books: books, reflections: reflections,
            pieces: pieces, comparisons: comparisons,
            lifeModes: lifeModes, calendar: calendar, today: day, now: day.date().addingTimeInterval(hour * 3600))
    }

    mutating func save(_ run: StudyRun) {
        for key in run.changedCards { cards[key] = run.cards[key] }
        sessions.append(run.session)
        tests += run.newTests
        for id in run.changedBooks {
            if let book = run.books.first(where: { $0.id == id }) {
                books.removeAll { $0.id == id }
                books.append(book)
            }
        }
        reflections += run.newReflections
        pieces += run.newPieces
        comparisons += run.newComparisons
    }

    /// Runs today's planned session, if there is one, with the student.
    @discardableResult
    mutating func study(on day: Day, student: inout Student, deck: LanguageDeck) -> StudyRun? {
        let state = state(on: day)
        guard let plan = SessionPlanner.today(state, catalogs: Fixtures.catalogs(deck)) else { return nil }
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        _ = student.run(&run, from: state.now)
        save(run)
        return run
    }
}

// The fixtures' days start at midnight (`Fixtures.settings`), so a record's day is its calendar day.
extension StudySession {
    var day: Day { day(startingAt: 0) }
}

extension TestResult {
    var day: Day { day(startingAt: 0) }
}

extension WritingPiece {
    var day: Day { day(startingAt: 0) }
}
