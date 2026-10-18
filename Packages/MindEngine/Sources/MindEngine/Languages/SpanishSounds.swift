import Foundation

/// Spanish is said the way it's spelled, so a word's syllables and stress follow from its letters:
/// an accent marks the stress; otherwise a word ending in a vowel, n or s stresses the second to
/// last syllable, and any other word the last. That's the pronunciation scaffold: PE·rro, ha·BLAR,
/// co·ra·ZÓN.
public enum SpanishSounds {
    static let articles: Set<String> = ["el", "la", "los", "las", "el/la", "un", "una"]
    /// Consonant pairs that start a syllable together: ha-blar, ma-dre.
    static let clusters: Set<String> = ["bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr", "kl", "kr", "pl", "pr", "tr"]

    /// The guide for a word or phrase: each word of two syllables or more split up with its stress
    /// in capitals. Nil when there's nothing to show (every word is one syllable).
    public static func guide(_ text: String) -> String? {
        var any = false
        let parts = text.split(separator: " ").map { part -> String in
            let word = String(part)
            guard !articles.contains(word.lowercased()) else { return word }
            let syllables = syllables(word)
            guard syllables.count > 1 else { return word.lowercased() }
            any = true
            let stress = stressed(syllables)
            return syllables.enumerated().map { $0.offset == stress ? $0.element.uppercased() : $0.element }.joined(separator: "·")
        }
        return any ? parts.joined(separator: " ") : nil
    }

    /// A noun without its article: "el perro" is "perro".
    public static func bare(_ text: String) -> String {
        let parts = text.split(separator: " ")
        guard parts.count > 1, articles.contains(parts[0].lowercased()) else { return text }
        return parts.dropFirst().joined(separator: " ")
    }

    private enum Kind { case vowel(strong: Bool), consonant }

    /// The word's syllables, lowercased: "guitarra" is gui·ta·rra, "país" pa·ís, "ciudad" ciu·dad.
    public static func syllables(_ word: String) -> [String] {
        let letters = Array(word.lowercased().filter(\.isLetter))
        guard !letters.isEmpty else { return [] }
        // Letters into sounds: ch, ll and rr are one consonant, and so are qu and gu before e or i.
        var units: [(text: String, kind: Kind)] = []
        var i = 0
        while i < letters.count {
            let c = letters[i]
            let next = i + 1 < letters.count ? letters[i + 1] : nil
            let after = i + 2 < letters.count ? letters[i + 2] : nil
            if let next, ["ch", "ll", "rr"].contains(String([c, next])) {
                units.append((String([c, next]), .consonant))
                i += 2
            } else if let next, let after, (c == "q" || c == "g") && next == "u" && "eéií".contains(after) {
                units.append((String([c, next]), .consonant))
                i += 2
            } else if "aeoáéóíú".contains(c) {
                units.append((String(c), .vowel(strong: true)))
                i += 1
            } else if "iuü".contains(c) {
                units.append((String(c), .vowel(strong: false)))
                i += 1
            } else if c == "y", next == nil || !"aeiouáéíóú".contains(next!), i > 0 {
                // A y ending a word or before a consonant is the vowel i: hoy, muy, reyna.
                units.append((String(c), .vowel(strong: false)))
                i += 1
            } else {
                units.append((String(c), .consonant))
                i += 1
            }
        }
        // Vowels into nuclei: two strong vowels (or an accented í or ú) split; anything else is a diphthong.
        var nuclei: [Range<Int>] = []
        var j = 0
        while j < units.count {
            guard case .vowel(let strong) = units[j].kind else { j += 1; continue }
            var end = j + 1
            var lastStrong = strong
            while end < units.count, case .vowel(let s) = units[end].kind, !(lastStrong && s) {
                lastStrong = lastStrong || s
                end += 1
            }
            nuclei.append(j..<end)
            j = end
        }
        guard !nuclei.isEmpty else { return [word.lowercased()] }
        // Consonants between nuclei: one goes to the next syllable; of two, a cluster goes on together
        // and anything else splits; of three or four, the last two go on if they're a cluster.
        var starts = [0]
        for (a, b) in zip(nuclei, nuclei.dropFirst()) {
            let between = Array(units[a.upperBound..<b.lowerBound])
            let count = between.count
            let pair = count >= 2 ? between[count - 2].text + between[count - 1].text : ""
            let onset: Int
            switch count {
            case 0: onset = 0
            case 1: onset = 1
            default: onset = clusters.contains(pair) ? 2 : 1
            }
            starts.append(b.lowerBound - onset)
        }
        return zip(starts, starts.dropFirst() + [units.count]).map { start, end in units[start..<end].map(\.text).joined() }
    }

    /// Which syllable carries the stress.
    public static func stressed(_ syllables: [String]) -> Int {
        if let marked = syllables.firstIndex(where: { $0.contains { "áéíóú".contains($0) } }) { return marked }
        guard syllables.count > 1, let last = syllables.last?.last else { return max(0, syllables.count - 1) }
        return "aeiouns".contains(last) ? syllables.count - 2 : syllables.count - 1
    }
}
