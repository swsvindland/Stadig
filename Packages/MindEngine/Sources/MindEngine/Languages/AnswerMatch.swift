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
    /// katakana as hiragana, full-width letters and digits as plain ones, Japanese numerals as
    /// digits and, in Spanish, numbers in words.
    public static func normalised(_ text: String, language: Language) -> String {
        var s = text.precomposedStringWithCompatibilityMapping.lowercased()
        switch language.pack.script {
        case .kanaKanji:
            s = String(
                String.UnicodeScalarView(
                    s.unicodeScalars.map { scalar in
                        (0x30A1...0x30F6).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x60)! : scalar
                    }))
            s = japaneseDigits(s)
            return String(s.filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol || $0 == "ー" })
        case .none, .hangul:
            s = s.replacingOccurrences(of: "ñ", with: "\u{1}")
            s = s.folding(options: [.diacriticInsensitive], locale: nil).replacingOccurrences(of: "\u{1}", with: "ñ")
            let words = s.split { !$0.isLetter && !$0.isNumber }.map { word -> String in
                guard language == .spanish, word.allSatisfy(\.isASCII), let number = Int(word) else { return String(word) }
                return spanishWords(number) ?? String(word)
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
            // A number's own words (百 and 円 in 三百円) are looked for in its kanji too.
            let saidKanji = kanjiNumerals(said)
            let found = words.filter { word in
                stems(word).contains { stem in
                    let want = normalised(stem, language: language)
                    return said.contains(want) || saidKanji.contains(kanjiNumerals(want))
                }
            }
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

    // MARK: Numbers

    /// Recognition writes numbers as digits ("12人", "Tiene 30 años"), sentences and deck words
    /// mostly in words or kanji, so both sides are brought to one form before comparing.

    static let kanjiDigits: [Character: Int] = ["〇": 0, "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
    static let kanjiUnits: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    static let kanjiPowers: [Character: Int] = ["万": 10_000, "億": 100_000_000]

    /// A digit, in kanji or (after `normalised`'s width folding) ASCII.
    static func digit(_ character: Character) -> Int? {
        if let value = kanjiDigits[character] { return value }
        return character.isASCII ? character.wholeNumberValue : nil
    }

    /// Each run of numerals as digits: kanji written out in full (十二, 二千二十四, 百), digit by
    /// digit (二〇二四), or mixed with digits as recognition writes big numbers (3万, 1万5000), so
    /// 十二 and 12, and 三万 and 3万 and 30,000, compare equal.
    static func japaneseDigits(_ text: String) -> String {
        let characters = Array(text)
        var out = ""
        var run: [Character] = []
        func flush() {
            guard !run.isEmpty else { return }
            out += japaneseNumber(run)
            run = []
        }
        for (i, character) in characters.enumerated() {
            // A thousands comma inside digits ("30,000") is part of the number.
            if character == ",", run.last.map({ $0.isASCII && $0.isNumber }) == true, i + 1 < characters.count,
                characters[i + 1].isASCII && characters[i + 1].isNumber
            {
                continue
            }
            if digit(character) != nil || kanjiUnits[character] != nil || kanjiPowers[character] != nil {
                run.append(character)
            } else {
                flush()
                out.append(character)
            }
        }
        flush()
        return out
    }

    /// One run as digits. A run too big to add up (typed or pasted, it can be anything) is left as
    /// it was.
    static func japaneseNumber(_ run: [Character]) -> String {
        // Digit by digit, as years are often written.
        let digits = run.compactMap(Self.digit)
        if digits.count == run.count { return digits.map(String.init).joined() }
        func scaled(_ a: Int, by b: Int, plus c: Int) -> Int? {
            let (product, overflowMultiplying) = a.multipliedReportingOverflow(by: b)
            let (sum, overflowAdding) = product.addingReportingOverflow(c)
            return overflowMultiplying || overflowAdding ? nil : sum
        }
        var total = 0
        var section = 0
        var digit = 0
        for character in run {
            if let value = Self.digit(character) {
                guard let next = scaled(digit, by: 10, plus: value) else { return String(run) }
                digit = next
            } else if let unit = kanjiUnits[character] {
                // No digit before 十, 百 or 千 means one of it.
                guard let next = scaled(digit == 0 ? 1 : digit, by: unit, plus: section) else { return String(run) }
                section = next
                digit = 0
            } else if let power = kanjiPowers[character] {
                guard let group = scaled(section, by: 1, plus: digit), let next = scaled(group == 0 ? 1 : group, by: power, plus: total) else {
                    return String(run)
                }
                total = next
                section = 0
                digit = 0
            }
        }
        return scaled(total, by: 1, plus: section).flatMap { scaled($0, by: 1, plus: digit) }.map(String.init) ?? String(run)
    }

    /// Digits written back as kanji numerals (300 as 三百), for finding the deck words a number is
    /// made of: 百 is in 三百円, but "100" isn't in "300円". Numbers from a trillion up stay digits.
    static func kanjiNumerals(_ text: String) -> String {
        var out = ""
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            out += Int(run).flatMap(kanjiNumber) ?? run
            run = ""
        }
        for character in text {
            if character.isASCII && character.isNumber {
                run.append(character)
            } else {
                flush()
                out.append(character)
            }
        }
        flush()
        return out
    }

    static func kanjiNumber(_ n: Int) -> String? {
        guard n >= 0 && n < 1_000_000_000_000 else { return nil }
        if n == 0 { return "〇" }
        let names: [Character] = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        func group(_ n: Int) -> String {
            var out = ""
            for (unit, mark) in [(1000, "千"), (100, "百"), (10, "十")] where n / unit % 10 > 0 {
                let count = n / unit % 10
                out += (count == 1 ? "" : String(names[count])) + mark
            }
            if n % 10 > 0 { out.append(names[n % 10]) }
            return out
        }
        let oku = n / 100_000_000
        let man = n / 10_000 % 10_000
        let rest = n % 10_000
        return (oku > 0 ? group(oku) + "億" : "") + (man > 0 ? group(man) + "万" : "") + group(rest)
    }

    static let spanishSmall = [
        "cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce",
        "trece", "catorce", "quince", "dieciseis", "diecisiete", "dieciocho", "diecinueve", "veinte", "veintiuno",
        "veintidos", "veintitres", "veinticuatro", "veinticinco", "veintiseis", "veintisiete", "veintiocho", "veintinueve",
    ]
    static let spanishTens = ["", "", "", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa"]
    static let spanishHundreds = [
        "", "ciento", "doscientos", "trescientos", "cuatrocientos", "quinientos", "seiscientos", "setecientos",
        "ochocientos", "novecientos",
    ]

    /// A number in Spanish words, accents left off as `normalised` folds them: 31 is "treinta y
    /// uno", 2024 "dos mil veinticuatro". Nil from a million up.
    static func spanishWords(_ n: Int) -> String? {
        guard n >= 0 && n < 1_000_000 else { return nil }
        if n < 30 { return spanishSmall[n] }
        if n < 100 { return spanishTens[n / 10] + (n % 10 == 0 ? "" : " y " + spanishSmall[n % 10]) }
        if n == 100 { return "cien" }
        if n < 1000 { return spanishHundreds[n / 100] + (n % 100 == 0 ? "" : " " + (spanishWords(n % 100) ?? "")) }
        let thousands = n / 1000
        let rest = n % 1000
        // "veintiún mil", not "veintiuno mil"; a thousand on its own is just "mil".
        var head = thousands == 1 ? "" : spanishWords(thousands) ?? ""
        if head.hasSuffix("uno") { head.removeLast() }
        let mil = head.isEmpty ? "mil" : head + " mil"
        return rest == 0 ? mil : mil + " " + (spanishWords(rest) ?? "")
    }
}
