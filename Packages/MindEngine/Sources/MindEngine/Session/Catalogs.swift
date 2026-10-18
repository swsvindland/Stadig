import Foundation

/// The content a session draws on: each language's deck, the grammar bank and the reading ladder.
/// Maths problems are generated, so they need no catalog, but statistics problems can use the
/// numbers the other System apps publish.
public struct Catalogs: Sendable {
    public var decks: [Language: LanguageDeck]
    public var writing: WritingBank
    public var ladder: ReadingLadder
    /// Steps, training and food from Lift Track and Macro Track; empty when they aren't installed.
    public var systemData: SystemData

    public init(decks: [Language: LanguageDeck] = [:], writing: WritingBank = .standard, ladder: ReadingLadder = .standard,
                systemData: SystemData = .none) {
        self.decks = decks
        self.writing = writing
        self.ladder = ladder
        self.systemData = systemData
    }

    public func deck(_ language: Language) -> LanguageDeck? { decks[language] }
    public func deck(for domain: Domain) -> LanguageDeck? { domain.language.flatMap { decks[$0] } }
}
