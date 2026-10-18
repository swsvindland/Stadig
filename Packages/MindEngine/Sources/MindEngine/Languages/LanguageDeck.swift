import Foundation
import OSLog
import SQLite3

let mindLog = Logger(subsystem: "dev.svindland.stadig.mind", category: "engine")

/// A word in a language's deck, in the order it's taught: how common it is in everyday sentences.
public struct Word: Hashable, Sendable, Identifiable {
    public var id: Int
    public var language: Language
    public var rank: Int
    /// As it's usually written: in Japanese kanji, or kana for words usually written in kana.
    public var text: String
    /// How it's read: kana for Japanese; the word itself where the script needs no reading.
    public var kana: String
    /// The kanji spelling, even for words usually written in kana.
    public var kanji: String?
    /// The short meaning used as an answer choice ("to eat").
    public var meaning: String
    /// Up to three senses ("to eat; to live on, to live off").
    public var meanings: String
    public var pos: String
    public var kanjiChars: String

    public init(
        id: Int, language: Language = .japanese, rank: Int, text: String, kana: String? = nil, kanji: String? = nil,
        meaning: String, meanings: String? = nil, pos: String = "noun", kanjiChars: String? = nil
    ) {
        self.id = id
        self.language = language
        self.rank = rank
        self.text = text
        self.kana = kana ?? text
        self.kanji = kanji
        self.meaning = meaning
        self.meanings = meanings ?? meaning
        self.pos = pos
        self.kanjiChars = kanjiChars ?? String(text.filter { $0.isKanji })
    }

    public var key: CardKey { .word(id, language) }
    public var reading: String { kana }
    /// Written with kanji, so its reading is worth asking.
    public var hasKanji: Bool { text.contains { $0.isKanji } }
    public var hasKatakana: Bool { KanaTable.containsKatakana(text) }
}

public struct Kanji: Hashable, Sendable {
    public var literal: String
    public var meanings: String
    public var onyomi: String
    public var kunyomi: String
    public var strokes: Int

    public init(literal: String, meanings: String, onyomi: String = "", kunyomi: String = "", strokes: Int = 0) {
        self.literal = literal
        self.meanings = meanings
        self.onyomi = onyomi
        self.kunyomi = kunyomi
        self.strokes = strokes
    }
}

/// A Tatoeba sentence in the language and its English translation. `level` is the rank of its
/// rarest word: every word in it is at or below that rank.
public struct Sentence: Hashable, Sendable, Identifiable {
    public var id: Int
    public var text: String
    public var english: String
    public var level: Int
    public var words: [Int]

    public init(id: Int, text: String, english: String, level: Int, words: [Int]) {
        self.id = id
        self.text = text
        self.english = english
        self.level = level
        self.words = words
    }
}

extension Character {
    var isKanji: Bool { unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || $0.value == 0x3005 } }
}

/// A language's catalog: every word (and, for Japanese, kanji) in memory, since they're small;
/// sentences read on demand. Built by Scripts/build-japanese-catalog.py (JMdict, KANJIDIC2 and
/// Tatoeba) and its Spanish counterpart, in one schema.
public final class LanguageDeck: @unchecked Sendable {
    public let language: Language
    public let words: [Word]
    public let attribution: String
    private let byID: [Int: Word]
    private let kanjiByLiteral: [String: Kanji]
    private let source: SentenceSource

    private enum SentenceSource {
        case memory([Sentence])
        case sqlite(OpaquePointer)
    }

    /// For tests and previews.
    public init(language: Language = .japanese, words: [Word], kanji: [Kanji] = [], sentences: [Sentence] = []) {
        self.language = language
        self.words = words.sorted { $0.rank < $1.rank }
        byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        kanjiByLiteral = Dictionary(kanji.map { ($0.literal, $0) }, uniquingKeysWith: { a, _ in a })
        source = .memory(sentences.sorted { $0.level < $1.level })
        attribution = ""
    }

    /// Opens a catalog read-only. Nil if it's missing or unreadable.
    public init?(url: URL, language: Language = .japanese) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
            mindLog.error("Couldn't open the \(language.pack.name, privacy: .public) catalog at \(url.path, privacy: .public)")
            return nil
        }
        self.language = language
        var words: [Word] = []
        Self.query(handle, "SELECT id, rank, word, kana, kanji, meaning, meanings, pos, kanji_chars FROM words ORDER BY rank") { row in
            words.append(
                Word(
                    id: Int(sqlite3_column_int64(row, 0)), language: language, rank: Int(sqlite3_column_int64(row, 1)),
                    text: Self.text(row, 2), kana: Self.text(row, 3), kanji: Self.optionalText(row, 4),
                    meaning: Self.text(row, 5), meanings: Self.text(row, 6), pos: Self.text(row, 7),
                    kanjiChars: Self.text(row, 8)))
        }
        var kanji: [Kanji] = []
        if language.pack.script == .kanaKanji {
            Self.query(handle, "SELECT literal, meanings, onyomi, kunyomi, strokes FROM kanji") { row in
                kanji.append(
                    Kanji(
                        literal: Self.text(row, 0), meanings: Self.text(row, 1), onyomi: Self.text(row, 2),
                        kunyomi: Self.text(row, 3), strokes: Int(sqlite3_column_int64(row, 4))))
            }
        }
        var attribution = ""
        Self.query(handle, "SELECT value FROM meta WHERE key = 'attribution'") { attribution = Self.text($0, 0) }
        guard !words.isEmpty else {
            sqlite3_close(handle)
            return nil
        }
        self.words = words
        byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        kanjiByLiteral = Dictionary(kanji.map { ($0.literal, $0) }, uniquingKeysWith: { a, _ in a })
        source = .sqlite(handle)
        self.attribution = attribution
    }

    deinit {
        if case .sqlite(let handle) = source { sqlite3_close(handle) }
    }

    /// A language's bundled catalog, if this build ships one.
    public static func bundled(_ language: Language, in bundle: Bundle = .main) -> LanguageDeck? {
        bundle.url(forResource: language.pack.catalog, withExtension: "db").flatMap { LanguageDeck(url: $0, language: language) }
    }

    /// Every language whose catalog this build ships.
    public static func bundled(in bundle: Bundle = .main) -> [Language: LanguageDeck] {
        Dictionary(uniqueKeysWithValues: Language.allCases.compactMap { language in bundled(language, in: bundle).map { (language, $0) } })
    }

    public var isEmpty: Bool { words.isEmpty }

    public func word(_ id: Int) -> Word? { byID[id] }

    public func kanji(in word: Word) -> [Kanji] {
        word.kanjiChars.compactMap { kanjiByLiteral[String($0)] }
    }

    /// Example sentences using a word, easiest first, none harder than `maxLevel`.
    public func sentences(with wordID: Int, maxLevel: Int, limit: Int = 3) -> [Sentence] {
        switch source {
        case .memory(let all):
            return Array(all.filter { $0.words.contains(wordID) && $0.level <= maxLevel }.prefix(limit))
        case .sqlite(let handle):
            var out: [Sentence] = []
            Self.query(
                handle,
                """
                SELECT s.id, s.jp, s.en, s.level, s.words FROM sentence_words w JOIN sentences s ON s.id = w.sentence
                WHERE w.word = ? AND w.level <= ? ORDER BY w.level, s.length LIMIT ?
                """, bind: [wordID, maxLevel, limit]
            ) { out.append(Self.sentence($0)) }
            return out
        }
    }

    /// Sentences whose rarest word falls in `levels`, a sample spread across the range by id.
    /// Each `skip` (a day, a test's own offset) gets a sample of its own.
    public func sentences(levels: ClosedRange<Int>, limit: Int, skip: Int = 0) -> [Sentence] {
        let offset = Self.sampleOffset(skip)
        switch source {
        case .memory(let all):
            let inRange = all.filter { levels.contains($0.level) }
            return Array(
                inRange.sorted { (Self.sampleOrder($0.id, offset: offset), $0.id) < (Self.sampleOrder($1.id, offset: offset), $1.id) }
                    .prefix(limit))
        case .sqlite(let handle):
            var out: [Sentence] = []
            Self.query(
                handle,
                """
                SELECT id, jp, en, level, words FROM sentences WHERE level BETWEEN ? AND ?
                ORDER BY (id * 2654435761 + ?) % 1000003, id LIMIT ?
                """, bind: [levels.lowerBound, levels.upperBound, offset, limit]
            ) { out.append(Self.sentence($0)) }
            return out
        }
    }

    /// Where a sample starts for a `skip`. Hashed, because adding `skip` itself only turns one
    /// fixed order a slot a day, and the same few sentences came back for months.
    static func sampleOffset(_ skip: Int) -> Int {
        var rng = SeededRandom("sentences", "\(skip)")
        return Int(rng.next() % 1_000_003)
    }

    /// A sentence's place in the sample for an offset: the order the catalog query uses.
    static func sampleOrder(_ id: Int, offset: Int) -> Int { (id &* 2_654_435_761 &+ offset) % 1_000_003 }

    // MARK: SQLite

    // Every catalog shares one schema. The sentences table's `jp` column holds the sentence in the
    // catalog's language and `en` its English translation (the names come from the first, Japanese, catalog).
    private static func sentence(_ row: OpaquePointer) -> Sentence {
        Sentence(
            id: Int(sqlite3_column_int64(row, 0)), text: text(row, 1), english: text(row, 2), level: Int(sqlite3_column_int64(row, 3)),
            words: text(row, 4).split(separator: ",").compactMap { Int($0) })
    }

    private static func query(_ db: OpaquePointer, _ sql: String, bind: [Int] = [], row: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            mindLog.error("Catalog query failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(statement) }
        for (i, value) in bind.enumerated() { sqlite3_bind_int64(statement, Int32(i + 1), sqlite3_int64(value)) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }

    private static func text(_ row: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(row, column).map { String(cString: $0) } ?? ""
    }

    private static func optionalText(_ row: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_type(row, column) == SQLITE_NULL ? nil : text(row, column)
    }
}
