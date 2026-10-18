import Foundation
import SystemCore

/// Reading. A reading test places the reader (passages, not books read long ago) and comes back
/// at check-ins; the ladder prescribes the next book from just below the tested level; a session's
/// reading block is as long as focus has held, growing as it keeps holding.
enum ReadingModule: SubjectModule {
    static func needsPlacement(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> Bool {
        !state.tests.contains { $0.test == .readingTest && $0.domain == .reading }
    }

    static func placementParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        [
            PlanPart(
                kind: .placement, domain: .reading, minutes: 6, title: "Reading test",
                detail: "Short passages, each a little harder or easier, with a few questions")
        ]
    }

    static func mainParts(
        _ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, catalogs: Catalogs,
        notes: inout [String]
    ) -> [PlanPart] {
        let reviewWeek = kind == .review
        let book = state.currentBook
        let stamina = ReadingPlan.nextBlock(ReadingPlan.blocks(state.sessions, books: state.books))
        // Audiobooks are listening: they don't build reading stamina, so the block is the time there is.
        let block = book?.format == .audiobook ? minutes : max(1, min(minutes, stamina))
        let detail: String
        if let book {
            detail = "\(book.title) · page \(book.page) of \(book.pages)"
        } else if reviewWeek {
            detail = "Read anything you enjoy"
        } else {
            detail = "Pick your next book: tier \(ReadingPlan.targetTier(books: state.books, tests: state.tests, on: state.today))"
        }
        if block < minutes {
            notes.append("Reading is a \(block)-minute block: as long as focus has held so far. It grows as focus keeps holding.")
        }
        return [PlanPart(kind: .read, domain: .reading, minutes: block, title: reviewWeek ? "Reading for pleasure" : "Reading", detail: detail)]
    }

    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        guard state.settings.mode(.reading) == .focus else { return [] }
        return [
            PlanPart(
                kind: .test(.readingTest), domain: .reading, minutes: 5, title: "Reading",
                detail: "Three short passages around your level")
        ]
    }

    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> (any PartRunner)? {
        switch part.kind {
        case .placement:
            // Recent reading hints where to begin; the passages decide.
            let hint = ReadingPlan.level(books: state.books, tests: [], on: state.today) ?? 4.5
            return ReadingTestRunner(placement: true, start: clamp(Int(hint.rounded()) - 1, 2, 6))
        case .test(.readingTest):
            let level = ReadingPlan.level(books: state.books, tests: state.tests, on: state.today) ?? 4
            return ReadingTestRunner(placement: false, start: Int(level.rounded()))
        case .read:
            let book = state.currentBook
            return ReadingRunner(stage: book == nil ? .pick : .read, bookID: book?.id, block: part.minutes)
        default:
            return nil
        }
    }

    static func question(for key: CardKey, kind: AttemptKind, run: StudyRun) -> Question? { nil }
    static func usable(_ key: CardKey, catalogs: Catalogs) -> Bool { false }
    static func reviewSeconds(_ card: MemoryCard) -> Double { 0 }

    static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)] { ReadingPlan.series(state) }

    static func recent(_ domain: Domain, state: StudyState, count: Int) -> [(day: Day, score: Double)] { ReadingPlan.series(state, last: count) }

    static func label(_ domain: Domain, state: StudyState) -> String {
        ReadingPlan.level(books: state.books, tests: state.tests, on: state.today).map { "Reading tier \(ReadingPlan.format($0))" } ?? ""
    }
}

/// The reading block: choose a book if none is on the go, read with the timer for as long as
/// focus has held, note the page and how focus went, then a few sentences of reflection.
struct ReadingRunner: PartRunner {
    enum Stage: Sendable { case pick, read, reflect, done }
    var stage: Stage
    var bookID: UUID?
    /// Minutes the timer runs, from stamina.
    var block: Int

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        switch stage {
        case .pick:
            return .pickBook(
                ReadingPlan.suggestions(
                    shelf: run.books, tests: run.tests, genres: run.settings.genres, on: run.today,
                    ladder: run.catalogs.ladder))
        case .read:
            guard let book = run.books.first(where: { $0.id == bookID }) else { return nil }
            return .read(book, minutes: block)
        case .reflect:
            guard let book = run.books.first(where: { $0.id == bookID }) else { return nil }
            return .reflect(book, finished: book.status == .finished)
        case .done:
            return nil
        }
    }

    /// Each response only in its own stage, so a second tap (a pick while the timer runs, a page
    /// saved twice) can't add a book or rewrite the log.
    mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool {
        switch response {
        case .bookPicked(var book) where stage == .pick:
            book.status = .reading
            book.started = book.started ?? run.today
            book.updatedAt = run.now
            run.books.append(book)
            run.changedBooks.insert(book.id)
            bookID = book.id
            stage = .read
            return true
        case .readingDone(let page, let finished, let feel, let minutes, let focus) where stage == .read:
            guard let id = bookID, let index = run.books.firstIndex(where: { $0.id == id }) else { return false }
            var book = run.books[index]
            let from = book.page
            book.page = finished ? book.pages : clamp(page, 0, book.pages)
            if finished {
                book.status = .finished
                book.finished = run.today
                book.feel = feel
            }
            book.updatedAt = run.now
            run.books[index] = book
            run.changedBooks.insert(id)
            let counts = (book.format ?? .print).countsForStamina
            run.session.reading = ReadingLog(
                bookID: id, fromPage: from, toPage: book.page, minutes: minutes, planned: block,
                focus: counts ? focus : nil)
            stage = .reflect
            return true
        case .reflection(let text) where stage == .reflect:
            guard let id = bookID else { return false }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, let book = run.books.first(where: { $0.id == id }) {
                run.newReflections.append(
                    Reflection(
                        bookID: id, date: run.now, kind: book.status == .finished ? .book : .section,
                        page: book.page, text: trimmed, updatedAt: run.now))
            }
            stage = .done
            return true
        default:
            return false
        }
    }
}
