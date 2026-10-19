import Foundation
import SystemCore
import Testing

@testable import MindEngine

/// What the shelf, writing and course destinations list: grouped, searched and sorted.
struct LibraryTests {
    let today = Day(year: 2026, month: 10, day: 14)

    func book(_ title: String, author: String = "Anne Author", status: BookStatus, finished: Day? = nil, language: Language? = nil) -> Book {
        Book(
            title: title, author: author, tier: 4, pages: 300, genres: [.literary], status: status, started: today.adding(days: -30),
            finished: finished, language: language)
    }

    @Test func searchIgnoresCaseAndAccentsAndWantsEveryWord() {
        #expect(LibrarySearch.matches("cafe", "The Last Night at the Café"))
        #expect(LibrarySearch.matches("LAST night", "The Last Night at the Café"))
        #expect(!LibrarySearch.matches("last morning", "The Last Night at the Café"), "every word typed must be there")
        #expect(LibrarySearch.matches("  ", "Anything"), "an empty search keeps everything")
        #expect(LibrarySearch.matches("austen", "Emma", "Jane Austen"), "any field counts")
    }

    @Test func theShelfIsGroupedNewestFirst() {
        let books = [
            book("Persuasion", status: .finished, finished: today.adding(days: -40)),
            book("Emma", status: .finished, finished: today.adding(days: -2)),
            book("Dune", author: "Frank Herbert", status: .reading),
            book("Ulysses", status: .abandoned, finished: today.adding(days: -9)),
            book("Middlemarch", status: .readBefore),
            book("Kiki's Delivery Service", status: .reading, language: .japanese),
        ]
        let shelf = ShelfSections(books: books)
        #expect(shelf.current?.title == "Dune", "a graded reader in Japanese lives with Japanese")
        #expect(shelf.finished.map(\.title) == ["Emma", "Persuasion"])
        #expect(shelf.setAside.map(\.title) == ["Ulysses"])
        #expect(shelf.readBefore.map(\.title) == ["Middlemarch"])

        let herbert = ShelfSections(books: books, query: "herbert")
        #expect(herbert.current?.title == "Dune")
        #expect(herbert.finished.isEmpty && herbert.setAside.isEmpty && herbert.readBefore.isEmpty)
        #expect(ShelfSections(books: books, query: "nothing like it").isEmpty)
    }

    @Test func writingIsNewestFirstAndSearchable() {
        let first = WritingPiece(
            date: today.adding(days: -20).date(), exercise: .prompt, writingKind: .creative, prompt: "The last shift at the café",
            text: "The lights went down.")
        let second = WritingPiece(
            date: today.date(), exercise: .practical, writingKind: .practical, prompt: "Rewrite the notice", text: "Please keep the door shut.")
        #expect(PieceSearch.matching([first, second], query: "").map(\.id) == [second.id, first.id])
        #expect(PieceSearch.matching([first, second], query: "cafe").map(\.id) == [first.id], "the prompt counts")
        #expect(PieceSearch.matching([first, second], query: "door").map(\.id) == [second.id], "and the text")
    }

    @Test func aCoursesWordsShowWhereEachMemoryStands() throws {
        let deck = Fixtures.deck(words: 40, sentences: 10)
        let now = today.date().addingTimeInterval(10 * 3600)
        func card(_ rank: Int, _ memory: Memory?, knownBefore: Bool = false) -> MemoryCard {
            MemoryCard(key: .word(100_000 + rank), memory: memory, introduced: now.addingTimeInterval(-86_400 * 30), knownBefore: knownBefore)
        }
        let day = 86_400.0
        let cards = [
            card(3, nil),
            card(1, Memory(stability: 4, difficulty: 5, lastReview: now - 5 * day, due: now - day)),
            card(2, Memory(stability: 6, difficulty: 5, lastReview: now - day, due: now + 5 * day)),
            card(4, Memory(stability: 40, difficulty: 4, lastReview: now - 10 * day, due: now + 30 * day, reps: 6, lapses: 1)),
            card(5, Memory(stability: 3, difficulty: 3, lastReview: now - day, due: now + 2 * day), knownBefore: true),
            MemoryCard(key: .kana("あ"), memory: Memory(stability: 30, difficulty: 3, lastReview: now, due: now + 30 * day), introduced: now),
            MemoryCard(key: .word(999_999), memory: nil, introduced: now),
        ]
        let rows = CourseWord.rows(.japanese, cards: Dictionary(uniqueKeysWithValues: cards.map { ($0.key, $0) }), deck: deck, today: today, now: now)
        #expect(rows.map(\.rank) == [1, 2, 3, 4, 5], "most common first; kana and words not in the deck left out")
        #expect(rows.map(\.state) == [.due, .known, .learning, .mastered, .mastered])
        #expect(rows[2].due == nil && rows[2].recall == nil, "nothing scheduled while learning")
        let recall = try #require(rows[1].recall)
        #expect(recall > 0.9 && recall <= 1)
        #expect(rows[3].reviews == 6 && rows[3].lapses == 1)
        #expect(rows[1].text == "ご2" && rows[1].reading == "", "a word written in kana has no separate reading")
        #expect(rows[2].text == "語3" && rows[2].reading == "ご3", "a kanji word keeps its kana reading")

        #expect(CourseWord.counts(rows) == [.due: 1, .known: 1, .learning: 1, .mastered: 2])
        #expect(CourseWord.filter(rows, query: "", state: .mastered).map(\.rank) == [4, 5])
        #expect(CourseWord.filter(rows, query: "meaning 2", state: nil).map(\.rank) == [2])
        #expect(CourseWord.rows(.spanish, cards: [:], deck: deck, today: today, now: now).isEmpty)
    }

    @Test func spanishWordsShowTheirStressAsTheReading() {
        let word = Word(id: 7, language: .spanish, rank: 1, text: "corazón", meaning: "heart")
        let deck = LanguageDeck(language: .spanish, words: [word])
        let now = today.date()
        let card = MemoryCard(key: .word(7, .spanish), introduced: now)
        let rows = CourseWord.rows(.spanish, cards: [card.key: card], deck: deck, today: today, now: now)
        #expect(rows.map(\.reading) == [SpanishSounds.guide("corazón") ?? ""])
        #expect(rows.first?.reading.contains("ZÓN") == true)
        #expect(CourseWord.rows(.japanese, cards: [card.key: card], deck: deck, today: today, now: now).isEmpty, "each language its own")
    }
}
