import Foundation

/// A possible slip in a piece: a word the platform's spell checker flagged, or a mechanical rule
/// that's almost never wrong to point out (the same word twice, "could of", "a apple", a sentence
/// without its capital). Deterministic, so a piece gets the same count on every device.
public struct WritingSlip: Hashable, Sendable {
    public enum Kind: String, Sendable { case spelling, mechanics }

    public var kind: Kind
    /// Where it is, in characters from the start of the text.
    public var offset: Int
    public var length: Int
    /// The words as written.
    public var text: String
    /// What to do about it, in a few words.
    public var note: String
}

/// What's measured on every piece: slips per 100 words, the range of vocabulary and how much
/// sentence lengths vary. Shown only as trends, never as a grade.
public struct WritingMetrics: Hashable, Sendable {
    public enum Key {
        public static let words = "words"
        public static let sentences = "sentences"
        public static let slips = "slips"
        public static let errors = "errorsPer100"
        public static let vocabulary = "vocabulary"
        public static let sentenceMean = "sentenceMean"
        public static let sentenceSpread = "sentenceSpread"
    }

    public var words: Int
    public var sentences: Int
    public var slips: Int
    /// Spelling and mechanical slips per 100 words.
    public var errorsPer100: Double
    /// The moving-average type–token ratio over 50-word windows (0–1), which doesn't fall just
    /// because a piece is longer. Nil under 50 words.
    public var vocabulary: Double?
    public var sentenceMean: Double?
    /// The standard deviation of sentence lengths in words. Nil under three sentences.
    public var sentenceSpread: Double?

    public var dictionary: [String: Double] {
        var out: [String: Double] = [Key.words: Double(words), Key.sentences: Double(sentences), Key.slips: Double(slips),
                                     Key.errors: errorsPer100]
        out[Key.vocabulary] = vocabulary
        out[Key.sentenceMean] = sentenceMean
        out[Key.sentenceSpread] = sentenceSpread
        return out
    }
}

/// The deterministic check behind the metrics. Spelling comes from the platform (the app passes
/// the words its spell checker flagged under both British and American English); everything else
/// is rules simple enough to defend, each with its exceptions.
public enum WritingCheck {
    public static let vocabularyWindow = 50

    public static func measure(_ text: String, misspelled: [String] = []) -> WritingMetrics {
        let chars = Array(text)
        let tokens = tokens(chars)
        let words = tokens.count
        let lengths = sentences(chars, tokens: tokens).map(\.words).filter { $0 > 0 }
        let slips = slips(chars, tokens: tokens, misspelled: misspelled).count
        var mean: Double?
        var spread: Double?
        if !lengths.isEmpty {
            let m = Double(lengths.reduce(0, +)) / Double(lengths.count)
            mean = m
            if lengths.count >= 3 {
                spread = (lengths.map { (Double($0) - m) * (Double($0) - m) }.reduce(0, +) / Double(lengths.count)).squareRoot()
            }
        }
        return WritingMetrics(words: words, sentences: lengths.count, slips: slips,
                              errorsPer100: words == 0 ? 0 : Double(slips) / Double(words) * 100,
                              vocabulary: vocabulary(tokens), sentenceMean: mean, sentenceSpread: spread)
    }

    public static func slips(_ text: String, misspelled: [String] = []) -> [WritingSlip] {
        let chars = Array(text)
        return slips(chars, tokens: tokens(chars), misspelled: misspelled)
    }

    // MARK: Words and sentences

    struct Token {
        var text: String
        var offset: Int
        var length: Int
        var lower: String
        var end: Int { offset + length }
        var hasLetters: Bool { text.contains { $0.isLetter } }
        var capitalised: Bool { text.first?.isUppercase == true }
        /// "NASA", "UK": two or more letters, all capitals.
        var acronym: Bool { text.count >= 2 && text.allSatisfy { !$0.isLetter || $0.isUppercase } }
        /// "iPhone", "eBay": a capital after the first letter of a word starting lower case.
        var mixedCase: Bool { text.first?.isLowercase == true && text.dropFirst().contains { $0.isUppercase } }
    }

    static func isJoiner(_ c: Character) -> Bool { c == "'" || c == "’" || c == "-" }

    /// Words: letters and digits, joined by apostrophes and hyphens ("don't", "well-known").
    static func tokens(_ chars: [Character]) -> [Token] {
        var out: [Token] = []
        var i = 0
        while i < chars.count {
            guard chars[i].isLetter || chars[i].isNumber else {
                i += 1
                continue
            }
            let start = i
            var j = i + 1
            while j < chars.count {
                if chars[j].isLetter || chars[j].isNumber {
                    j += 1
                } else if isJoiner(chars[j]), j + 1 < chars.count, chars[j + 1].isLetter || chars[j + 1].isNumber {
                    j += 2
                } else {
                    break
                }
            }
            let text = String(chars[start..<j])
            out.append(Token(text: text, offset: start, length: j - start, lower: text.lowercased().replacingOccurrences(of: "’", with: "'")))
            i = j
        }
        return out
    }

    struct Sentence {
        var offset: Int
        var end: Int
        var words: Int
    }

    /// Words that end in a full stop without ending the sentence.
    static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "st", "prof", "sr", "jr", "vs", "cf", "e.g", "i.e", "eg", "ie",
                                             "approx", "fig", "vol", "pp", "mt", "rev", "lt", "col", "capt", "sgt", "inc", "ltd",
                                             "dept", "a.m", "p.m"]
    /// Words that can end a sentence or run on: "etc. and" runs on, "etc. Then" doesn't.
    static let runOnAbbreviations: Set<String> = ["etc", "al", "viz"]
    static let closers: Set<Character> = ["\"", "”", "’", "'", ")", "]"]
    static let enders: Set<Character> = [".", "!", "?", "…"]

    /// The letters (and inner dots) just before `index`, lower-cased: "e.g" before "e.g.".
    static func wordBefore(_ chars: [Character], _ index: Int) -> String {
        var j = index
        while j > 0, chars[j - 1].isLetter || (chars[j - 1] == "." && j > 1 && chars[j - 2].isLetter) { j -= 1 }
        return String(chars[j..<index]).lowercased()
    }

    /// Sentences split at line breaks and at a full stop, question or exclamation mark followed by
    /// a space, except after an abbreviation or an initial, after "etc.", "et al." or an initialism
    /// ("U.S.") that runs on in lower case, after an ellipsis that does, and before a lower-case
    /// dialogue tag ("Where?" she asked).
    static func sentences(_ chars: [Character], tokens: [Token]) -> [Sentence] {
        var bounds: [(Int, Int)] = []
        var start = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\n" {
                bounds.append((start, i))
                start = i + 1
                i += 1
                continue
            }
            guard enders.contains(c) else {
                i += 1
                continue
            }
            var j = i + 1
            while j < chars.count, enders.contains(chars[j]) { j += 1 }
            var quoted = false
            while j < chars.count, closers.contains(chars[j]) {
                quoted = true
                j += 1
            }
            guard j < chars.count else { break }
            guard chars[j] == " " || chars[j] == "\t" else {
                i = j
                continue
            }
            var k = j
            while k < chars.count, chars[k] == " " || chars[k] == "\t" { k += 1 }
            let nextLower = k < chars.count && chars[k].isLowercase
            let ellipsis = c == "…" || j - i >= 2 && chars[i..<j].allSatisfy { $0 == "." }
            let word = wordBefore(chars, i)
            let initial = word.count == 1 && i > 0 && chars[i - 1].isUppercase
            let runsOn = c == "." && nextLower && (runOnAbbreviations.contains(word) || word.contains("."))
            let breaks = !(c == "." && (abbreviations.contains(word) || initial)) && !(nextLower && (ellipsis || quoted)) && !runsOn
            if breaks {
                bounds.append((start, j))
                start = k
            }
            i = k
        }
        bounds.append((start, chars.count))
        return bounds.compactMap { s, e in
            guard e > s else { return nil }
            let words = tokens.filter { $0.offset >= s && $0.offset < e }.count
            return words == 0 ? nil : Sentence(offset: s, end: e, words: words)
        }
    }

    /// The moving-average type–token ratio: the share of different words in every 50-word window.
    static func vocabulary(_ tokens: [Token]) -> Double? {
        let words = tokens.filter(\.hasLetters).map(\.lower)
        let window = vocabularyWindow
        guard words.count >= window else { return nil }
        var counts: [String: Int] = [:]
        for word in words[0..<window] { counts[word, default: 0] += 1 }
        var total = Double(counts.count)
        var windows = 1.0
        for i in window..<words.count {
            let leaving = words[i - window]
            counts[leaving]! -= 1
            if counts[leaving] == 0 { counts[leaving] = nil }
            counts[words[i], default: 0] += 1
            total += Double(counts.count)
            windows += 1
        }
        return total / windows / Double(window)
    }

    // MARK: Slips

    /// Words that are fine twice running: "had had", "that that".
    static let doubles: Set<String> = ["had", "that", "is", "do", "very", "so", "no", "bye", "ha", "ho", "now", "really", "far", "again"]
    /// Joined words that should be two.
    static let joined: [String: String] = ["alot": "a lot", "noone": "no one", "eachother": "each other", "infact": "in fact",
                                           "aswell": "as well", "alittle": "a little", "atleast": "at least", "inspite": "in spite",
                                           "thankyou": "thank you", "everytime": "every time"]
    /// Words that start with a vowel letter and a consonant sound: "a one-off", "a European".
    static let consonantSounds = ["one", "once", "eu", "ewe"]
    static let modals: Set<String> = ["could", "would", "should", "must", "might"]
    static let comparatives: Set<String> = ["more", "less", "fewer", "greater", "better", "worse", "larger", "smaller", "higher",
                                            "lower", "bigger", "older", "younger", "longer", "shorter"]

    static func slips(_ chars: [Character], tokens: [Token], misspelled: [String]) -> [WritingSlip] {
        var out: [WritingSlip] = []
        func slip(_ kind: WritingSlip.Kind, _ offset: Int, _ end: Int, _ note: String) {
            out.append(WritingSlip(kind: kind, offset: offset, length: end - offset, text: String(chars[offset..<end]), note: note))
        }
        func onlySpaces(_ from: Int, _ to: Int) -> Bool { from < to && chars[from..<to].allSatisfy(\.isWhitespace) }

        for (index, token) in tokens.enumerated() {
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            let previous = index > 0 ? tokens[index - 1] : nil
            let adjacent = next.map { onlySpaces(token.end, $0.offset) } ?? false

            if let next, adjacent, token.hasLetters, token.lower == next.lower, !doubles.contains(token.lower) {
                slip(.mechanics, token.offset, next.end, "The same word twice")
            }
            if token.text == "i" || token.text.hasPrefix("i'") || token.text.hasPrefix("i’") {
                let dotted = (token.end < chars.count && chars[token.end] == ".") || (token.offset > 0 && chars[token.offset - 1] == ".")
                if !dotted { slip(.mechanics, token.offset, token.end, "“I” is always a capital") }
            }
            if let next, adjacent, !next.acronym, let first = next.lower.first {
                if token.lower == "a", "aeio".contains(first), !consonantSounds.contains(where: { next.lower.hasPrefix($0) }) {
                    slip(.mechanics, token.offset, next.end, "“an” before a vowel sound")
                }
                let singleLetter = next.text.prefix { !isJoiner($0) }.count == 1
                if token.lower == "an", first.isLetter, !"aeiouh".contains(first), !singleLetter, !next.capitalised {
                    slip(.mechanics, token.offset, next.end, "“a” before a consonant sound")
                }
            }
            if let next, adjacent, modals.contains(token.lower), next.lower == "of" {
                let noun = token.lower == "might" && ["the", "his", "her", "its", "their", "all", "with", "our", "your"].contains(previous?.lower ?? "")
                if !noun { slip(.mechanics, token.offset, next.end, "“\(token.lower) have”, not “\(token.lower) of”") }
            }
            if let next, adjacent, next.lower == "then" {
                let after = index + 2 < tokens.count ? tokens[index + 2] : nil
                let comparing = after.map { $0.text.first?.isNumber == true || $0.lower == "ever" || $0.lower == "before" } ?? false
                if token.lower == "rather" || token.lower == "other" || (comparatives.contains(token.lower) && comparing) {
                    slip(.mechanics, token.offset, next.end, "“than” for a comparison")
                }
            }
            if let two = joined[token.lower] {
                slip(.mechanics, token.offset, token.end, "“\(two)” is two words")
            }
        }

        // Punctuation: a space before it, none after it, or doubled.
        for i in chars.indices {
            let c = chars[i]
            if ",;:.?!".contains(c), i >= 2, chars[i - 1] == " ", chars[i - 2].isLetter || chars[i - 2].isNumber,
               i + 1 == chars.count || chars[i + 1].isWhitespace || (c != "." && chars[i + 1].isLetter) {
                slip(.mechanics, i - 1, i + 1, "No space before “\(c)”")
            }
            if (c == "," || c == ";"), i > 0, i + 1 < chars.count, chars[i - 1].isLetter, chars[i + 1].isLetter {
                slip(.mechanics, i, i + 1, "A space after “\(c)”")
            }
            if ".?!".contains(c), i > 0, i + 2 < chars.count, chars[i - 1].isLowercase, chars[i + 1].isUppercase, chars[i + 2].isLowercase {
                // Not a web address or a file name: the word before has no other dot.
                var j = i - 1
                while j > 0, !chars[j - 1].isWhitespace { j -= 1 }
                let word = chars[j..<i]
                if !word.contains(".") && !word.contains("@") { slip(.mechanics, i, i + 1, "A space after “\(c)”") }
            }
            if i + 1 < chars.count, c == chars[i + 1], ",;:".contains(c) {
                slip(.mechanics, i, i + 2, "One “\(c)” is enough")
            }
            if c == ".", i + 1 < chars.count, chars[i + 1] == ".", i == 0 || chars[i - 1] != ".", i + 2 == chars.count || chars[i + 2] != "." {
                slip(.mechanics, i, i + 2, "One full stop, or three for a pause")
            }
        }

        // Sentences that start in lower case (not "iPhone", not a bulleted line).
        for sentence in sentences(chars, tokens: tokens) {
            guard let first = tokens.first(where: { $0.offset >= sentence.offset && $0.offset < sentence.end }),
                  first.text.first?.isLowercase == true, !first.mixedCase, first.text != "i" else { continue }
            var lineStart = sentence.offset
            while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
            let line = String(chars[lineStart..<first.offset]).trimmingCharacters(in: .whitespaces)
            if let marker = line.first, "-•*–—".contains(marker) || marker.isNumber { continue }
            slip(.mechanics, first.offset, first.end, "Start the sentence with a capital")
        }

        // Spelling: every place a flagged word appears. Capitalised words are left alone, so a name
        // never counts against anyone.
        let flagged = Set(misspelled)
        for token in tokens where flagged.contains(token.text) && !token.capitalised {
            slip(.spelling, token.offset, token.end, "Check the spelling")
        }

        // One slip per place: a rule's note is more use than "check the spelling".
        var kept: [WritingSlip] = []
        for slip in out.sorted(by: { ($0.offset, $0.kind == .spelling ? 1 : 0) < ($1.offset, $1.kind == .spelling ? 1 : 0) }) {
            if let last = kept.last, slip.offset < last.offset + last.length { continue }
            kept.append(slip)
        }
        return kept
    }
}
