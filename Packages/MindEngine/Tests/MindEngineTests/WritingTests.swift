import Foundation
import SystemCore
import Testing

@testable import MindEngine

enum WritingFixtures {
    static func words(_ count: Int, from seed: String = "") -> String {
        let pool = [
            "river", "lamp", "window", "garden", "winter", "letter", "kitchen", "station", "morning", "silence", "road", "cloud",
            "table", "voice", "bridge", "stone", "harbour", "market", "candle", "orchard", "ladder", "engine", "pocket", "mirror",
        ]
        var rng = SeededRandom("words", seed)
        var body: [String] = []
        while body.count < count {
            let word = rng.pick(pool)
            if word != body.last { body.append(word) }
        }
        return body.chunked(8).map { $0.joined(separator: " ").capitalisedFirst + "." }.joined(separator: " ")
    }

    static let library = WritingLibrary(
        passages: [
            WritingPassage(
                id: "creative-one", title: "Book One", author: "A. Writer", book: "pride-and-prejudice", kinds: [.creative], tier: 5,
                text: words(150, from: "c1"), twists: ["Rewrite it from the sister’s point of view.", "Tell it in the present tense."]),
            WritingPassage(
                id: "creative-two", title: "Book Two", author: "B. Writer", kinds: [.creative], tier: 4, text: words(140, from: "c2"),
                twists: ["Make the weather turn."]),
            WritingPassage(id: "practical-one", title: "Book Three", author: "C. Writer", kinds: [.practical], tier: 4, text: words(130, from: "p1")),
            WritingPassage(id: "argument-one", title: "Book Four", author: "D. Writer", kinds: [.argument], tier: 5, text: words(160, from: "a1")),
        ],
        prompts: [
            WritingPrompt(id: "creative-a", exercise: .prompt, writingKind: .creative, text: "A café closes for good."),
            WritingPrompt(id: "creative-b", exercise: .prompt, writingKind: .creative, text: "A book forty years overdue."),
            WritingPrompt(id: "creative-c", exercise: .prompt, writingKind: .creative, text: "Three in the morning at a service station."),
            WritingPrompt(id: "argument-a", exercise: .argument, writingKind: .argument, text: "Should cities ban cars?"),
            WritingPrompt(
                id: "practical-a", exercise: .practical, writingKind: .practical, text: "Make the ask clear.", source: words(60, from: "s1")),
            WritingPrompt(id: "practical-b", exercise: .practical, writingKind: .practical, text: "Drop the sarcasm.", source: words(70, from: "s2")),
            WritingPrompt(id: "benchmark-creative", exercise: .benchmark, writingKind: .creative, text: "A place as it changes.", minutes: 12),
            WritingPrompt(
                id: "benchmark-practical", exercise: .benchmark, writingKind: .practical, text: "Ask the book club to choose.", minutes: 12),
            WritingPrompt(
                id: "benchmark-argument", exercise: .benchmark, writingKind: .argument, text: "A second language for everyone?", minutes: 12),
        ])

    static var catalogs: Catalogs {
        let bank = WritingBank.standard
        return Catalogs(writing: WritingBank(skills: bank.skills, items: bank.items, library: library))
    }

    static func settings(_ kinds: [WritingKind] = [.creative], domains: [Domain] = [.maths, .writing]) -> MindSettings {
        var settings = Fixtures.settings(domains)
        settings.writingKinds = kinds
        return settings
    }

    static func piece(
        _ exercise: WritingExercise, on day: Day, kind: WritingKind = .creative, taskID: String? = nil, words count: Int = 120,
        notes: String? = nil, text: String? = nil, id: UUID = UUID()
    ) -> WritingPiece {
        let body = exercise == .franklinNotes ? "" : text ?? words(count, from: "\(exercise)\(day.iso)")
        return WritingPiece(
            id: id, date: day.date().addingTimeInterval(18 * 3600), exercise: exercise, writingKind: kind, prompt: "Task \(taskID ?? "")",
            text: body, notes: notes, metrics: body.isEmpty ? [:] : WritingCheck.measure(body).dictionary, taskID: taskID)
    }

    static func state(
        _ settings: MindSettings, pieces: [WritingPiece] = [], comparisons: [BlindComparison] = [], tests: [TestResult] = [],
        books: [Book] = [], sessions: [StudySession] = [], on day: Day
    ) -> StudyState {
        StudyState(
            settings: settings, sessions: sessions, tests: tests, books: books, pieces: pieces, comparisons: comparisons, today: day,
            now: day.date().addingTimeInterval(18 * 3600))
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] { stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) } }
}

extension String {
    var capitalisedFirst: String { prefix(1).uppercased() + dropFirst() }
}

@Suite("Writing: the deterministic check")
struct WritingCheckTests {
    func notes(_ text: String, misspelled: [String] = []) -> [String] { WritingCheck.slips(text, misspelled: misspelled).map(\.note) }
    func marked(_ text: String, misspelled: [String] = []) -> [String] { WritingCheck.slips(text, misspelled: misspelled).map(\.text) }

    @Test("clean prose has no slips")
    func clean() {
        let text = """
            The café had been on the corner for thirty years. On its last night, Mr. Okafor stacked the chairs while one regular, \
            a retired teacher, finished her tea. “Will you miss it?” she asked. He said he would, and then he said he wouldn’t, \
            and they both laughed. An hour later the lights went out; a one-off, a European tour bus and an X-ray clinic were all \
            that the street had left. I’d rather stay than go, he thought. Prices were higher then, but the tea was better. \
            It got better then worse. He had had enough. iPhones lit the bus windows. See example.com for details... then nothing.
            - first item on the list
            """
        #expect(WritingCheck.slips(text).isEmpty, "\(WritingCheck.slips(text))")
    }

    @Test("each mechanical rule finds its slip")
    func rules() {
        #expect(marked("We went to the the shop.") == ["the the"])
        #expect(marked("Yesterday i went out, and i'm tired.") == ["i", "i'm"])
        #expect(marked("She ate a apple and an banana.") == ["a apple", "an banana"])
        #expect(marked("I could of gone. You should of said.") == ["could of", "should of"])
        #expect(marked("The might of Rome fell.").isEmpty)
        #expect(marked("I would rather then wait. There were more then 50 people.") == ["rather then", "more then"])
        #expect(marked("Hello , world. Hello,world.").count == 2)
        #expect(marked("It ended.Then it began again.") == ["."])
        #expect(marked("This is fine. this isn’t.") == ["this"])
        #expect(marked("“Where are you?” she asked. “Here!” He waved.").isEmpty)
        #expect(marked("Dr. Smith met J. K. Rowling. They talked.").isEmpty)
        #expect(notes("We have alot to do.") == ["“a lot” is two words"])
        #expect(marked("Wait,, what.. no.").count == 2)
    }

    @Test("spelling comes from the platform, and capitalised words are never counted")
    func spelling() {
        let slips = WritingCheck.slips(
            "I recieve letters from Svindland. Recieve them? I recieve them.", misspelled: ["recieve", "Svindland", "Recieve"])
        #expect(slips.map(\.text) == ["recieve", "recieve"])
        #expect(slips.allSatisfy { $0.kind == .spelling })
        // A rule's note beats "check the spelling" for the same words.
        #expect(WritingCheck.slips("We have alot.", misspelled: ["alot"]).map(\.kind) == [.mechanics])
    }

    @Test("slips per 100 words, vocabulary range and sentence-length variety")
    func metrics() throws {
        let text = WritingFixtures.words(50, from: "m") + " We could of gone. I recieve it."
        let metrics = WritingCheck.measure(text, misspelled: ["recieve"])
        #expect(metrics.words == 57)
        #expect(metrics.slips == 2)
        #expect(abs(metrics.errorsPer100 - 200.0 / 57) < 0.001)
        #expect(WritingCheck.measure("Too short to say.").vocabulary == nil)

        let distinct = (1...60).map { "word\($0)" }.joined(separator: " ") + "."
        #expect(WritingCheck.measure(distinct).vocabulary == 1)
        let repeated = Array(repeating: "again", count: 60).joined(separator: " ") + "."
        #expect(abs((WritingCheck.measure(repeated).vocabulary ?? 0) - 1.0 / 50) < 0.0001)
        // The window keeps it from falling just because a piece is longer.
        let once = WritingCheck.measure(WritingFixtures.words(120, from: "x")).vocabulary ?? 0
        let twice = WritingCheck.measure(WritingFixtures.words(480, from: "x")).vocabulary ?? 0
        #expect(abs(once - twice) < 0.05, "\(once) against \(twice)")

        let even = WritingCheck.measure("One two three four five. One two three four five. One two three four five.")
        #expect(even.sentences == 3 && even.sentenceSpread == 0 && even.sentenceMean == 5)
        let varied = WritingCheck.measure(
            "Go now. " + "One two three four five six seven eight nine ten. "
                + (1...18).map { "w\($0)" }.joined(separator: " ") + ".")
        #expect(varied.sentences == 3)
        #expect(abs((varied.sentenceSpread ?? 0) - 6.532) < 0.01)
        let dialogue = WritingCheck.measure("Dr. Jones met J. K. Rowling. They talked... about books. Then left!\nThe end")
        #expect(dialogue.sentences == 4)
    }
}

@Suite("Writing: the AI's notes and second opinion")
struct WritingCoachTests {
    @Test("notes keep two or three specific fixes and drop anything that grades")
    func notes() {
        let reply = """
            Here are my notes:
            - **“the the shop”**: one “the” is enough.
            1. “It was nice” tells rather than shows: name one thing she noticed, such as the steam on the window.
            * Overall I’d give this 7/10.
            - Grade: B+, a solid effort with room to grow.
            - Your second paragraph jumps from the café to the bus; add a sentence that takes us there.
            - A fourth note that should be cut because three is the most.
            """
        let notes = WritingCoach.notes(from: reply)
        #expect(notes.count == 3)
        #expect(notes[0] == "“the the shop”: one “the” is enough.")
        #expect(notes.allSatisfy { !$0.contains("7/10") && !$0.contains("Grade") })
        #expect(WritingCoach.notes(from: "Score: 85%\nGreat!").isEmpty)
    }

    @Test("the blind pick reads the letter, and both orders must agree")
    func pick() {
        #expect(WritingCoach.pick(from: "A\nClearer throughout.") == 0)
        #expect(WritingCoach.pick(from: "**B**. It flows better.") == 1)
        #expect(WritingCoach.pick(from: "\nPiece B is stronger.") == 1)
        #expect(WritingCoach.pick(from: "A clearer piece is the second one.") == nil)
        #expect(WritingCoach.pick(from: "Both are good.") == nil)
        #expect(WritingCoach.pick(from: "A rambles in the middle.\nB ends abruptly.\nStronger: B") == 1)
        #expect(WritingCoach.pick(from: "A: vague.\nB: flat.\n**Stronger: piece A**") == 0)

        let old = WritingFixtures.piece(.prompt, on: Fixtures.monday)
        let new = WritingFixtures.piece(.prompt, on: Fixtures.monday.adding(days: 50))
        let pair = WritingSchedule.pair(old, new)
        let newerIndex = pair.first.id == new.id ? 0 : 1
        #expect(WritingCoach.secondOpinion(pair, shown: newerIndex, swapped: 1 - newerIndex) == true)
        #expect(WritingCoach.secondOpinion(pair, shown: 1 - newerIndex, swapped: newerIndex) == false)
        // Position bias: "A" both times is no opinion.
        #expect(WritingCoach.secondOpinion(pair, shown: 0, swapped: 0) == nil)
        #expect(WritingCoach.secondOpinion(pair, shown: nil, swapped: 1 - newerIndex) == true)
        #expect(WritingCoach.comparisonPrompt(pair, swapped: false).contains(pair.first.text))
    }

    @Test("the feedback prompt carries the task, the source and what the checker already marked")
    func prompt() {
        var piece = WritingFixtures.piece(.practical, on: Fixtures.monday, kind: .practical, text: "We could of met.")
        piece.prompt = "Make the ask clear."
        let prompt = WritingCoach.prompt(piece, source: "re the thing", slips: WritingCheck.slips(piece.text))
        #expect(prompt.contains("Make the ask clear.") && prompt.contains("re the thing") && prompt.contains("“could of”"))
        #expect(!WritingCoach.instructions(for: .prompt).isEmpty && WritingCoach.instructions(for: .franklinRewrite).contains("Franklin"))
    }
}

@Suite("Writing: what each session holds")
struct WritingScheduleTests {
    let library = WritingFixtures.library
    let day = Fixtures.monday.adding(days: 30)

    func next(_ kinds: [WritingKind], pieces: [WritingPiece], on day: Day? = nil, books: [Book] = []) -> WritingTask? {
        WritingSchedule.task(
            WritingFixtures.state(WritingFixtures.settings(kinds), pieces: pieces, books: books, on: day ?? self.day), minutes: 8,
            library: library)
    }

    @Test("each kind rotates its exercises, and kinds take turns")
    func rotation() throws {
        var pieces: [WritingPiece] = []
        var seen: [String] = []
        for i in 0..<6 {
            let task = try #require(next([.creative], pieces: pieces, on: day.adding(days: i * 3)))
            seen.append(task.exercise.rawValue)
            pieces.append(WritingFixtures.piece(task.exercise, on: day.adding(days: i * 3), taskID: task.taskID, notes: "notes"))
            if task.exercise == .franklinNotes {
                pieces.append(WritingFixtures.piece(.franklinRewrite, on: day.adding(days: i * 3 + 1), taskID: task.taskID))
            }
        }
        #expect(seen == ["prompt", "franklinNotes", "prompt", "sceneRewrite", "prompt", "franklinNotes"])

        var mixed: [WritingPiece] = []
        var kinds: [WritingKind] = []
        for i in 0..<4 {
            let task = try #require(next([.creative, .practical], pieces: mixed, on: day.adding(days: i * 3)))
            kinds.append(task.writingKind)
            mixed.append(WritingFixtures.piece(task.exercise, on: day.adding(days: i * 3), kind: task.writingKind, taskID: task.taskID))
            if task.exercise == .franklinNotes {
                mixed.append(WritingFixtures.piece(.franklinRewrite, on: day.adding(days: i * 3 + 1), kind: task.writingKind, taskID: task.taskID))
            }
        }
        #expect(kinds == [.creative, .practical, .creative, .practical])
        #expect(try #require(next([.practical], pieces: [])).source != nil, "a practical task brings the text to rewrite")
    }

    @Test("Franklin: notes now, the rewrite at least two days later from the notes alone, then the original beside it")
    func franklin() throws {
        let notes = WritingFixtures.piece(.franklinNotes, on: day, taskID: "creative-two", notes: "garden; winter; a letter")
        #expect(WritingSchedule.franklinDue([notes], today: day.adding(days: 1)) == nil)
        let rewrite = try #require(next([.creative], pieces: [notes], on: day.adding(days: 2)))
        #expect(rewrite.exercise == .franklinRewrite)
        #expect(rewrite.notes == "garden; winter; a letter")
        #expect(rewrite.source == library.passage("creative-two")?.text)
        #expect(!rewrite.showsSource, "the original stays hidden while rewriting")
        var reviewing = rewrite
        reviewing.reviewing = UUID()
        #expect(reviewing.showsSource)

        // No second set of notes while one is waiting: the rotation moves on.
        #expect(next([.creative], pieces: [notes], on: day.adding(days: 1))?.exercise == .prompt)

        // Notes taken on a page of the person's own book are rewritten against that page.
        var own = notes
        own.original = "My own page, scanned."
        own.taskID = "own.\(own.id)"
        #expect(next([.creative], pieces: [own], on: day.adding(days: 3))?.source == "My own page, scanned.")
    }

    @Test("Franklin passages come from the book being read when there's one, else near its tier")
    func passages() throws {
        let reading = Book(
            ladderID: "pride-and-prejudice", title: "Pride and Prejudice", author: "Jane Austen", tier: 5, pages: 400,
            genres: [.classics], status: .reading)
        let prompt = WritingFixtures.piece(.prompt, on: day.adding(days: -3), taskID: "creative-a")
        let task = try #require(next([.creative], pieces: [prompt], books: [reading]))
        #expect(task.exercise == .franklinNotes && task.taskID == "creative-one")
    }

    @Test("prompts don't repeat until every one has been used")
    func freshPrompts() throws {
        var pieces: [WritingPiece] = []
        var used: [String] = []
        for i in 0..<4 {
            let state = WritingFixtures.state(WritingFixtures.settings(), pieces: pieces, on: day.adding(days: i))
            let task = try #require(WritingSchedule.task(.prompt, kind: .creative, state: state, minutes: 8, library: library))
            used.append(task.taskID!)
            pieces.append(WritingFixtures.piece(.prompt, on: day.adding(days: i), taskID: task.taskID))
        }
        #expect(Set(used.prefix(3)).count == 3)
        #expect(used[3] == used[0], "the least recently used comes back first")
        #expect(try #require(next([.creative], pieces: [])).instruction.hasSuffix("Write one or two paragraphs."))
    }

    @Test("a benchmark first, then once a term at a check-in")
    func benchmark() throws {
        let catalogs = WritingFixtures.catalogs
        var tests = [TestResult(test: .writing, date: Fixtures.monday.date(), score: 0.7, placement: true)]
        let first = WritingFixtures.state(WritingFixtures.settings(), tests: tests, on: day)
        let plan = SessionPlanner.plan(.regular, domains: [.writing], state: first, catalogs: catalogs)
        #expect(plan.parts.contains { $0.kind == .test(.writingBenchmark) && $0.minutes == 12 }, "\(plan.parts)")

        let benchmark = WritingFixtures.piece(.benchmark, on: day, taskID: "benchmark-creative")
        let later = WritingFixtures.state(WritingFixtures.settings(), pieces: [benchmark], tests: tests, on: day.adding(days: 3))
        #expect(
            !SessionPlanner.plan(.regular, domains: [.writing], state: later, catalogs: catalogs).parts.contains {
                $0.kind == .test(.writingBenchmark)
            })

        tests.append(TestResult(test: .writing, date: day.adding(days: 40).date(), score: 0.8))
        let sixWeeks = WritingFixtures.state(WritingFixtures.settings(), pieces: [benchmark], tests: tests, on: day.adding(days: 42))
        #expect(!WritingModule.checkInParts(.writing, state: sixWeeks, catalogs: catalogs).contains { $0.kind == .test(.writingBenchmark) })
        let term = WritingFixtures.state(WritingFixtures.settings(), pieces: [benchmark], tests: tests, on: day.adding(days: 84))
        let parts = WritingModule.checkInParts(.writing, state: term, catalogs: catalogs)
        #expect(
            parts.map(\.kind) == [.test(.writing), .test(.writingBenchmark), .test(.blindComparison)],
            "the new benchmark is set beside last term's: \(parts)")
    }

    @Test("blind pairs: older and newer of the same exercise, five weeks apart, in a fixed random order, never twice")
    func pairs() throws {
        let start = Fixtures.monday
        let oldPrompt = WritingFixtures.piece(.prompt, on: start, taskID: "creative-a")
        let oldPractical = WritingFixtures.piece(.practical, on: start, kind: .practical, taskID: "practical-a")
        let notes = WritingFixtures.piece(.franklinNotes, on: start, taskID: "creative-one", notes: "notes")
        let short = WritingFixtures.piece(.prompt, on: start.adding(days: 60), words: 20)
        let newPrompt = WritingFixtures.piece(.prompt, on: start.adding(days: 60), taskID: "creative-b")
        let tooClose = WritingFixtures.piece(.practical, on: start.adding(days: 20), kind: .practical)
        let today = start.adding(days: 62)
        let pieces = [oldPrompt, oldPractical, notes, short, newPrompt, tooClose]

        let pairs = WritingSchedule.pairs(pieces, comparisons: [], today: today)
        #expect(pairs.count == 1)
        let pair = try #require(pairs.first)
        #expect(pair.older.id == oldPrompt.id && pair.newer.id == newPrompt.id)
        #expect(WritingSchedule.pairs(pieces, comparisons: [], today: today).first == pair, "the same order every time")

        let done = BlindComparison(date: today.date(), older: oldPrompt.id, newer: newPrompt.id, pickedNewer: true)
        #expect(WritingSchedule.pairs(pieces, comparisons: [done], today: today).isEmpty)

        // Over many pairs the newer piece lands first about half the time. Fixed ids, so the count is
        // the same on every run.
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
        let firsts = (0..<200).map { i -> Bool in
            let a = WritingFixtures.piece(.prompt, on: start, id: id(2 * i))
            let b = WritingFixtures.piece(.prompt, on: start.adding(days: 50 + i % 3), id: id(2 * i + 1))
            let pair = WritingSchedule.pair(a, b)
            return pair.first.id == b.id
        }
        #expect((80...120).contains(firsts.filter { $0 }.count), "\(firsts.filter { $0 }.count) of 200")

        let benchmarks = [
            WritingFixtures.piece(.benchmark, on: start, taskID: "benchmark-creative"),
            WritingFixtures.piece(.benchmark, on: start.adding(days: 84), taskID: "benchmark-creative"),
        ]
        let benchmarkPair = try #require(WritingSchedule.pairs(benchmarks, comparisons: [], today: start.adding(days: 84)).first)
        #expect(benchmarkPair.older.id == benchmarks[0].id && benchmarkPair.prompt.contains("same prompt"))
    }
}

@Suite("Writing: sessions")
struct WritingSessionTests {
    let catalogs = WritingFixtures.catalogs
    let day = Fixtures.monday.adding(days: 20)
    var placed: [TestResult] { [TestResult(test: .writing, date: Fixtures.monday.date(), score: 0.7, placement: true)] }

    /// Past the grammar part, if the plan has one, to the piece of writing.
    func toWriting(_ run: inout StudyRun, at now: Date) {
        while run.currentPart.map({ $0.kind != .custom("writing") }) ?? false { run.skipPart(now: now) }
    }

    @Test("write, hand in with the spell checker's words, then see it back with notes")
    func compose() throws {
        let benchmark = WritingFixtures.piece(.benchmark, on: Fixtures.monday, taskID: "benchmark-creative")
        let state = WritingFixtures.state(WritingFixtures.settings(), pieces: [benchmark], tests: placed, on: day)
        let plan = SessionPlanner.plan(.regular, domains: [.writing], state: state, catalogs: catalogs)
        #expect(plan.parts.last?.kind == .custom("writing"))
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        toWriting(&run, at: state.now)
        guard case .compose(let task) = run.step else {
            Issue.record("\(String(describing: run.step))")
            return
        }
        #expect(task.exercise == .prompt && task.reviewing == nil)

        let text = WritingFixtures.words(80) + " I recieve it and we could of gone."
        run.submitWriting(text, source: .handwritten, misspelled: ["recieve"], now: state.now + 600)
        guard case .compose(let review) = run.step, let id = review.reviewing else {
            Issue.record("no review step")
            return
        }
        let piece = try #require(run.piece(id))
        #expect(piece.source == .handwritten && piece.text == text && piece.taskID == task.taskID)
        #expect(piece.metrics[WritingMetrics.Key.slips] == 2)

        run.attachFeedback("- One fix.\n- Another fix.", to: id)
        #expect(run.piece(id)?.feedbackItems == ["- One fix.", "- Another fix."])
        run.respond(.skip, now: state.now + 700)
        #expect(run.isComplete || run.currentPart?.kind != .custom("writing"))
        #expect(run.newPieces.count == 1 && run.newTests.isEmpty)
    }

    @Test("Franklin notes are kept for later with nothing to review")
    func franklinNotes() throws {
        let earlier = [
            WritingFixtures.piece(.benchmark, on: Fixtures.monday, taskID: "benchmark-creative"),
            WritingFixtures.piece(.prompt, on: Fixtures.monday.adding(days: 3), taskID: "creative-a"),
        ]
        let state = WritingFixtures.state(WritingFixtures.settings(), pieces: earlier, tests: placed, on: day)
        var run = StudyRun(
            plan: SessionPlanner.plan(.regular, domains: [.writing], state: state, catalogs: catalogs), state: state,
            catalogs: catalogs, now: state.now)
        toWriting(&run, at: state.now)
        guard case .compose(let task) = run.step, task.exercise == .franklinNotes else {
            Issue.record("\(String(describing: run.step))")
            return
        }
        run.submitWriting(
            "the garden; a letter; winter coming", source: .typed, misspelled: [], original: "A page of my own book.", now: state.now + 300)
        let notes = try #require(run.newPieces.first)
        #expect(notes.notes == "the garden; a letter; winter coming" && notes.text.isEmpty && notes.metrics.isEmpty)
        #expect(notes.original == "A page of my own book." && notes.taskID == "own.\(notes.id)")
        if case .compose = run.step { Issue.record("no review after notes") }
    }

    @Test("a check-in: the grammar check, the benchmark, then the new benchmark beside last term's")
    func checkIn() throws {
        let old = WritingFixtures.piece(.benchmark, on: Fixtures.monday, taskID: "benchmark-creative")
        let today = Fixtures.monday.adding(days: 84)
        let state = WritingFixtures.state(WritingFixtures.settings(), pieces: [old], tests: placed, on: today)
        let plan = SessionPlanner.plan(.checkIn, domains: [.writing], state: state, catalogs: catalogs)
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        var now = state.now
        var picked = false
        var steps = 0
        while let step = run.step, steps < 100 {
            steps += 1
            now += 20
            switch step {
            case .question(let question):
                run.choose(question.correctChoice ?? 0, now: now)
                run.next(now: now)
            case .compose(let task):
                if task.reviewing == nil {
                    #expect(task.exercise == .benchmark && task.minutes == 12)
                    now += 720
                    run.submitWriting(WritingFixtures.words(150, from: "new"), source: .typed, misspelled: [], now: now)
                } else {
                    run.respond(.skip, now: now)
                }
            case .compare(let pair):
                #expect(pair.older.id == old.id)
                let newer = pair.first.id == pair.newer.id ? 0 : 1
                run.respond(.picked(newer), now: now)
                picked = true
            default:
                run.skipPart(now: now)
            }
        }
        run.finish(now: now)
        #expect(picked)
        let comparison = try #require(run.newComparisons.first)
        #expect(comparison.pickedNewer == true && comparison.older == old.id)
        #expect(run.newTests.map(\.test) == [.writing, .writingBenchmark, .blindComparison])
        #expect(run.newTests.first { $0.test == .blindComparison }?.score == 1)
        #expect(run.newTests.first { $0.test == .writingBenchmark }?.detail[WritingMetrics.Key.words] == 150)
        run.attachSecondOpinion(false, older: comparison.older, newer: comparison.newer)
        #expect(run.newComparisons.first?.aiPickedNewer == false)
    }
}

@Suite("Writing: progress")
struct WritingProgressTests {
    @Test("metrics show as trends in words, from six pieces on")
    func trends() {
        let start = Fixtures.monday
        let base = WritingFixtures.words(100, from: "trend")
        let pieces = (0..<10).map { i -> WritingPiece in
            var piece = WritingFixtures.piece(.prompt, on: start.adding(days: i * 7), text: base)
            piece.metrics[WritingMetrics.Key.errors] = Double(10 - i)
            return piece
        }
        let trends = WritingProgress.trends(pieces)
        let slips = trends.first { $0.metric == .slips }!
        #expect(slips.direction == .better && slips.points.count == 10)
        #expect(slips.points.last!.value == (1 + 2 + 3 + 4 + 5) / 5.0)
        #expect(trends.first { $0.metric == .vocabulary }?.direction == .steady)
        #expect(WritingProgress.trends(Array(pieces.prefix(5))).allSatisfy { $0.direction == .notEnoughData })
        #expect(trends.allSatisfy { !$0.summary.contains { $0.isNumber } }, "trends only, in words")
    }

    @Test("the score moves only on the grammar check and blind comparisons")
    func score() {
        let start = Fixtures.monday
        let grammar = TestResult(test: .writing, date: start.date(), score: 0.8, placement: true)
        #expect(WritingProgress.series(tests: [grammar], comparisons: []).map(\.score) == [65])
        let wins = (1...3).map { BlindComparison(date: start.adding(days: 40 * $0).date(), older: UUID(), newer: UUID(), pickedNewer: true) }
        #expect(WritingProgress.series(tests: [grammar], comparisons: wins).last?.score == 72.5)
        // The AI disagreeing makes a comparison a draw.
        var split = wins
        for i in split.indices { split[i].aiPickedNewer = false }
        #expect(WritingProgress.series(tests: [grammar], comparisons: split).last?.score == 65)
        let losses = (1...20).map { BlindComparison(date: start.adding(days: $0).date(), older: UUID(), newer: UUID(), pickedNewer: false) }
        #expect(WritingProgress.craft(losses) == 0)

        let record = WritingProgress.record(split)
        #expect(record.judged == 3 && record.newerPicked == 3 && record.aiJudged == 3 && record.aiNewerPicked == 0 && record.agreed == 0)

        // Writing more doesn't move it.
        let state = WritingFixtures.state(
            WritingFixtures.settings(), pieces: (0..<30).map { WritingFixtures.piece(.prompt, on: start.adding(days: $0)) },
            tests: [grammar], on: start.adding(days: 30))
        #expect(WritingModule.series(.writing, state: state).map(\.score) == [65])
        #expect(WritingModule.label(.writing, state: state) == "Writing 65")
    }
}

extension WritingCheckTests {
    @Test("etc., et al. and initialisms run on into lower case without a false capital slip; etc. can still end a sentence")
    func runOnAbbreviations() {
        let text = "We packed tents, stoves, etc. and drove north. The U.S. and Canada agreed. Smith et al. found it in the Ph.D. thesis."
        #expect(WritingCheck.slips(text).isEmpty, "\(WritingCheck.slips(text))")
        #expect(WritingCheck.measure(text).sentences == 3)
        #expect(WritingCheck.measure("We packed stoves, etc. Then we left.").sentences == 2)
        #expect(notes("We stopped, etc. then we left.").isEmpty, "a run-on etc. is read as one sentence, as written")
        #expect(notes("I said no. then we left.").contains { $0.contains("capital") }, "no isn't an abbreviation")
    }
}

extension WritingScheduleTests {
    @Test("Franklin notes whose passage left the library don't hold up grammar or new notes")
    func orphanedNotes() throws {
        let notes = WritingFixtures.piece(.franklinNotes, on: day.adding(days: -5), taskID: "retired-passage", notes: "gone")
        #expect(WritingSchedule.waitingNotes([notes], library: library) == nil)
        #expect(WritingSchedule.franklinDue([notes], today: day, library: library) == nil)
        let held = WritingFixtures.piece(.franklinNotes, on: day.adding(days: -5), taskID: "creative-two", notes: "here")
        #expect(WritingSchedule.franklinDue([notes, held], today: day, library: library)?.id == held.id)

        // With only the orphan, the plan teaches grammar again and the rotation can take new notes.
        let state = WritingFixtures.state(
            WritingFixtures.settings(),
            pieces: [
                WritingFixtures.piece(
                    .benchmark, on: day.adding(days: -20),
                    taskID: "benchmark-creative"), notes,
            ], on: day)
        var noteTexts: [String] = []
        let parts = WritingModule.mainParts(
            .writing, minutes: 20, kind: .regular, state: state, catalogs: WritingFixtures.catalogs, notes: &noteTexts)
        #expect(parts.contains { $0.kind == .learn }, "\(parts.map(\.title))")
        #expect(WritingSchedule.task(state, minutes: 8, library: library)?.exercise != .franklinRewrite)
    }

    @Test("a skill in learning that the bank no longer has doesn't block the next one, in the plan or the session")
    func retiredSkill() throws {
        let bank = WritingFixtures.catalogs.writing
        let now = day.date()
        let retired = MemoryCard(key: .skill("retired-skill"), recent: [true], introduced: now - 86_400, updatedAt: now - 86_400)
        let cards = [retired.key: retired]
        let first = try #require(bank.skills.enumerated().min { ($0.element.level, $0.offset) < ($1.element.level, $1.offset) }?.element)
        #expect(WritingPlan.next(cards, bank: bank)?.id == first.id)
        #expect(WritingPlan.candidates(cards, bank: bank).first?.id == first.id)

        let state = StudyState(settings: WritingFixtures.settings(), cards: [retired], today: day, now: now)
        let plan = SessionPlan(
            day: day, kind: .regular, minutes: 5, domains: [.writing],
            parts: [PlanPart(kind: .learn, domain: .writing, minutes: 5, title: "Grammar", detail: "")], headline: "", notes: [],
            planned: true)
        let run = StudyRun(plan: plan, state: state, catalogs: WritingFixtures.catalogs, now: now)
        guard case .lesson(.skill(let skill)) = run.step else {
            Issue.record("no lesson: \(String(describing: run.step))")
            return
        }
        #expect(skill.id == first.id)

        // A skill with a lesson and nothing to ask isn't taught, planned or left in learning, even
        // once it was started.
        let empty = WritingSkill(id: "empty", title: "Empty", level: 0, lesson: "", example: "")
        let thin = Catalogs(writing: WritingBank(skills: [empty] + bank.skills, items: bank.items, library: library))
        let started = MemoryCard(key: empty.key, recent: [], introduced: now - 86_400, updatedAt: now - 86_400)
        #expect(
            WritingPlan.next([:], bank: thin.writing)?.id == first.id && WritingPlan.next([started.key: started], bank: thin.writing)?.id == first.id)
        let other = StudyRun(
            plan: plan, state: StudyState(settings: WritingFixtures.settings(), cards: [started], today: day, now: now), catalogs: thin,
            now: now)
        guard case .lesson(.skill(let opening)) = other.step else {
            Issue.record("the part ended: \(String(describing: other.step))")
            return
        }
        #expect(opening.id == first.id)
    }
}

extension WritingSessionTests {
    @Test("Done under a piece's notes, pressed twice as the step changes, doesn't skip the blind comparison after it")
    func reviewDoneOnce() throws {
        let old = WritingFixtures.piece(.benchmark, on: Fixtures.monday, taskID: "benchmark-creative")
        let state = WritingFixtures.state(WritingFixtures.settings(), pieces: [old], tests: placed, on: Fixtures.monday.adding(days: 84))
        var run = StudyRun(
            plan: SessionPlanner.plan(.checkIn, domains: [.writing], state: state, catalogs: catalogs), state: state, catalogs: catalogs,
            now: state.now)
        var now = state.now
        var steps = 0
        // To the benchmark's notes.
        while let step = run.step, steps < 100 {
            steps += 1
            now += 20
            if case .compose(let task) = step, task.reviewing != nil { break }
            switch step {
            case .question(let question):
                run.choose(question.correctChoice ?? 0, now: now)
                run.next(now: now)
            case .compose: run.submitWriting(WritingFixtures.words(150, from: "new"), source: .typed, misspelled: [], now: now)
            default: run.skipPart(now: now)
            }
        }
        guard case .compose(let review) = run.step, review.reviewing != nil else {
            Issue.record("no notes to read: \(String(describing: run.step))")
            return
        }
        let shown = run.stepNumber

        // Unguarded, the second press would leave the pair unjudged.
        var unguarded = run
        unguarded.respond(.skip, now: now + 1)
        unguarded.respond(.skip, now: now + 2)
        if case .compare = unguarded.step { Issue.record("the second Done was expected to skip the comparison") }

        run.respond(.skip, onStep: shown, now: now + 1)
        guard case .compare = run.step else {
            Issue.record("no comparison after the notes: \(String(describing: run.step))")
            return
        }
        let compare = run.stepNumber
        run.respond(.skip, onStep: shown, now: now + 2)
        #expect(run.stepNumber == compare, "the second press was for the notes, which have gone")
        guard case .compare = run.step else {
            Issue.record("the comparison was skipped")
            return
        }
    }

    @Test("Return on a lesson, arriving after the next question was answered, doesn't skip that answer's feedback")
    func lessonReturnOnce() throws {
        let state = StudyState(settings: WritingFixtures.settings(), today: day, now: day.date())
        let plan = SessionPlan(
            day: day, kind: .regular, minutes: 5, domains: [.writing],
            parts: [PlanPart(kind: .learn, domain: .writing, minutes: 5, title: "Grammar", detail: "")], headline: "", notes: [],
            planned: true)
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        guard case .lesson = run.step else {
            Issue.record("no lesson: \(String(describing: run.step))")
            return
        }
        let lesson = run.stepNumber
        run.next(fromStep: lesson, now: state.now + 20)
        guard case .question(let question) = run.step else {
            Issue.record("no question after the lesson: \(String(describing: run.step))")
            return
        }
        #expect(run.stepNumber == lesson + 1)
        run.choose(question.correctChoice ?? 0, now: state.now + 25)
        #expect(run.feedback != nil)

        run.next(fromStep: lesson, now: state.now + 26)
        #expect(run.stepNumber == lesson + 1 && run.feedback != nil, "the answer's feedback stays on screen")
        run.next(fromStep: run.stepNumber, now: state.now + 30)
        #expect(run.stepNumber == lesson + 2, "a press on the step shown moves on")
    }
}
