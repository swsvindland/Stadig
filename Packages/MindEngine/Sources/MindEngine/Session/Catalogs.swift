import Foundation

/// The content a session draws on: each language's deck, the grammar bank and the reading ladder.
/// Maths problems are generated, so they need no catalog.
public struct Catalogs: Sendable {
    public var decks: [Language: LanguageDeck]
    public var writing: WritingBank
    public var ladder: ReadingLadder

    public init(decks: [Language: LanguageDeck] = [:], writing: WritingBank = .standard, ladder: ReadingLadder = .standard) {
        self.decks = decks
        self.writing = writing
        self.ladder = ladder
    }

    public func deck(_ language: Language) -> LanguageDeck? { decks[language] }
    public func deck(for domain: Domain) -> LanguageDeck? { domain.language.flatMap { decks[$0] } }
}
