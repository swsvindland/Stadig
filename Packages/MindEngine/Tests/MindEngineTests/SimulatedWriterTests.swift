import Foundation
import SystemCore
import Testing

@testable import MindEngine

/// A simulated writer: pieces whose slips fall and sentences vary more week by week when they're
/// improving, and stay the same when they aren't. In a blind pair they pick the piece with fewer
/// slips, as a careful reader would; with nothing between them, it's a coin toss.
struct Writer {
    var improving: Bool
    var rng: SeededRandom
    static let pool = [
        "river", "lamp", "window", "garden", "winter", "letter", "kitchen", "station", "morning", "silence", "road", "cloud",
        "table", "voice", "bridge", "stone", "harbour", "market", "candle", "orchard", "ladder", "engine", "pocket", "mirror",
        "walked", "waited", "turned", "carried", "opened", "watched", "slowly", "later", "under", "across", "behind", "quiet",
        "bright", "narrow", "heavy", "early", "kettle", "platform", "ticket", "neighbour", "promise", "answer", "reason",
        "evening", "corner", "street", "doorway", "shadow", "sister", "brother", "teacher", "stranger", "coat", "glass",
    ]

    mutating func text(week: Int) -> String {
        let slipRate = improving ? max(0.02, 0.5 - 0.025 * Double(week)) : 0.3
        let spread = improving ? 2 + week / 2 : 3
        var sentences: [String] = []
        var words = 0
        while words < 110 {
            let length = max(3, 10 + Int.random(in: -spread...spread, using: &rng))
            var sentence: [String] = []
            for _ in 0..<length {
                let word = rng.pick(Self.pool)
                if word != sentence.last { sentence.append(word) }
            }
            if rng.chance(slipRate) {
                switch rng.int(0...2) {
                case 0: sentence.insert(contentsOf: ["could", "of"], at: 1)
                case 1: sentence.append("recieve")
                default: sentence.insert(contentsOf: ["a", "apple"], at: 1)
                }
            }
            words += sentence.count
            sentences.append(sentence.joined(separator: " ").capitalisedFirst + ".")
        }
        return sentences.joined(separator: " ")
    }

    mutating func pick(_ pair: BlindPair) -> Int {
        let a = WritingCheck.measure(pair.first.text, misspelled: ["recieve"]).errorsPer100
        let b = WritingCheck.measure(pair.second.text, misspelled: ["recieve"]).errorsPer100
        // Too close to call: a coin toss for newer or older, whichever side each is shown on.
        if abs(a - b) < 1 { return rng.chance(0.5) == (pair.first.id == pair.newer.id) ? 0 : 1 }
        return a < b ? 0 : 1
    }
}

@Suite("Simulated writers")
struct SimulatedWriterTests {
    let deck = Fixtures.deck(words: 200, sentences: 200)

    struct Result {
        var store: Store
        var plans: [(day: Day, plan: SessionPlan)]
    }

    /// Twenty weeks of maths and writing, five days a week, writing creative and practical pieces.
    func run(_ writer: Writer) -> Result {
        var writer = writer
        var settings = Fixtures.settings([.maths, .writing])
        settings.writingKinds = [.creative, .practical]
        var store = Store(settings: settings)
        var student = Student(vocabulary: 0, mathsLevel: 4, writingLevel: 2, deck: deck)
        let catalogs = Catalogs()
        var plans: [(day: Day, plan: SessionPlan)] = []
        for offset in 0..<140 {
            let day = Fixtures.monday.adding(days: offset)
            let state = store.state(on: day)
            guard let plan = SessionPlanner.checkIns(state, catalogs: catalogs).first ?? SessionPlanner.today(state, catalogs: catalogs) else {
                continue
            }
            plans.append((day, plan))
            var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
            var now = state.now
            var steps = 0
            while let step = run.step, steps < 2000 {
                steps += 1
                switch step {
                case .lesson:
                    now += 20
                    run.next(now: now)
                case .question(let question):
                    now += max(1, question.expectedSeconds * 0.8)
                    if student.knows(question, cards: run.cards, now: now) == true, let index = question.correctChoice {
                        run.choose(index, now: now)
                    } else if let index = question.correctChoice {
                        run.choose((index + 1) % question.choices.count, now: now)
                    } else {
                        run.type(student.answerText(question), now: now)
                    }
                    now += 2
                    run.next(now: now)
                case .compose(let task):
                    now += Double(task.minutes) * 60
                    if task.reviewing != nil {
                        run.respond(.skip, now: now)
                    } else if task.exercise == .franklinNotes {
                        run.submitWriting("garden; a letter; the station at night", source: .typed, misspelled: [], now: now)
                    } else {
                        run.submitWriting(writer.text(week: offset / 7), source: .typed, misspelled: ["recieve"], now: now)
                    }
                case .compare(let pair):
                    now += 120
                    run.respond(.picked(writer.pick(pair)), now: now)
                default:
                    now += 30
                    run.skipPart(now: now)
                }
            }
            run.finish(now: now)
            store.save(run)
        }
        return Result(store: store, plans: plans)
    }

    @Test("twenty weeks: every exercise for both kinds, Franklin rewrites days after the notes, a benchmark a term, and blind pairs at check-ins")
    func term() throws {
        let result = run(Writer(improving: true, rng: SeededRandom(seed: 7)))
        let store = result.store
        let pieces = store.pieces
        let exercises = Set(pieces.map(\.exercise))
        #expect(exercises.isSuperset(of: [.prompt, .practical, .franklinNotes, .franklinRewrite, .sceneRewrite, .benchmark]), "\(exercises)")
        #expect(Set(pieces.filter { $0.exercise.composes && $0.exercise != .benchmark }.map(\.writingKind)) == [.creative, .practical])

        // Every set of notes was rewritten in a later session, at least two days on, from the same passage.
        let notes = pieces.filter { $0.exercise == .franklinNotes }
        for note in notes.dropLast() {
            let rewrite = try #require(pieces.first { $0.exercise == .franklinRewrite && $0.taskID == note.taskID && $0.date > note.date })
            #expect(note.day.days(until: rewrite.day) >= WritingSchedule.franklinGap)
            #expect(rewrite.notes == note.notes)
        }

        // The first benchmark during the assessment, the next a term later at a check-in.
        let benchmarks = pieces.filter { $0.exercise == .benchmark }
        #expect(benchmarks.count == 2, "\(benchmarks.map(\.day))")
        #expect(Fixtures.monday.days(until: benchmarks[0].day) < StudyCalendar.assessmentDays)
        let checkIns = result.plans.filter { $0.plan.kind == .checkIn }
        #expect(checkIns.count >= 2)
        #expect(checkIns.contains { $0.day == benchmarks[1].day })
        #expect(benchmarks[0].day.days(until: benchmarks[1].day) >= WritingSchedule.benchmarkGap)

        // Blind comparisons only at check-ins, never the same pair twice, the benchmarks among them.
        #expect(store.comparisons.count >= 3, "\(store.comparisons.count) comparisons")
        let checkInDays = Set(checkIns.map(\.day))
        #expect(store.comparisons.allSatisfy { checkInDays.contains(Day($0.date)) })
        #expect(Set(store.comparisons.map { "\($0.older)\($0.newer)" }).count == store.comparisons.count)
        #expect(store.comparisons.contains { $0.older == benchmarks[0].id && $0.newer == benchmarks[1].id })
        #expect(store.tests.filter { $0.test == .blindComparison }.count == store.comparisons.count)

        // Nothing new in a review week: pieces are written in regular sessions and check-ins only.
        for plan in result.plans where plan.plan.kind == .review {
            #expect(!pieces.contains { $0.day == plan.day }, "a piece written on \(plan.day) in a review week")
            #expect(!plan.plan.parts.contains { $0.kind == .custom(WritingModule.compose) || $0.kind == .learn })
        }
        // Grammar keeps a share while skills are left, and sessions stay about their length.
        #expect(result.plans.contains { $0.plan.parts.contains { $0.kind == .learn && $0.domain == .writing } })
        let minutes = store.sessions.filter { $0.purpose == .regular }.map(\.minutes)
        #expect(minutes.reduce(0, +) / Double(minutes.count) < 32, "\(minutes.reduce(0, +) / Double(minutes.count)) minutes on average")

        // The improving writer: fewer slips as a trend, the newer piece picked, and the score up.
        let trends = WritingProgress.trends(pieces)
        #expect(trends.first { $0.metric == .slips }?.direction == .better)
        #expect(trends.first { $0.metric == .variety }?.direction == .better)
        let record = WritingProgress.record(store.comparisons)
        #expect(record.newerPicked * 2 > record.judged, "\(record)")
        #expect(WritingProgress.craft(store.comparisons) > WritingProgress.craftStart)
        let series = WritingModule.series(.writing, state: store.state(on: Fixtures.monday.adding(days: 140)))
        #expect(series.last!.score > series.first!.score, "\(series.map(\.score))")
    }

    @Test("a writer who isn't improving doesn't gain on pieces written or time spent")
    func plateau() {
        let improving = run(Writer(improving: true, rng: SeededRandom(seed: 7))).store
        let flat = run(Writer(improving: false, rng: SeededRandom(seed: 7))).store
        #expect(flat.pieces.count >= improving.pieces.count - 2, "both wrote about as much")
        // Nothing to tell the pieces apart, so the picks are a coin toss and craft wanders near the start.
        let craft = WritingProgress.craft(flat.comparisons)
        #expect(abs(craft - WritingProgress.craftStart) <= 3 * WritingProgress.craftStep, "\(craft)")
        #expect(WritingProgress.trends(flat.pieces).allSatisfy { $0.direction == .steady }, "\(WritingProgress.trends(flat.pieces).map(\.direction))")
    }
}
