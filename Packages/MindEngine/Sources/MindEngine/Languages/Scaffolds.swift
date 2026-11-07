import Foundation

/// Text in the language with help on what isn't mastered yet: furigana over a kanji word, romaji
/// under a kana (and under a kanji word whose reading's kana aren't), a stress guide under a Spanish word. Each item's help goes once that item is
/// mastered, so a sentence loses its scaffolding word by word rather than all at once.
public struct Scaffolded: Hashable, Sendable {
    public enum Help: String, Hashable, Sendable {
        /// Kana over kanji.
        case furigana
        /// Latin letters under kana.
        case romaji
        /// Syllables with the stressed one in capitals: co·ra·ZÓN.
        case stress
    }

    public struct Segment: Hashable, Sendable {
        public var text: String
        /// Nil once the item is mastered (or for text that needs none).
        public var help: String?
        public var kind: Help

        public init(text: String, help: String? = nil, kind: Help = .furigana) {
            self.text = text
            self.help = help
            self.kind = kind
        }
    }

    public var language: Language
    public var segments: [Segment]

    public init(language: Language, segments: [Segment]) {
        self.language = language
        // Neighbouring plain text joins up, so it wraps as words rather than letters.
        var joined: [Segment] = []
        for segment in segments {
            if segment.help == nil, let last = joined.last, last.help == nil {
                joined[joined.count - 1].text += segment.text
            } else {
                joined.append(segment)
            }
        }
        self.segments = joined
    }

    public static func plain(_ text: String, _ language: Language) -> Scaffolded {
        Scaffolded(language: language, segments: [Segment(text: text)])
    }

    public var text: String { segments.map(\.text).joined() }
    public var hasHelp: Bool { segments.contains { $0.help != nil } }
}

/// What gets help, and when it stops. A word is mastered once its memory lasts three weeks, or it
/// was known before starting and hasn't slipped since; words below the placement level that were
/// never carded count as known, as they do for teaching. A kana is mastered the same way; romaji
/// only ever shows for someone who said they don't read kana yet.
public enum Scaffolds {
    public static let masteredStability = 21.0

    public struct Context: Sendable {
        public var cards: [CardKey: MemoryCard]
        public var frontier: Int
        public var readsKana: Bool?

        public init(cards: [CardKey: MemoryCard], frontier: Int, readsKana: Bool?) {
            self.cards = cards
            self.frontier = frontier
            self.readsKana = readsKana
        }

        func mastered(_ key: CardKey) -> Bool {
            guard let card = cards[key], let memory = card.memory else { return false }
            return memory.stability >= Scaffolds.masteredStability || (card.knownBefore && memory.lapses == 0)
        }

        func mastered(_ word: Word) -> Bool {
            if cards[word.key] == nil { return word.rank <= frontier }
            return mastered(word.key)
        }

        var romaji: Bool { readsKana == false }
    }

    /// A word as a prompt: its reading over the kanji (or its stress guide) until it's mastered.
    public static func word(_ word: Word, _ context: Context) -> Scaffolded {
        let mastered = context.mastered(word)
        switch word.language.pack.script {
        case .kanaKanji:
            guard word.hasKanji, let split = furigana(word) else {
                return Scaffolded(language: word.language, segments: kana(word.text, context))
            }
            return Scaffolded(
                language: word.language,
                segments: kana(split.prefix, context)
                    + [stem(split.stem, reading: mastered ? nil : split.reading, context)] + kana(split.suffix, context))
        case .none:
            guard !mastered, word.language.pack.pronunciation == .spanish, let guide = SpanishSounds.guide(word.text) else {
                return .plain(word.text, word.language)
            }
            return Scaffolded(language: word.language, segments: [Scaffolded.Segment(text: word.text, help: guide, kind: .stress)])
        case .hangul:
            return .plain(word.text, word.language)
        }
    }

    /// A sentence: help on each of its words that isn't mastered yet.
    public static func sentence(_ sentence: Sentence, deck: LanguageDeck, _ context: Context) -> Scaffolded {
        let words = sentence.words.compactMap(deck.word)
        switch deck.language.pack.script {
        case .kanaKanji: return japanese(sentence.text, words: words, context)
        case .none: return spanish(sentence.text, words: words, context, language: deck.language)
        case .hangul: return .plain(sentence.text, deck.language)
        }
    }

    /// A line with its own kana reading (a dialogue line): the reading shows over the whole line
    /// until it's been practised `seen` times, then only romaji for kana not yet mastered.
    public static func line(_ text: String, reading: String?, language: Language, seen: Int, _ context: Context) -> Scaffolded {
        guard language.pack.script == .kanaKanji else { return .plain(text, language) }
        if let reading, seen < 3, reading != text, text.contains(where: \.isKanji) {
            return Scaffolded(language: language, segments: [Scaffolded.Segment(text: text, help: reading)])
        }
        return Scaffolded(language: language, segments: kana(text, context))
    }

    /// A dialogue line in romaji, for someone learning kana while any kana in it isn't mastered.
    /// Nil once all of it can be read.
    public static func romaji(_ line: Dialogue.Line, _ context: Context) -> String? {
        guard context.romaji, let romaji = line.romaji else { return nil }
        let unread = [line.text, line.reading].compactMap(\.self).contains { text in kana(text, context).contains { $0.help != nil } }
        return unread ? romaji : nil
    }

    // MARK: Japanese

    /// The kanji part of a word and how it's read, with the kana either side: 食べる is お-less
    /// "食" read "た" with "べる" after; お茶 is "お", then "茶" read "ちゃ".
    static func furigana(_ word: Word) -> (prefix: String, stem: String, reading: String, suffix: String)? {
        guard word.hasKanji else { return nil }
        var text = Array(word.text)
        var kana = Array(word.kana)
        var prefix = ""
        var suffix = ""
        while let t = text.last, let k = kana.last, !t.isKanji, fold(t) == fold(k), text.count > 1 {
            suffix.insert(t, at: suffix.startIndex)
            text.removeLast()
            kana.removeLast()
        }
        while let t = text.first, let k = kana.first, !t.isKanji, fold(t) == fold(k), text.count > 1 {
            prefix.append(t)
            text.removeFirst()
            kana.removeFirst()
        }
        guard text.contains(where: \.isKanji), !kana.isEmpty else { return nil }
        return (prefix, String(text), String(kana), suffix)
    }

    static func fold(_ c: Character) -> Character {
        Character(
            String(
                String.UnicodeScalarView(
                    c.unicodeScalars.map { s in
                        (0x30A1...0x30F6).contains(s.value) ? Unicode.Scalar(s.value - 0x60)! : s
                    })))
    }

    static func japanese(_ text: String, words: [Word], _ context: Context) -> Scaffolded {
        let characters = Array(text)
        var covered = [Int?](repeating: nil, count: characters.count)
        var helps: [Int: (stem: String, reading: String?)] = [:]
        // Longer stems first, so 日本 claims its characters before 本 does.
        let stems = words.compactMap { word in furigana(word).map { (word, $0.stem, $0.reading) } }
            .sorted { $0.1.count > $1.1.count }
        for (index, (word, stem, reading)) in stems.enumerated() {
            let pattern = Array(stem)
            var i = 0
            while i + pattern.count <= characters.count {
                if Array(characters[i..<(i + pattern.count)]) == pattern, covered[i..<(i + pattern.count)].allSatisfy({ $0 == nil }) {
                    for j in i..<(i + pattern.count) { covered[j] = index }
                    helps[i] = (stem, context.mastered(word) ? nil : reading)
                    i += pattern.count
                } else {
                    i += 1
                }
            }
        }
        var segments: [Scaffolded.Segment] = []
        var run = ""
        var i = 0
        while i < characters.count {
            if let help = helps[i] {
                segments += kana(run, context)
                run = ""
                segments.append(stem(help.stem, reading: help.reading, context))
                i += help.stem.count
            } else {
                run.append(characters[i])
                i += 1
            }
        }
        segments += kana(run, context)
        return Scaffolded(language: .japanese, segments: segments)
    }

    /// A kanji stem and its help: the reading over it, or for someone still learning kana, the
    /// reading in romaji under it until each of its kana is mastered. Nil `reading` for a word
    /// that's mastered.
    static func stem(_ stem: String, reading: String?, _ context: Context) -> Scaffolded.Segment {
        guard let reading else { return Scaffolded.Segment(text: stem) }
        if context.romaji, kana(reading, context).contains(where: { $0.help != nil }), let romaji = KanaTable.romaji(reading) {
            return Scaffolded.Segment(text: stem, help: romaji, kind: .romaji)
        }
        return Scaffolded.Segment(text: stem, help: reading)
    }

    /// Kana with romaji under each one not mastered yet, for someone still learning to read them.
    /// A small っ joins the kana after it and a long ー the one before.
    static func kana(_ text: String, _ context: Context) -> [Scaffolded.Segment] {
        guard !text.isEmpty else { return [] }
        guard context.romaji else { return [Scaffolded.Segment(text: text)] }
        let characters = Array(text)
        var out: [Scaffolded.Segment] = []
        var i = 0
        while i < characters.count {
            var unit = String(characters[i])
            var doubled = false
            if unit == "っ" || unit == "ッ", i + 1 < characters.count {
                doubled = true
                i += 1
                unit = String(characters[i])
            }
            if i + 1 < characters.count, KanaTable.byKana[unit + String(characters[i + 1])] != nil {
                unit += String(characters[i + 1])
                i += 1
            }
            i += 1
            guard let kana = KanaTable.byKana[unit] else {
                out.append(Scaffolded.Segment(text: (doubled ? String(characters[i - 2]) : "") + unit))
                continue
            }
            var text = (doubled ? String(characters[i - 1 - unit.count]) : "") + unit
            var romaji = (doubled ? String(kana.romaji.prefix(1)) : "") + kana.romaji
            if i < characters.count, characters[i] == "ー" {
                text += "ー"
                romaji += String(kana.romaji.suffix(1))
                i += 1
            }
            let mastered = context.mastered(kana.key)
            out.append(Scaffolded.Segment(text: text, help: mastered ? nil : romaji, kind: .romaji))
        }
        return out
    }

    // MARK: Spanish

    /// Each word of the sentence with a stress guide while the deck word it's a form of isn't
    /// mastered. Forms are matched to deck words by their shared beginning (comí, comer), so
    /// irregular forms and grammar words go without.
    static func spanish(_ text: String, words: [Word], _ context: Context, language: Language) -> Scaffolded {
        guard language.pack.pronunciation == .spanish else { return .plain(text, language) }
        let learning = words.filter { !context.mastered($0) }.map { AnswerMatch.normalised(SpanishSounds.bare($0.text), language: language) }
        var segments: [Scaffolded.Segment] = []
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            let token = AnswerMatch.normalised(current, language: language)
            let isLearning = learning.contains { lemma in
                lemma == token || (lemma.count >= 4 && token.count >= 3 && commonPrefix(lemma, token) >= min(lemma.count - 2, 4))
            }
            if isLearning, let guide = SpanishSounds.guide(current) {
                segments.append(Scaffolded.Segment(text: current, help: guide, kind: .stress))
            } else {
                segments.append(Scaffolded.Segment(text: current))
            }
            current = ""
        }
        for character in text {
            if character.isLetter {
                current.append(character)
            } else {
                flush()
                segments.append(Scaffolded.Segment(text: String(character)))
            }
        }
        flush()
        return Scaffolded(language: language, segments: segments)
    }

    static func commonPrefix(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }
}
