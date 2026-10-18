#if DEBUG
import Foundation
import MindEngine
import SystemCore

/// Eight and a half weeks of study for checking screens: every session planned by the real planner
/// and run by the real session engine, answered by a student who gets most things right, through
/// the assessment, a block, a review week and its check-in.
enum SampleData {
    @MainActor
    static func seedIfEmpty(_ model: AppModel) {
        guard model.settings == nil else { return }
        let today = Day.today
        let start = today.adding(days: -60)
        let ladder = ReadingLadder.standard
        var settings = MindSettings(schedule: StudySchedule(daysPerWeek: 5), onboardedAt: start.date(), readsKana: true,
                                    mathsStrands: [.numeracy, .discrete, .classic], genres: [.fantasy, .sciFi, .nonfiction])
        settings.updatedAt = start.date()
        var books = ladder.books.filter { ["mistborn-final-empire", "the-name-of-the-wind"].contains($0.id) }.map { $0.book(status: .readBefore) }
        if books.isEmpty { books = ladder.books.filter { $0.tier == 3 }.prefix(2).map { $0.book(status: .readBefore) } }
        var cards: [CardKey: MemoryCard] = [:]
        var sessions: [StudySession] = []
        var tests: [TestResult] = []
        var reflections: [Reflection] = []
        var pieces: [WritingPiece] = []
        var rng = SeededRandom(seed: 2026)

        for offset in 0..<60 {
            let day = start.adding(days: offset)
            // A missed day now and then.
            if offset > 20 && rng.chance(0.08) { continue }
            let state = StudyState(settings: settings, cards: Array(cards.values), sessions: sessions, tests: tests, books: books,
                                   reflections: reflections, pieces: pieces, today: day, now: day.date().addingTimeInterval(18.5 * 3600))
            guard let plan = SessionPlanner.today(state, catalogs: model.catalogs) else { continue }
            var run = StudyRun(plan: plan, state: state, catalogs: model.catalogs, now: state.now)
            var now = state.now
            var steps = 0
            while let step = run.step, steps < 600 {
                steps += 1
                switch step {
                case .lesson:
                    now += 25
                    run.next(now: now)
                case .question(let question):
                    now += question.expectedSeconds * Double.random(in: 0.6...1.3, using: &rng)
                    let p = chance(question, cards: run.cards, catalogs: model.catalogs)
                    if question.allowsDontKnow && p < 0.3 && rng.chance(0.7) {
                        run.dontKnow(now: now)
                        now += 3
                        run.next(now: now)
                        continue
                    }
                    let right = rng.chance(p)
                    if let index = question.correctChoice {
                        run.choose(right ? index : (index + 1) % question.choices.count, now: now)
                    } else if right, case .number(let value, let tolerance) = question.answer {
                        run.type(tolerance > 0 ? String(format: "%.2f", value.double) : value.description, now: now)
                    } else {
                        run.type("0", now: now)
                    }
                    now += 3
                    run.next(now: now)
                case .pickBook(let options):
                    now += 20
                    if let pick = options.first { run.pickBook(pick, now: now) } else { run.skipPart(now: now) }
                case .read(let book, let minutes):
                    now += Double(minutes) * 60
                    let page = book.page + minutes * 2 + rng.int(0...10)
                    let finished = page >= book.pages
                    run.finishReading(page: page, finished: finished, feel: finished ? .right : nil, minutes: Double(minutes), now: now)
                case .reflect(_, let finished):
                    now += 60
                    run.reflect(rng.pick(finished ? bookNotes : sectionNotes), now: now)
                case .passage(let passage):
                    now += Double(passage.words) / 4
                    run.respond(.passageRead(seconds: Double(passage.words) / 4), now: now)
                case .speak:
                    now += 10
                    run.respond(.skip, now: now)
                case .compose(let task):
                    now += Double(task.minutes) * 60
                    run.respond(.written(text: rng.pick(sectionNotes), source: .typed), now: now)
                case .compare:
                    now += 90
                    run.respond(.picked(1), now: now)
                }
            }
            run.finish(now: now)
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
        }
        tests.append(TestResult(test: .episode, date: start.adding(days: 52).date().addingTimeInterval(21 * 3600), score: 1.0 / 3,
                                detail: ["rating": 1], language: .japanese))
        model.seed(settings: settings, cards: Array(cards.values), sessions: sessions, tests: tests, books: books, reflections: reflections,
                   pieces: pieces)
    }

    /// The sample student: about 600 Japanese words to begin with; numeracy quick to level 6,
    /// algebra solid to level 5 and statistics to 3, shakier above; and the basic writing skills.
    static func chance(_ question: Question, cards: [CardKey: MemoryCard], catalogs: Catalogs) -> Double {
        let key = question.key
        switch key.domain {
        case .japanese, .spanish:
            if key.wordID == nil && !key.isKana { return 0.6 }
            if let memory = cards[key]?.memory { return min(0.95, Scheduler.retrievability(memory, at: Date()) + 0.05) }
            if let id = key.wordID, let word = catalogs.deck(for: key.domain)?.word(id), word.rank <= 600 { return 0.92 }
            return question.kind == .learn ? 0.85 : 0.25
        case .maths:
            if let numeracy = key.numeracy { return numeracy.level <= 6 ? 0.92 : numeracy.level == 7 ? 0.5 : 0.15 }
            let topic = MathCurriculum.topic(key.item)
            let level = topic?.level ?? 10, solid = topic?.strand == .discrete ? 3 : 5
            if level <= solid { return 0.92 }
            if question.kind == .test && cards[key]?.memory == nil { return 0.2 }
            return level <= solid + 2 ? 0.8 : 0.55
        case .writing:
            let level = WritingBank.standard.skill(key.item)?.level ?? 3
            return [0.92, 0.8, 0.65][min(2, max(0, level - 1))]
        case .reading:
            return 1
        }
    }

    /// Eight weeks of what Lift Track and Macro Track would publish: steps most days, strength
    /// three days a week, and food logged on most days with protein hit on about two in three.
    static func systemData(ending today: Day) -> SystemData {
        var rng = SeededRandom(seed: 314)
        var steps: [SystemData.Point] = [], training: [SystemData.Point] = [], protein: [SystemData.Point] = []
        var hits: [Day: Bool] = [:]
        for offset in 1...56 {
            let day = today.adding(days: -offset)
            let trains = [.monday, .wednesday, .friday].contains(day.weekday)
            let weekend = day.weekday == .saturday || day.weekday == .sunday
            if rng.chance(0.93) { steps.append(.init(day: day, value: Double(rng.int(5200...9800) + (weekend ? 1800 : 0) + (trains ? 600 : 0)))) }
            if trains && rng.chance(0.9) { training.append(.init(day: day, value: Double(rng.int(50...75)))) }
            if offset <= 28 && rng.chance(0.85) {
                let grams = Double(rng.int(110...190))
                protein.append(.init(day: day, value: grams))
                hits[day] = grams >= 140
            }
        }
        return SystemData(steps: steps, training: training, protein: protein, proteinHits: hits)
    }

    static let sectionNotes = [
        "The heist plan finally came together, and the cost of it is starting to show.",
        "A slow chapter, but the history of the place explains why everyone distrusts the council.",
        "I hadn't noticed how unreliable the narrator is until the letter contradicted him.",
        "Two characters said the same thing for opposite reasons. That felt deliberate.",
    ]
    static let bookNotes = [
        "Better than I expected: the ending reframed everything about the first act.",
        "Hard going in the middle, worth it for the last hundred pages.",
    ]
}
#endif
