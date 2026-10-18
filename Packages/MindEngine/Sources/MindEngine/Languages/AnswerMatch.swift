import Foundation

/// Marks what was said (as on-device speech recognition heard it) or typed, leniently: being
/// understood is the bar, not perfect spelling. Accents, case, punctuation and katakana against
/// hiragana don't count against an answer; numbers can come back as digits; a short answer counts
/// if it's anywhere in what was said ("perro" in "el perro"); a sentence counts when most of its
/// words are there.
public enum AnswerMatch {
    /// The share of a sentence's words that has to be there.
    public static let sentenceShare = 0.75

    /// Lowercased, without accents (ñ stays: año isn't ano), punctuation or spaces in Japanese,
    /// katakana as hiragana, full-width letters and digits as plain ones, and small numbers in words.
    public static func normalised(_ text: String, language: Language) -> String {
        var s = text.precomposedStringWithCompatibilityMapping.lowercased()
        switch language.pack.script {
        case .kanaKanji:
            s = String(String.UnicodeScalarView(s.unicodeScalars.map { scalar in
                (0x30A1...0x30F6).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x60)! : scalar
            }))
            for (digits, kanji) in japaneseNumbers { s = s.replacingOccurrences(of: digits, with: kanji) }
            return String(s.filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol || $0 == "ー" })
        case .none, .hangul:
            s = s.replacingOccurrences(of: "ñ", with: "\u{1}")
            s = s.folding(options: [.diacriticInsensitive], locale: nil).replacingOccurrences(of: "\u{1}", with: "ñ")
            let words = s.split { !$0.isLetter && !$0.isNumber }.map { word -> String in
                language == .spanish ? spanishNumbers[String(word)] ?? String(word) : String(word)
            }
            return words.joined(separator: " ")
        }
    }

    /// Whether `heard` says any of the expected answers. Short answers can sit inside a longer
    /// reply, at word boundaries where the language has spaces.
    public static func matches(_ heard: String, expected: [String], language: Language) -> Bool {
        let said = normalised(heard, language: language)
        guard !said.isEmpty else { return false }
        for answer in expected {
            let want = normalised(answer, language: language)
            guard !want.isEmpty else { continue }
            if said == want { return true }
            if language.pack.script == .kanaKanji {
                if said.contains(want) { return true }
            } else if " \(said) ".contains(" \(want) ") {
                return true
            }
        }
        return false
    }

    /// How much of a sentence was said: the share of its words heard. Japanese has no spaces, so
    /// its deck words are looked for by their written stem or their kana ("食べ" or "たべ" for
    /// 食べました).
    public static func coverage(_ heard: String, of sentence: String, words: [Word], language: Language) -> Double {
        let said = normalised(heard, language: language)
        guard !said.isEmpty else { return 0 }
        if language.pack.script == .kanaKanji {
            guard !words.isEmpty else { return said == normalised(sentence, language: language) ? 1 : 0 }
            let found = words.filter { word in stems(word).contains { said.contains(normalised($0, language: language)) } }
            return Double(found.count) / Double(words.count)
        }
        let want = normalised(sentence, language: language).split(separator: " ")
        guard !want.isEmpty else { return 0 }
        var pool = said.split(separator: " ")
        var found = 0
        for word in want {
            if let i = pool.firstIndex(of: word) {
                found += 1
                pool.remove(at: i)
            }
        }
        return Double(found) / Double(want.count)
    }

    /// Ways a Japanese word shows up in a sentence: as written, in kana, and both without the
    /// ending that conjugates (食べ, たべ for 食べる).
    static func stems(_ word: Word) -> [String] {
        var out = [word.text, word.kana]
        let conjugates = word.pos == "verb" || word.pos == "i-adjective"
        if conjugates, word.text.count > 1 { out.append(String(word.text.dropLast())) }
        if conjugates, word.kana.count > 2 { out.append(String(word.kana.dropLast())) }
        if let split = Scaffolds.furigana(word), !split.stem.isEmpty { out.append(split.stem) }
        return out.filter { !$0.isEmpty }
    }

    /// Variants that count for a word said or written: with or without a noun's article; written
    /// or in kana.
    public static func variants(_ word: Word) -> [String] {
        var out = [word.text]
        if word.kana != word.text { out.append(word.kana) }
        if let kanji = word.kanji, !out.contains(kanji) { out.append(kanji) }
        let bare = SpanishSounds.bare(word.text)
        if bare != word.text { out.append(bare) }
        if word.text.hasPrefix("el/la ") {
            out += ["el " + bare, "la " + bare]
        }
        return out
    }

    static let japaneseNumbers: [(String, String)] = [("10", "十"), ("0", "〇"), ("1", "一"), ("2", "二"), ("3", "三"), ("4", "四"),
                                                       ("5", "五"), ("6", "六"), ("7", "七"), ("8", "八"), ("9", "九")]
    static let spanishNumbers: [String: String] = [
        "0": "cero", "1": "uno", "2": "dos", "3": "tres", "4": "cuatro", "5": "cinco", "6": "seis", "7": "siete", "8": "ocho",
        "9": "nueve", "10": "diez", "11": "once", "12": "doce", "15": "quince", "20": "veinte", "100": "cien", "1000": "mil",
    ]
}
