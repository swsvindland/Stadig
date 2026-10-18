import Foundation
import SystemCore

/// Reading. The ladder of books, a timed reading block and a reflection. The v2 rework places the
/// reader with a passage test instead of books read long ago, measures stamina apart from
/// difficulty, and adds books by ISBN, cover or search.
enum ReadingModule: SubjectModule {
    static func needsPlacement(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> Bool { false }

    static func placementParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] { [] }

    static func mainParts(_ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, catalogs: Catalogs,
                          notes: inout [String]) -> [PlanPart] {
        let reviewWeek = kind == .review
        let detail: String
        if let book = state.currentBook {
            detail = "\(book.title) · page \(book.page) of \(book.pages)"
        } else {
            detail = reviewWeek ? "Read anything you enjoy" : "Pick your next book from the ladder"
        }
        return [PlanPart(kind: .read, domain: .reading, minutes: minutes, title: reviewWeek ? "Reading for pleasure" : "Reading", detail: detail)]
    }

    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] { [] }

    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> (any PartRunner)? {
        guard part.kind == .read else { return nil }
        let book = state.currentBook
        return ReadingRunner(stage: book == nil ? .pick : .read, bookID: book?.id)
    }

    static func question(for key: CardKey, kind: AttemptKind, run: StudyRun) -> Question? { nil }
    static func usable(_ key: CardKey, catalogs: Catalogs) -> Bool { false }
    static func reviewSeconds(_ card: MemoryCard) -> Double { 0 }

    static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)] {
        state.books.filter(\.done).compactMap { book in
            let day = book.finished ?? state.start
            let shelf = state.books.filter { $0.done && ($0.finished ?? state.start) <= day }
            return ReadingPlan.score(shelf).map { (day, $0) }
        }.sorted { $0.0 < $1.0 }
    }

    static func label(_ domain: Domain, state: StudyState) -> String { "" }
}

/// The reading block: choose a book if none is on the go, read with the timer, note the page,
/// then a few sentences of reflection.
struct ReadingRunner: PartRunner {
    enum Stage: Sendable { case pick, read, reflect, done }
    var stage: Stage
    var bookID: UUID?

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        switch stage {
        case .pick:
            return .pickBook(ReadingPlan.suggestions(shelf: run.books, genres: run.settings.genres, ladder: run.catalogs.ladder))
        case .read:
            guard let book = run.books.first(where: { $0.id == bookID }) else { return nil }
            return .read(book, minutes: Int((run.budget / 60).rounded()))
        case .reflect:
            guard let book = run.books.first(where: { $0.id == bookID }) else { return nil }
            return .reflect(book, finished: book.status == .finished)
        case .done:
            return nil
        }
    }

    mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool {
        switch response {
        case .bookPicked(var book):
            book.status = .reading
            book.started = book.started ?? run.today
            book.updatedAt = run.now
            run.books.append(book)
            run.changedBooks.insert(book.id)
            bookID = book.id
            stage = .read
            return true
        case .readingDone(let page, let finished, let feel, let minutes):
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
            run.session.reading = ReadingLog(bookID: id, fromPage: from, toPage: book.page, minutes: minutes)
            stage = .reflect
            return true
        case .reflection(let text):
            guard let id = bookID else { return false }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, let book = run.books.first(where: { $0.id == id }) {
                run.newReflections.append(Reflection(bookID: id, date: run.now, kind: book.status == .finished ? .book : .section,
                                                     page: book.page, text: trimmed, updatedAt: run.now))
            }
            stage = .done
            return true
        default:
            return false
        }
    }
}
