import Foundation

/// Builds language questions, for any pack. Every one is multiple choice with believable wrong answers (the same
/// part of speech, from nearby in the deck), so it can be answered on a phone in seconds and
/// marked without asking the person to judge themselves.
public enum LanguageQuiz {
    /// Ways to ask about a word. They rotate across reviews, so no single cue carries it.
    public enum WordAsk: String, Sendable, CaseIterable {
        case meaning, reading, listening
    }

    /// The ask for a word's nth review: meaning first, then reading (for kanji words) and listening.
    public static func ask(for word: Word, reps: Int) -> WordAsk {
        let order: [WordAsk] = word.hasKanji ? [.meaning, .reading, .listening, .meaning, .listening, .reading] : [.meaning, .listening]
        return order[reps % order.count]
    }

    public static func question(_ word: Word, ask: WordAsk, kind: AttemptKind, deck: LanguageDeck, seed: String) -> Question {
        var rng = SeededRandom(seed, word.key.raw, ask.rawValue)
        let reveal = Reveal.word(word, kanji: deck.kanji(in: word))
        let id = "\(word.key.raw).\(ask.rawValue).\(seed)"
        switch ask {
        case .meaning:
            return .choosing(id: id, key: word.key, kind: kind, instruction: "What does it mean?", prompt: .foreign(word.text, word.language),
                             correct: word.meaning, wrong: wrongMeanings(for: word, deck: deck, rng: &rng), expectedSeconds: 6,
                             reveal: reveal, rng: &rng)
        case .reading:
            return .choosing(id: id, key: word.key, kind: kind, instruction: "How is it read?", prompt: .foreign(word.text, word.language),
                             correct: word.kana, wrong: wrongReadings(for: word, deck: deck, rng: &rng), style: .foreign,
                             expectedSeconds: 6, reveal: reveal, rng: &rng)
        case .listening:
            return .choosing(id: id, key: word.key, kind: kind, instruction: "What did you hear?", prompt: .audio(word.kana, word.language),
                             correct: word.meaning, wrong: wrongMeanings(for: word, deck: deck, rng: &rng), expectedSeconds: 8,
                             reveal: reveal, rng: &rng)
        }
    }

    public static func question(_ kana: Kana, reps: Int, kind: AttemptKind, introduced: [Kana], seed: String) -> Question {
        var rng = SeededRandom(seed, kana.kana)
        let pool = (KanaTable.lookalikes(of: kana.kana).compactMap { KanaTable.byKana[$0] }
            + introduced.filter { $0.script == kana.script }.shuffled(using: &rng)
            + KanaTable.kana(kana.script).filter { $0.group == kana.group }.shuffled(using: &rng))
            .filter { $0.romaji != kana.romaji }
        let id = "\(kana.key.raw).\(reps).\(seed)"
        if reps % 2 == 1 {
            // Hear it, pick the kana.
            return .choosing(id: id, key: kana.key, kind: kind, instruction: "Which did you hear?", prompt: .audio(kana.kana, .japanese),
                             correct: kana.kana, wrong: pool.map(\.kana), style: .foreign, expectedSeconds: 5,
                             reveal: .note("\(kana.kana) is “\(kana.romaji)”"), rng: &rng)
        }
        return .choosing(id: id, key: kana.key, kind: kind, instruction: "How is it said?", prompt: .foreign(kana.kana, .japanese),
                         correct: kana.romaji, wrong: pool.map(\.romaji), expectedSeconds: 4,
                         reveal: .note("\(kana.kana) is “\(kana.romaji)”"), rng: &rng)
    }

    /// Hear a sentence, pick what it means. Wrong answers are translations of other sentences of
    /// about the same length, so length alone doesn't give it away.
    public static func sentence(_ sentence: Sentence, language: Language, kind: AttemptKind, others: [Sentence], seed: String,
                                key: CardKey) -> Question {
        var rng = SeededRandom(seed, "\(sentence.id)")
        let wrong = others.filter { $0.id != sentence.id }
            .sorted { abs($0.english.count - sentence.english.count) < abs($1.english.count - sentence.english.count) }
            .prefix(8).shuffled(using: &rng).map(\.english)
        // Japanese packs a sentence into fewer characters than a Latin script.
        let perCharacter = language.pack.script == .kanaKanji ? 0.5 : 0.2
        var question = Question.choosing(id: "sentence.\(sentence.id).\(seed)", key: key, kind: kind, instruction: "What does it mean?",
                                         prompt: .audio(sentence.text, language), correct: sentence.english, wrong: wrong,
                                         expectedSeconds: 12 + Double(sentence.text.count) * perCharacter, reveal: .sentence(sentence, language),
                                         rng: &rng)
        question.allowsDontKnow = kind == .test
        return question
    }

    static func wrongMeanings(for word: Word, deck: LanguageDeck, rng: inout SeededRandom) -> [String] {
        let near = neighbours(of: word, deck: deck, rng: &rng)
        let same = near.filter { $0.pos == word.pos }
        let mine = Question.normalised(word.meaning)
        return (same + near).map(\.meaning).filter {
            let other = Question.normalised($0)
            return other != mine && !other.contains(mine) && !mine.contains(other)
        }
    }

    static func wrongReadings(for word: Word, deck: LanguageDeck, rng: inout SeededRandom) -> [String] {
        let near = neighbours(of: word, deck: deck, rng: &rng)
        // Readings that share a kanji or a length look most alike.
        let shared = near.filter { other in other.kanjiChars.contains { word.kanjiChars.contains($0) } }
        let sameLength = near.filter { $0.kana.count == word.kana.count }
        var out = (shared + sameLength + near).map(\.kana).filter { $0 != word.kana }
        // A lengthened or shortened vowel is the classic misreading: きょう for きよう.
        if let variant = vowelVariant(word.kana) { out.insert(variant, at: min(1, out.count)) }
        return out
    }

    /// Words of similar rank, shuffled.
    static func neighbours(of word: Word, deck: LanguageDeck, rng: inout SeededRandom) -> [Word] {
        let words = deck.words
        guard let index = words.firstIndex(where: { $0.id == word.id }) ?? words.firstIndex(where: { $0.rank >= word.rank }) else {
            return Array(words.shuffled(using: &rng).prefix(30))
        }
        let spread = max(60, word.rank / 4)
        let low = max(0, index - spread), high = min(words.count, index + spread + 1)
        return Array(words[low..<high].filter { $0.id != word.id }.shuffled(using: &rng).prefix(40))
    }

    static func vowelVariant(_ kana: String) -> String? {
        if kana.contains("ょう") { return kana.replacingOccurrences(of: "ょう", with: "よう") }
        if kana.contains("う") && kana.count > 2 {
            return kana.replacingOccurrences(of: "う", with: "", options: [], range: kana.range(of: "う", options: .backwards))
        }
        if kana.contains("っ") { return kana.replacingOccurrences(of: "っ", with: "") }
        return nil
    }
}
