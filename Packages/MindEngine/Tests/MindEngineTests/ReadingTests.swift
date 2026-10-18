import Foundation
import Testing
import SystemCore
@testable import MindEngine

/// A simulated reader with a true level (the tier they understand comfortably), a true focus span
/// in minutes that grows a little with regular reading, and a reading pace.
struct Reader {
    var level: Double
    var focusSpan: Double
    var wordsPerMinute = 240.0
    var rng: SeededRandom

    init(level: Double, focusSpan: Double = 20, seed: UInt64 = 1) {
        self.level = level
        self.focusSpan = focusSpan
        rng = SeededRandom(seed: seed)
    }

    /// Understanding falls away smoothly above the true level, down to a guess among four.
    func chance(tier: Int) -> Double { 0.25 + 0.7 / (1 + exp(2.5 * (Double(tier) - level - 0.5))) }

    func feel(_ book: Book) -> BookFeel {
        let tier = Double(book.tier)
        if tier <= level - 1.25 { return .easy }
        if tier <= level + 0.5 { return .right }
        return .hard
    }

    /// Reads for the block: focus holds if the block is within the span, drifts a little past it,
    /// and is lost well past it. Someone with focus to spare reads a little beyond the timer.
    mutating func read(_ minutes: Int) -> (minutes: Double, focus: ReadingFocus) {
        let block = Double(minutes)
        if block <= focusSpan { return (min(focusSpan, block * (rng.chance(0.3) ? 1.2 : 1)), .held) }
        if block <= focusSpan * 1.25 { return (block, .drifted) }
        return (focusSpan, .lost)
    }

    @discardableResult
    mutating func run(_ run: inout StudyRun, from start: Date) -> Date {
        var now = start
        var steps = 0
        while let step = run.step, steps < 500 {
            steps += 1
            switch step {
            case .passage(let passage):
                let pace = wordsPerMinute * (Double(passage.tier) > level + 0.5 ? 0.6 : 1)
                let seconds = Double(passage.words) / pace * 60
                now += seconds
                run.respond(.passageRead(seconds: seconds), now: now)
            case .question(let question):
                now += 12
                let right = rng.chance(chance(tier: question.band ?? 5))
                run.choose(right ? question.correctChoice! : (question.correctChoice! + 1) % question.choices.count, now: now)
                now += 2
                run.next(now: now)
            case .pickBook(let options):
                now += 10
                if let first = options.first { run.pickBook(first, now: now) } else { run.skipPart(now: now) }
            case .read(let book, let minutes):
                let (read, focus) = self.read(minutes)
                now += read * 60
                let page = book.page + Int(read * 1.5)
                let finished = page >= book.pages
                run.finishReading(page: page, finished: finished, feel: finished ? feel(book) : nil, minutes: read, focus: focus, now: now)
            case .reflect:
                now += 30
                run.reflect("The middle dragged, but the ending earned it.", now: now)
            case .lesson:
                run.next(now: now)
            default:
                run.respond(.skip, now: now)
                run.skipPart(now: now)
            }
        }
        run.finish(now: now)
        return now
    }
}

@Suite("Reading")
struct ReadingTests {
    let catalogs = Catalogs()

    func placementTest(_ reader: inout Reader, books: [Book] = []) -> (TestResult?, StudyRun?) {
        var store = Store(settings: Fixtures.settings([.reading]))
        store.books = books
        let state = store.state(on: Fixtures.monday)
        guard let plan = SessionPlanner.today(state, catalogs: catalogs) else { return (nil, nil) }
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        reader.run(&run, from: state.now)
        return (run.newTests.first { $0.test == .readingTest }, run)
    }

    // MARK: The reading test

    @Test("the first session is a reading test that places readers of every level within about a tier")
    func placement() throws {
        var errors: [Double] = []
        var worst: [String] = []
        for level in 2...9 {
            for seed in 1...12 {
                var reader = Reader(level: Double(level), seed: UInt64(level * 100 + seed))
                let (result, run) = placementTest(&reader)
                let test = try #require(result, "level \(level) seed \(seed)")
                let placed = try #require(test.detail["tier"])
                errors.append(abs(placed - Double(level)))
                if abs(placed - Double(level)) > 1.5 {
                    worst.append("level \(level) placed \(placed): " + (run?.session.attempts.filter { $0.test == .readingTest }
                        .map { "\($0.band ?? 0)\($0.correct ? "+" : "-")" }.joined(separator: " ") ?? ""))
                }
                #expect(test.placement && test.domain == .reading)
                #expect(test.detail["wpm"] ?? 0 > 60)
                #expect((3...5).contains(Int(test.detail["passages"] ?? 0)), "\(test.detail)")
                #expect(run.map { $0.session.minutes < 14 } ?? false, "\(run?.session.minutes ?? 0) minutes")
            }
        }
        let mean = errors.reduce(0, +) / Double(errors.count)
        let within = Double(errors.filter { $0 <= 1 }.count) / Double(errors.count)
        #expect(mean <= 0.8, "mean error \(mean)")
        #expect(within >= 0.8, "\(within) within a tier")
        #expect(errors.allSatisfy { $0 <= 2.5 }, "\(worst)")
    }

    @Test("the staircase steps two until it turns, then one, and stops once it brackets a tier")
    func staircase() throws {
        var test = ReadingTest(start: 4, placement: true)
        func passage(_ tier: Int, _ right: Int) -> ReadingTest.Result {
            .init(passage: "p\(tier)", tier: tier, words: 150, seconds: 40, right: right, asked: 3)
        }
        test.record(passage(4, 3))
        #expect(test.nextTier == 6)
        test.record(passage(6, 2))
        #expect(test.nextTier == 8)
        test.record(passage(8, 1))
        #expect(test.nextTier == 7, "one step after the turn")
        test.record(passage(7, 3))
        #expect(test.done, "passed 7, failed 8")
        let seven = try #require(ReadingTest.estimate(test.results))
        #expect(seven >= 6.5 && seven <= 7.5, "\(seven)")

        // Understood but laboured over (40 words a minute) doesn't pass, and counts for less.
        let slow = ReadingTest.Result(passage: "s", tier: 5, words: 150, seconds: 225, right: 3, asked: 3)
        #expect(!slow.passed)
        #expect(try #require(ReadingTest.estimate([slow])) < (try #require(ReadingTest.estimate([passage(5, 3)]))))
        // Three of three says more than two of three.
        #expect(try #require(ReadingTest.estimate([passage(6, 3), passage(7, 1)])) > (try #require(ReadingTest.estimate([passage(6, 2), passage(7, 1)]))))
        #expect(try #require(ReadingTest.estimate([passage(3, 0), passage(2, 1)])) <= 1.5)
        let between = try #require(ReadingTest.estimate([passage(4, 3), passage(6, 0)]))
        #expect(between > 4 && between < 5.5, "\(between)")

        // A single pass at the top isn't the end: it's confirmed with a second.
        var top = ReadingTest(start: 8, placement: true)
        top.record(passage(8, 3))
        top.record(passage(10, 2))
        #expect(top.nextTier == 10)
        top.record(passage(10, 3))
        #expect(top.done)
    }

    @Test("a check-in re-tests from the level with three passages it hasn't shown before")
    func checkInTest() throws {
        var reader = Reader(level: 6, seed: 9)
        var store = Store(settings: Fixtures.settings([.reading]))
        let first = try #require(placementTest(&reader).0)
        store.tests = [first]
        store.sessions = [StudySession(purpose: .placement, start: Fixtures.monday.date(), end: Fixtures.monday.date(), plannedMinutes: 25,
                                       domains: [.reading], planned: true)]
        let day = Fixtures.monday.adding(days: 55)
        let state = store.state(on: day)
        let plan = SessionPlanner.plan(.checkIn, domains: [.reading], state: state, catalogs: catalogs)
        #expect(plan.parts.map(\.kind) == [.test(.readingTest)])
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        var shown: [String] = []
        while let step = run.step, case .passage(let passage) = step {
            shown.append(passage.id)
            run.respond(.passageRead(seconds: 45), now: state.now)
            while case .question(let question) = run.step {
                run.choose(question.correctChoice!, now: state.now)
                run.next(now: state.now)
            }
        }
        run.finish(now: state.now)
        let retest = try #require(run.newTests.first)
        #expect(!retest.placement && shown.count == 3)
        #expect(shown.allSatisfy { first.detail["passage.\($0)"] == nil }, "fresh passages")
    }

    // MARK: Level and the next book

    @Test("the next book starts just below the tested level and climbs as books feel easy or just right")
    func prescription() throws {
        let day = Fixtures.monday
        let test = TestResult(test: .readingTest, date: day.date(), score: 0.8, detail: ["tier": 6])
        func book(_ tier: Int, _ status: BookStatus, _ feel: BookFeel?, after days: Int) -> Book {
            Book(title: "Book \(tier).\(days)", author: "Author", tier: tier, pages: 300, genres: [.literary], status: status,
                 finished: day.adding(days: days), feel: feel, tierConfidence: 1)
        }
        var shelf: [Book] = []
        func target() -> Double { ReadingPlan.target(books: shelf, tests: [test], on: day.adding(days: 100)) }
        func tier() -> Int { ReadingPlan.targetTier(books: shelf, tests: [test], on: day.adding(days: 100)) }
        #expect(target() == 5, "just below the tested 6")
        shelf.append(book(5, .finished, .right, after: 10))
        #expect(target() == 5.5)
        shelf.append(book(6, .finished, .easy, after: 30))
        #expect(tier() == 7, "an easy 6: up a tier")
        #expect(target() <= (ReadingPlan.level(books: shelf, tests: [test], on: day.adding(days: 100)) ?? 0) + 1, "never past a tier above the level")
        shelf.append(book(7, .finished, .hard, after: 50))
        #expect(tier() == 7, "a slog holds it")
        shelf.append(book(7, .abandoned, .hard, after: 60))
        #expect(target() == 6, "given up on as too hard: back a tier")
        shelf.append(book(4, .abandoned, .easy, after: 70))
        #expect(target() == 6, "given up on as too easy is taste, not difficulty")

        // Without a test, recent reading places the start; without either, the ladder's start.
        #expect(ReadingPlan.target(books: [], tests: [], on: day) == Double(ReadingPlan.startingTier))
        let recent = [Book(ladderID: "x", title: "Recent", author: "A", tier: 5, pages: 300, genres: [], status: .readBefore, finished: day,
                           feel: .right)]
        #expect(ReadingPlan.target(books: recent, tests: [], on: day) == 4)

        // Suggestions sit at the next tier, in liked genres, by different authors, none owned.
        let picks = ReadingPlan.suggestions(shelf: shelf, tests: [test], genres: [.fantasy, .sciFi], on: day.adding(days: 100))
        #expect(picks.count == 3)
        #expect(picks.allSatisfy { abs($0.tier - 6) <= 1 }, "\(picks.map(\.tier))")
        #expect(Set(picks.map(\.author)).count == 3)
        #expect(picks.allSatisfy { !Set($0.genres).isDisjoint(with: [.fantasy, .sciFi]) })
    }

    @Test("the level fits tests and finished books; easy books lift it, and nothing else moves it")
    func level() throws {
        let day = Fixtures.monday
        let test = TestResult(test: .readingTest, date: day.date(), score: 0.8, detail: ["tier": 5])
        #expect(ReadingPlan.level(books: [], tests: [test], on: day) == 5)
        #expect(ReadingPlan.level(books: [], tests: [], on: day) == nil)
        var easy = Book(ladderID: "x", title: "Easy", author: "A", tier: 7, pages: 300, genres: [], status: .finished,
                        finished: day.adding(days: 20), feel: .easy, tierConfidence: 1)
        let lifted = try #require(ReadingPlan.level(books: [easy], tests: [test], on: day.adding(days: 30)))
        #expect(lifted > 5.5 && lifted < 6.5, "\(lifted)")
        // An easy book far below the level says nothing new.
        easy.tier = 2
        #expect(ReadingPlan.level(books: [easy], tests: [test], on: day.adding(days: 30)) == 5)
        // An audiobook counts for half; one's own book with a guessed tier counts for less still.
        var audio = Book(title: "Heard", author: "A", tier: 8, pages: 300, genres: [], status: .finished, finished: day.adding(days: 20),
                         feel: .right, format: .audiobook, tierConfidence: 1)
        let heard = try #require(ReadingPlan.level(books: [audio], tests: [test], on: day.adding(days: 30)))
        audio.format = .print
        let read = try #require(ReadingPlan.level(books: [audio], tests: [test], on: day.adding(days: 30)))
        #expect(heard < read && heard > 5)
        let guessed = Book(title: "Own", author: "A", tier: 8, pages: 300, genres: [], status: .finished, finished: day.adding(days: 20),
                           feel: .right)
        #expect(try #require(ReadingPlan.level(books: [guessed], tests: [test], on: day.adding(days: 30))) < heard)
    }

    @Test("Wisdom moves on the reading test and finished books, never on time read")
    func wisdomIsHonest() throws {
        var store = Store(settings: Fixtures.settings([.reading]))
        let day = Fixtures.monday.adding(days: 30)
        store.tests = [TestResult(test: .readingTest, date: Fixtures.monday.date(), score: 0.8, detail: ["tier": 5], placement: true)]
        let book = Book(title: "On the go", author: "A", tier: 5, pages: 400, genres: [.literary], status: .reading, format: .print)
        store.books = [book]
        let before = try #require(ReadingPlan.wisdom(store.state(on: day)).score)
        for offset in 1...20 {
            let start = Fixtures.monday.adding(days: offset).date().addingTimeInterval(19 * 3600)
            store.sessions.append(StudySession(purpose: .regular, start: start, end: start.addingTimeInterval(3600), plannedMinutes: 25,
                                               domains: [.reading], planned: true,
                                               reading: ReadingLog(bookID: book.id, fromPage: offset * 15, toPage: offset * 15 + 15, minutes: 60,
                                                                   planned: 25, focus: .held),
                                               activeSeconds: 3600, ranToEnd: true))
        }
        #expect(ReadingPlan.wisdom(store.state(on: day)).score == before, "twenty hours of reading moved nothing")
        var finished = book
        finished.status = .finished
        finished.finished = day
        finished.feel = .easy
        store.books = [finished]
        #expect(try #require(ReadingPlan.wisdom(store.state(on: day)).score) > before)
    }

    // MARK: Stamina

    @Test("stamina climbs while focus holds, holds when it drifts, drops when it's lost, and audiobooks don't count")
    func stamina() {
        let day = Fixtures.monday
        func block(_ minutes: Double, _ planned: Int, _ focus: ReadingFocus?) -> ReadingPlan.Block {
            .init(day: day, minutes: minutes, planned: planned, focus: focus)
        }
        #expect(ReadingPlan.nextBlock([]) == ReadingPlan.firstBlock)
        #expect(ReadingPlan.nextBlock([block(15, 15, .held)]) == 17)
        #expect(ReadingPlan.nextBlock([block(15, 15, .held), block(17, 17, .held)]) == 19)
        #expect(ReadingPlan.nextBlock([block(26, 15, .held)]) == 26, "reading well past the timer counts")
        #expect(ReadingPlan.nextBlock([block(15, 15, .held), block(17, 17, .drifted)]) == 17)
        #expect(ReadingPlan.nextBlock([block(15, 15, .held), block(12, 17, .lost)]) == 9)
        // A block cut short by the session's length says nothing against a longer one.
        #expect(ReadingPlan.nextBlock([block(30, 30, .held), block(16, 16, .held)]) == 33)
        // Focus held but stopped early (the phone rang): no climb, no drop.
        #expect(ReadingPlan.nextBlock([block(20, 20, .held), block(8, 22, .held)]) == 22)
        #expect(ReadingPlan.stamina([block(20, 20, .held), block(20, 22, .drifted)]) == 19)
        #expect(ReadingPlan.stamina([block(20, 20, .lost)]) == 10)

        let print = Book(title: "Print", author: "A", tier: 4, pages: 300, genres: [], status: .reading, format: .print)
        let audio = Book(title: "Audio", author: "A", tier: 4, pages: 300, genres: [], status: .reading, format: .audiobook)
        let sessions = [print, audio, print].enumerated().map { index, book in
            StudySession(purpose: .regular, start: day.adding(days: index).date(), plannedMinutes: 25, domains: [.reading], planned: true,
                         reading: ReadingLog(bookID: book.id, fromPage: 0, toPage: 20, minutes: 40, planned: 20, focus: .held))
        }
        #expect(ReadingPlan.blocks(sessions, books: [print, audio]).count == 2, "the audiobook block is left out")
    }

    @Test("a reading day's block is as long as stamina allows, and the timer runs for it")
    func blockRespectsStamina() throws {
        var store = Store(settings: Fixtures.settings([.reading], days: 7))
        store.tests = [TestResult(test: .readingTest, date: Fixtures.monday.date(), score: 0.8, detail: ["tier": 5], placement: true)]
        store.sessions = [StudySession(purpose: .placement, start: Fixtures.monday.date(), end: Fixtures.monday.date(), plannedMinutes: 25,
                                       domains: [.reading], planned: true)]
        let book = Book(title: "On the go", author: "A", tier: 4, pages: 400, genres: [.literary], status: .reading, format: .print)
        store.books = [book]
        let state = store.state(on: Fixtures.monday.adding(days: 1))
        let plan = try #require(SessionPlanner.today(state, catalogs: catalogs))
        let part = try #require(plan.parts.first { $0.kind == .read })
        #expect(part.minutes == ReadingPlan.firstBlock, "\(plan.parts)")
        #expect(plan.notes.contains { $0.contains("\(ReadingPlan.firstBlock)-minute block") })
        let run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        guard case .read(_, let minutes) = run.step else { Issue.record("no reading step: \(String(describing: run.step))"); return }
        #expect(minutes == ReadingPlan.firstBlock)

        // An audiobook gets the whole share: listening doesn't build reading stamina.
        var audio = book
        audio.format = .audiobook
        store.books = [audio]
        let listening = try #require(SessionPlanner.today(store.state(on: Fixtures.monday.adding(days: 1)), catalogs: catalogs))
        #expect(try #require(listening.parts.first { $0.kind == .read }).minutes > ReadingPlan.firstBlock)
    }

    @Test("sixteen weeks of reading: placed by the test, stamina grows with the reader, the ladder climbs and a check-in re-tests")
    func sixteenWeeks() throws {
        var store = Store(settings: Fixtures.settings([.reading], days: 4))
        let recent = ReadingLadder.standard.books.filter { $0.tier == 4 && !$0.levelledFromText }.prefix(2).map { ladder -> Book in
            var book = ladder.book(status: .readBefore)
            book.feel = .right
            book.format = .audiobook
            return book
        }
        store.books = recent
        var reader = Reader(level: 6.5, focusSpan: 22, seed: 2026)
        var wisdom: [Day: Double?] = [:]
        var blocks: [Int] = []
        var checkIns = 0
        for offset in 0..<(16 * 7) {
            let day = Fixtures.monday.adding(days: offset)
            // Regular reading trains focus: about a minute more a fortnight, up to forty.
            if offset % 14 == 13 { reader.focusSpan = min(40, reader.focusSpan + 1) }
            let state = store.state(on: day)
            guard let plan = SessionPlanner.today(state, catalogs: catalogs) else { continue }
            var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
            reader.run(&run, from: state.now)
            store.save(run)
            if plan.kind == .checkIn { checkIns += 1 }
            if let log = run.session.reading { blocks.append(log.planned ?? 0) }
            wisdom[day] = ReadingPlan.wisdom(store.state(on: day)).score
        }
        let tests = store.tests.filter { $0.test == .readingTest }
        let placed = try #require(tests.first)
        #expect(placed.placement && abs((placed.detail["tier"] ?? 0) - 6.5) <= 1.5, "\(placed.detail)")
        #expect(checkIns >= 1 && tests.count >= 2, "\(checkIns) check-ins, \(tests.count) tests")

        // Stamina rose from the first block towards the reader's real span, and never far past it.
        #expect(blocks.first == ReadingPlan.firstBlock)
        let last = try #require(blocks.last)
        #expect(last >= 22 && Double(last) <= reader.focusSpan * 1.3, "blocks \(blocks)")

        // Books were read and finished at the prescribed tiers, climbing from just below the test.
        let finished = store.books.filter { $0.status == .finished }
        #expect(finished.count >= 2, "\(store.books.map { "\($0.title) \($0.status) \($0.page)/\($0.pages)" })")
        #expect(finished.allSatisfy { $0.tier >= Int((placed.detail["tier"] ?? 0).rounded()) - 2 })

        // Wisdom changed only on days with a test or a finished book.
        let movingDays = Set(tests.map(\.day) + finished.compactMap(\.finished))
        let days = wisdom.keys.sorted()
        for (previous, day) in zip(days, days.dropFirst()) where wisdom[day]! != wisdom[previous]! {
            #expect(movingDays.contains(day), "Wisdom moved on \(day.iso) with nothing to show for it")
        }
    }

    // MARK: Books from outside

    @Test("ISBNs: an EAN-13 starting 978 or 979 with a good check digit, or an ISBN-10 converted")
    func isbn() {
        #expect(ISBN.normalize("978-0-14-143951-8") == "9780141439518")
        #expect(ISBN.normalize("9780141439519") == nil, "bad check digit")
        #expect(ISBN.normalize("5012345678900") == nil, "a grocery barcode, not a book")
        #expect(ISBN.normalize("0141439513") == "9780141439518")
        #expect(ISBN.normalize("0-8044-2957-X") == "9780804429573")
        #expect(ISBN.normalize("9791032305690") == "9791032305690")
        #expect(ISBN.normalize("") == nil)
    }

    @Test("Open Library and Google Books replies become cached book records")
    func sources() throws {
        let edition = """
        {"ISBN:9780141439518": {"title": "Pride and Prejudice", "authors": [{"name": "Jane Austen"}], "number_of_pages": 435,
         "publish_date": "2003", "subjects": [{"name": "Fiction, Romance, Historical, Regency"}, {"name": "Courtship"}],
         "cover": {"small": "https://covers.openlibrary.org/b/id/1-S.jpg", "medium": "https://covers.openlibrary.org/b/id/1-M.jpg"}}}
        """
        let meta = try #require(OpenLibrary.parseISBN(Data(edition.utf8), isbn: "9780141439518"))
        #expect(meta.title == "Pride and Prejudice" && meta.author == "Jane Austen" && meta.pages == 435 && meta.year == 2003)
        #expect(meta.coverURL?.absoluteString.hasSuffix("1-M.jpg") == true && meta.source == "openlibrary")

        let search = """
        {"numFound": 1, "docs": [{"author_name": ["Susanna Clarke"], "cover_i": 10226290, "first_publish_year": 2020,
         "isbn": ["1635575648", "9781526622440"], "number_of_pages_median": 272, "title": "Piranesi",
         "subject": ["form:novel", "genre:fantasy", "Labyrinths"]}]}
        """
        let found = OpenLibrary.parseSearch(Data(search.utf8))
        #expect(found.count == 1 && found[0].isbn == "9781635575644" && found[0].pages == 272)
        #expect(found[0].coverURL?.absoluteString == "https://covers.openlibrary.org/b/id/10226290-M.jpg")
        #expect(OpenLibrary.parseSearch(Data("{}".utf8)).isEmpty)

        let google = """
        {"items": [{"volumeInfo": {"title": "The Name of the Wind", "authors": ["Patrick Rothfuss"], "publishedDate": "2007-03-27",
         "pageCount": 662, "categories": ["Fiction"], "imageLinks": {"thumbnail": "http://books.google.com/x.jpg"},
         "industryIdentifiers": [{"type": "ISBN_10", "identifier": "0756404746"}, {"type": "ISBN_13", "identifier": "9780756404741"}]}}]}
        """
        let volume = try #require(GoogleBooks.parse(Data(google.utf8)).first)
        #expect(volume.isbn == "9780756404741" && volume.year == 2007 && volume.pages == 662 && volume.source == "googlebooks")
        #expect(volume.coverURL?.scheme == "https")
        // A quota error is an empty answer, not a crash.
        #expect(GoogleBooks.parse(Data(#"{"error": {"code": 429}}"#.utf8)).isEmpty)
        #expect(OpenLibrary.year("March 1813") == 1813 && OpenLibrary.year("n.d.") == nil)
    }

    @Test("a cover's text: the model's two lines, or else the tallest words and a name-shaped line")
    func coverText() {
        let reply = "Title: The Name of the Wind\nAuthor: Patrick Rothfuss"
        #expect(CoverText.parseReply(reply) == .init(title: "The Name of the Wind", author: "Patrick Rothfuss"))
        #expect(CoverText.parseReply("Title: Beowulf\nAuthor: unknown")?.author == nil)
        #expect(CoverText.parseReply("I can't tell") == nil)
        let lines: [CoverText.Line] = [
            .init(text: "#1 NEW YORK TIMES BESTSELLER", height: 0.02),
            .init(text: "THE NAME", height: 0.09), .init(text: "OF THE WIND", height: 0.085),
            .init(text: "PATRICK ROTHFUSS", height: 0.05),
            .init(text: "Day One of the Kingkiller Chronicle", height: 0.02),
        ]
        let guess = CoverText.guess(lines)
        #expect(guess?.title == "The Name of the Wind")
        #expect(guess?.author == "Patrick Rothfuss")
        #expect(guess?.query == "The Name of the Wind Patrick Rothfuss")
        #expect(CoverText.guess([]) == nil)
    }

    @Test("a book's level: the ladder, then the author's other books, then genre, length and age; feedback refines it")
    func bookLevels() throws {
        let ladder = ReadingLadder.standard
        let gatsby = BookLevel.estimate(title: "The Great Gatsby: A Novel", author: "Fitzgerald, F. Scott", ladder: ladder)
        #expect(gatsby.tier == 4 && gatsby.confidence == 1)
        if case .ladder = gatsby.basis {} else { Issue.record("not matched to the ladder: \(gatsby.basis)") }

        let tolkien = BookLevel.estimate(title: "The Children of Húrin", author: "J.R.R. Tolkien", ladder: ladder)
        #expect(tolkien.confidence == BookLevel.authorConfidence && tolkien.tier >= 2 && tolkien.tier <= 6, "\(tolkien)")

        let thriller = BookLevel.estimate(title: "Some Thriller", author: "Nobody Known", pages: 380, year: 2019,
                                          subjects: ["Fiction", "Thrillers", "Suspense"], ladder: ladder)
        #expect(thriller.genres == [.crime] && thriller.tier <= 3 && thriller.confidence == BookLevel.guessConfidence)
        let treatise = BookLevel.estimate(title: "An Old Treatise", author: "Nobody Known", pages: 950, year: 1690,
                                          subjects: ["Philosophy", "Metaphysics"], ladder: ladder)
        #expect(treatise.tier >= 9, "\(treatise.tier)")
        #expect(BookLevel.estimate(title: "Picture Book", author: "Nobody Known", subjects: ["Juvenile fiction"]).tier <= 1.5)

        // Feedback pulls an estimate towards what the reader found: a guess more than a ladder book.
        var own = Book(title: "Own", author: "A", tier: 4, pages: 300, genres: [], status: .finished, feel: .hard)
        let refined = BookLevel.refined(own, readerLevel: 4)
        #expect(refined > 4.5)
        own.tierConfidence = 1
        #expect(BookLevel.refined(own, readerLevel: 4) < refined)
        own.status = .reading
        #expect(BookLevel.refined(own, readerLevel: 4) == 4, "no feedback until it's finished or set aside")

        // The same book however it's written.
        #expect(BookLevel.matchKey(title: "The Hobbit: or There and Back Again", author: "J. R. R. Tolkien")
            == BookLevel.matchKey(title: "Hobbit", author: "Tolkien, J. R. R."))
        #expect(BookLevel.matchKey(title: "A Canticle for Leibowitz", author: "Walter M. Miller Jr.")
            == BookLevel.matchKey(title: "A Canticle for Leibowitz", author: "Walter M. Miller"))
    }

    // MARK: Content

    @Test("the ladder: a few hundred books levelled by hand across every tier and genre, unique and well formed")
    func ladder() {
        let ladder = ReadingLadder.standard
        let hand = ladder.handLevelled
        #expect(hand.count >= 300, "\(hand.count) hand-levelled")
        #expect(Set(ladder.books.map(\.id)).count == ladder.books.count, "ids are unique")
        #expect(Set(ladder.books.map { BookLevel.matchKey(title: $0.title, author: $0.author) }).count == ladder.books.count, "no book twice")
        for tier in 1...10 {
            let books = hand.filter { $0.tier == tier }
            #expect(books.count >= 15, "tier \(tier): \(books.count)")
            #expect(Set(books.flatMap(\.genres)).count >= 4, "tier \(tier) genres")
        }
        for genre in Genre.allCases {
            let tiers = Set(hand.filter { $0.genres.contains(genre) }.map(\.tier))
            #expect(tiers.count >= 7, "\(genre) spans \(tiers.sorted())")
        }
        for book in ladder.books {
            #expect((40...2500).contains(book.pages) && !book.genres.isEmpty && book.note.count >= 50, "\(book.id): \(book.pages)")
            #expect(book.year <= 2026 && book.language == nil, "\(book.id)")
        }
    }

    @Test("classics levelled from their Gutenberg text agree with the hand-levelled tiers")
    func classicsFromText() throws {
        let classics = ReadingLadder.standard.classics
        #expect(classics.count >= 80, "\(classics.count) levelled from text")
        let anchors = classics.filter { $0.handTier != nil }
        #expect(anchors.count >= 25)
        for classic in classics {
            #expect((1...10).contains(classic.tier) && classic.words > 5000 && classic.sentenceWords > 5, "\(classic.id)")
        }
        // Each anchor's tier was predicted with it left out of the fit. Text alone is a blunt
        // measure (it can't see what makes Faulkner hard), so these bounds are honest, not tight,
        // and text-levelled tiers count for half of a hand-levelled one.
        let errors = anchors.map { abs($0.tier - Double($0.handTier!)) }
        let mean = errors.reduce(0, +) / Double(errors.count)
        #expect(mean <= 2, "mean error \(mean)")
        #expect(Double(errors.filter { $0 <= 2 }.count) / Double(errors.count) >= 0.6)
        // Order holds broadly: the hand tiers' ranks and the text's ranks go the same way.
        #expect(spearman(anchors.map { Double($0.handTier!) }, anchors.map(\.tier)) >= 0.4)
        // And the obvious pairs come out the right way round.
        func tier(_ id: String) throws -> Double { try #require(classics.first { $0.id == id }).tier }
        #expect(try tier("the-wonderful-wizard-of-oz") < tier("the-descent-of-man"))
        #expect(try tier("the-hound-of-the-baskervilles") < tier("tristram-shandy"))
        #expect(try tier("the-secret-adversary") < tier("the-wealth-of-nations"))
        #expect(BookLevel.textConfidence < BookLevel.authorConfidence)
        // Classics not levelled by hand join the ladder, marked as levelled from their text.
        let joined = ReadingLadder.standard.books.filter(\.levelledFromText)
        #expect(joined.count == classics.count - anchors.count)
        #expect(joined.allSatisfy { $0.note.hasPrefix("Levelled from its text") })
    }

    func spearman(_ a: [Double], _ b: [Double]) -> Double {
        func ranks(_ values: [Double]) -> [Double] {
            let order = values.indices.sorted { values[$0] < values[$1] }
            var out = [Double](repeating: 0, count: values.count)
            var i = 0
            while i < order.count {
                var j = i
                while j + 1 < order.count && values[order[j + 1]] == values[order[i]] { j += 1 }
                for k in i...j { out[order[k]] = Double(i + j) / 2 }
                i = j + 1
            }
            return out
        }
        let (ra, rb) = (ranks(a), ranks(b))
        let (ma, mb) = (ra.reduce(0, +) / Double(ra.count), rb.reduce(0, +) / Double(rb.count))
        let cov = zip(ra, rb).map { ($0 - ma) * ($1 - mb) }.reduce(0, +)
        let va = ra.map { ($0 - ma) * ($0 - ma) }.reduce(0, +), vb = rb.map { ($0 - mb) * ($0 - mb) }.reduce(0, +)
        return cov / sqrt(va * vb)
    }

    @Test("passages: three or more at every tier, each with two or three questions and four distinct choices")
    func passages() {
        let bank = PassageBank.standard
        for tier in 1...10 { #expect(bank.passages(tier: tier).count >= 3, "tier \(tier)") }
        #expect(Set(bank.passages.map(\.id)).count == bank.passages.count)
        for passage in bank.passages {
            #expect((90...260).contains(passage.words), "\(passage.id): \(passage.words) words")
            #expect((2...3).contains(passage.questions.count), "\(passage.id)")
            #expect(!passage.source.isEmpty && !passage.author.isEmpty, "\(passage.id)")
            for question in ReadingTestRunner.questions(passage, seed: "x") {
                #expect(question.choices.count == 4 && Set(question.choices).count == 4, "\(passage.id): \(question.choices)")
                #expect(question.test == .readingTest && question.kind == .test && question.band == passage.tier)
            }
            for item in passage.questions {
                #expect(!item.wrong.contains(item.answer), "\(passage.id)")
            }
        }
    }
}

extension ReadingTests {
    /// A reader placed on Monday with no book on the go, on Tuesday's reading day.
    func readingDay() -> (store: Store, state: StudyState) {
        var store = Store(settings: Fixtures.settings([.reading], days: 7))
        store.tests = [TestResult(test: .readingTest, date: Fixtures.monday.date(), score: 0.8, detail: ["tier": 5], placement: true)]
        store.sessions = [StudySession(purpose: .placement, start: Fixtures.monday.date(), end: Fixtures.monday.date(), plannedMinutes: 25,
                                       domains: [.reading], planned: true)]
        return (store, store.state(on: Fixtures.monday.adding(days: 1)))
    }

    @Test("'Not today' with no book on the go isn't the day's session done")
    func notToday() throws {
        var (store, state) = readingDay()
        let plan = try #require(SessionPlanner.today(state, catalogs: catalogs))
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        guard case .pickBook = run.step else { Issue.record("no book to pick: \(String(describing: run.step))"); return }
        run.skipPart(now: state.now + 5)
        #expect(run.isComplete)
        run.finish(now: state.now + 8)
        #expect(!run.session.ranToEnd && !run.session.counts)
        store.save(run)
        let after = store.state(on: state.today.adding(days: 1))
        let discipline = Analyst.discipline(after)
        #expect(discipline.planned == 2 && discipline.completed == 1, "\(discipline)")
        #expect(Analyst.week(after).first { $0.day == state.today }?.status == .missed)
    }

    @Test("a second pick, page or reflection is ignored once the reading has moved on")
    func repeatedTaps() throws {
        let (_, state) = readingDay()
        let plan = try #require(SessionPlanner.today(state, catalogs: catalogs))
        var run = StudyRun(plan: plan, state: state, catalogs: catalogs, now: state.now)
        guard case .pickBook(let books) = run.step, let ladderBook = books.first else { Issue.record("no book to pick"); return }
        run.pickBook(ladderBook, now: state.now + 5)
        guard case .read(let book, let minutes) = run.step else { Issue.record("not reading"); return }
        run.pickBook(books.last ?? ladderBook, now: state.now + 6)
        #expect(run.books.filter { $0.status == .reading }.count == 1 && run.changedBooks == [book.id], "one book on the go")
        guard case .read(let still, _) = run.step else { Issue.record("not reading"); return }
        #expect(still.id == book.id)

        let end = state.now + Double(minutes) * 60
        run.finishReading(page: 30, finished: false, feel: nil, minutes: Double(minutes), focus: .held, now: end)
        guard case .reflect = run.step else { Issue.record("no reflection"); return }
        run.finishReading(page: 30, finished: false, feel: nil, minutes: Double(minutes), focus: .held, now: end + 1)
        #expect(run.session.reading?.fromPage == 0 && run.session.reading?.toPage == 30, "\(String(describing: run.session.reading))")

        run.reflect("A quiet chapter.", now: end + 30)
        run.reflect("Saved twice.", now: end + 31)
        #expect(run.newReflections.map(\.text) == ["A quiet chapter."])
    }
}

extension ReadingTests {
    @Test("an odd record in a lookup reply drops only itself, and ISBNs typed in full-width digits read as plain ones")
    func untrustedReplies() throws {
        let google = """
        {"items": [{"kind": "books#volume"},
                   {"volumeInfo": {"title": "Odd", "industryIdentifiers": [{"type": "OTHER"}, {"type": "ISBN_13", "identifier": "9780141439518"}]}},
                   {"volumeInfo": {"title": "The Name of the Wind", "authors": ["Patrick Rothfuss"], "pageCount": 662}}]}
        """
        let books = GoogleBooks.parse(Data(google.utf8))
        #expect(books.map(\.title) == ["Odd", "The Name of the Wind"], "an identifier without a value loses only itself")
        #expect(books.first?.isbn == "9780141439518")
        let search = """
        {"docs": [{"title": "Piranesi", "number_of_pages_median": "many"}, {"title": "Jonathan Strange", "author_name": ["Susanna Clarke"]}]}
        """
        #expect(OpenLibrary.parseSearch(Data(search.utf8)).map(\.title) == ["Jonathan Strange"])
        #expect(OpenLibrary.parseISBN(Data(#"{"ISBN:9780141439518": {"authors": []}}"#.utf8), isbn: "9780141439518") == nil)

        #expect(ISBN.normalize("９７８０１４１４３９５１８") == "9780141439518")
        #expect(ISBN.normalize("978-0-14-143951-8") == "9780141439518")
        #expect(ISBN.normalize("978014143951½8") == "9780141439518", "½ isn't a digit, so it's dropped like a hyphen")
        #expect(ISBN.normalize("①9780141439518") == "9780141439518")
        #expect(ISBN.normalize("97801414395１9") == nil, "a wrong check digit, whatever the keyboard")
    }

    @Test("a trend reads only the last two points, and they're the full series' last two")
    func recentReadings() {
        var store = Store(settings: Fixtures.settings([.reading]))
        store.tests = (0..<4).map { i in
            TestResult(test: .readingTest, date: Fixtures.monday.adding(days: i * 42).date(), score: 0.8, detail: ["tier": Double(3 + i)])
        }
        store.books = (0..<6).map { i in
            Book(ladderID: "book-\(i)", title: "Book \(i)", author: "A", tier: 4 + i % 3, pages: 300, genres: [], status: .finished,
                 finished: Fixtures.monday.adding(days: 10 + i * 20), feel: [.easy, .right, .hard][i % 3])
        }
        let state = store.state(on: Fixtures.monday.adding(days: 200))
        let full = ReadingPlan.series(state)
        let recent = ReadingModule.recent(.reading, state: state, count: 2)
        #expect(full.count == 10)
        #expect(recent.map(\.day) == full.suffix(2).map(\.day) && recent.map(\.score) == full.suffix(2).map(\.score))
        #expect(ReadingPlan.series(state, last: 50).map(\.score) == full.map(\.score))
    }
}
