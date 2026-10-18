import Foundation

/// How many words someone knows, from a sample of each frequency band; and how much of a spoken
/// sentence they follow, at several levels, in any language. These measure: the words studied in
/// the app are just part of the bands, so the number only rises by knowing more of the language.
public enum LanguageTests {
    /// Frequency bands, by rank: the first 250 words, the next 250, then doubling.
    public static let bands: [ClosedRange<Int>] = [1...250, 251...500, 501...1000, 1001...2000, 2001...4000, 4001...8000,
                                                   8001...14000, 14001...20000]
    public static let wordsPerBand = 5
    /// Placement stops once a band is mostly unknown.
    public static let stopBelow = 0.35

    /// Sentence levels for the listening test, two sentences each.
    public static let listeningLevels: [ClosedRange<Int>] = [1...500, 501...1000, 1001...2000, 2001...4000, 4001...8000]

    /// Vocabulary questions for one band: what does it mean, with "Don't know".
    public static func vocabulary(band: Int, deck: LanguageDeck, seed: String) -> [Question] {
        guard bands.indices.contains(band) else { return [] }
        let range = bands[band]
        var rng = SeededRandom(seed, "band", "\(band)")
        let pool = deck.words.filter { range.contains($0.rank) }
        return pool.shuffled(using: &rng).prefix(wordsPerBand).map { word in
            var question = LanguageQuiz.question(word, ask: .meaning, kind: .test, deck: deck, seed: seed)
            question.allowsDontKnow = true
            question.test = .vocabulary
            question.band = band
            question.reveal = nil
            return question
        }
    }

    public static func bandsAvailable(in deck: LanguageDeck) -> Int {
        let maxRank = deck.words.last?.rank ?? 0
        return bands.filter { $0.lowerBound <= maxRank }.count
    }

    /// Whether placement should go on to the next band after these answers.
    public static func continuePlacement(after band: Int, attempts: [Attempt], deck: LanguageDeck) -> Bool {
        guard band + 1 < bandsAvailable(in: deck) else { return false }
        return known(attempts.filter { $0.band == band }) >= stopBelow
    }

    /// The share of a band known, corrected for guessing on four choices: a wrong answer suggests
    /// about one lucky right one elsewhere. "Don't know" isn't a guess.
    public static func known(_ attempts: [Attempt]) -> Double {
        guard !attempts.isEmpty else { return 0 }
        let right = Double(attempts.filter(\.correct).count)
        let wrong = Double(attempts.filter { !$0.correct && !$0.skipped }.count)
        return min(1, max(0, (right - wrong / 3) / Double(attempts.count)))
    }

    public struct VocabularyEstimate: Hashable, Sendable {
        public var words: Int
        public var low: Int
        public var high: Int
        /// The share known in each band tested.
        public var bands: [Int: Double]
    }

    /// Words known: each band's size times the share known in it. Bands above the last one tested
    /// count as nothing. The range is about one standard error each way.
    public static func estimate(_ attempts: [Attempt]) -> VocabularyEstimate {
        let tested = attempts.filter { $0.test == .vocabulary && $0.band != nil }
        var total = 0.0, variance = 0.0
        var shares: [Int: Double] = [:]
        for (index, range) in bands.enumerated() {
            let inBand = tested.filter { $0.band == index }
            guard !inBand.isEmpty else { continue }
            let p = known(inBand)
            let size = Double(range.count)
            shares[index] = p
            total += size * p
            variance += size * size * max(0.04, p * (1 - p)) / Double(inBand.count)
        }
        let se = variance.squareRoot()
        return VocabularyEstimate(words: Int(total.rounded()), low: Int(max(0, total - se).rounded()), high: Int((total + se).rounded()),
                                  bands: shares)
    }

    public static func result(_ attempts: [Attempt], date: Date, placement: Bool, language: Language) -> TestResult {
        let estimate = estimate(attempts)
        var detail: [String: Double] = ["low": Double(estimate.low), "high": Double(estimate.high)]
        for (band, share) in estimate.bands { detail["band\(band)"] = share }
        return TestResult(test: .vocabulary, date: date, score: Double(estimate.words), detail: detail, placement: placement,
                          language: language)
    }

    /// 0–100 for the hub, on a log scale: 1,000 words is about 57, 10,000 is 100.
    public static func vocabularyScore(_ words: Double) -> Double {
        min(100, 100 * log(1 + words / 50) / log(1 + 10_000 / 50))
    }

    /// A rough guide in familiar terms: the JLPT for Japanese, CEFR for the rest. Neither
    /// publishes word lists, so it's only "roughly".
    public static func level(words: Double, language: Language = .japanese) -> String {
        if language != .japanese {
            switch words {
            case ..<300: return "Getting started"
            case ..<600: return "Roughly A1 vocabulary"
            case ..<1200: return "Roughly A2 vocabulary"
            case ..<2500: return "Roughly B1 vocabulary"
            case ..<5000: return "Roughly B2 vocabulary"
            default: return "Roughly C1 vocabulary"
            }
        }
        return switch words {
        case ..<300: "Getting started"
        case ..<800: "Roughly N5 vocabulary in reach"
        case ..<1500: "Roughly N5 vocabulary"
        case ..<3700: "Roughly N4 vocabulary"
        case ..<6000: "Roughly N3 vocabulary"
        case ..<10000: "Roughly N2 vocabulary"
        default: "Roughly N1 vocabulary"
        }
    }

    // MARK: Listening

    public static func listening(deck: LanguageDeck, seed: String, offset: Int) -> [Question] {
        var questions: [Question] = []
        for (band, levels) in listeningLevels.enumerated() {
            let pool = deck.sentences(levels: levels, limit: 24, skip: offset)
            guard pool.count >= 4 else { continue }
            for sentence in pool.prefix(2) {
                var question = LanguageQuiz.sentence(sentence, language: deck.language, kind: .test, others: pool, seed: seed,
                                                     key: .practice(deck.language, "listening"))
                question.test = .listening
                question.band = band
                questions.append(question)
            }
        }
        return questions
    }

    /// The share understood, weighting harder sentences more, corrected for guessing.
    public static func listeningResult(_ attempts: [Attempt], date: Date, language: Language) -> TestResult {
        skillResult(.listening, attempts, date: date, language: language, choices: true)
    }

    // MARK: The other skills

    /// Reading: the listening test's levels from the page, with no sound and no scaffolds.
    public static func reading(deck: LanguageDeck, seed: String, offset: Int) -> [Question] {
        var questions: [Question] = []
        for (band, levels) in listeningLevels.enumerated() {
            // A sample of its own, so it mostly asks other sentences than the listening test that day.
            let pool = deck.sentences(levels: levels, limit: 24, skip: offset + 11)
            guard pool.count >= 4 else { continue }
            for sentence in pool.suffix(2) {
                var question = LanguageQuiz.sentence(sentence, language: deck.language, kind: .test, others: pool, seed: seed,
                                                     key: .practice(deck.language, "reading"))
                question.prompt = .foreign(sentence.text, deck.language)
                question.instruction = "What does it say?"
                question.expectedSeconds = 8 + Double(sentence.text.count) * (deck.language.pack.script == .kanaKanji ? 0.4 : 0.15)
                question.test = .languageReading
                question.band = band
                questions.append(question)
            }
        }
        return questions
    }

    /// Speaking or writing at one level: a word to produce from its meaning, and a sentence of that
    /// level to say back or write down as it's heard.
    public static func production(_ mode: SpeakingTask.Mode, band: Int, deck: LanguageDeck, seed: String, offset: Int) -> [SpeakingTask] {
        guard listeningLevels.indices.contains(band) else { return [] }
        let levels = listeningLevels[band]
        let test: TestKind = mode == .say ? .speaking : .languageWriting
        let language = deck.language
        var rng = SeededRandom(seed, "production", mode.rawValue, "\(band)")
        var out: [SpeakingTask] = []
        if let word = deck.words.filter({ levels.contains($0.rank) && LanguageQuiz.producible($0) }).shuffled(using: &rng).first {
            out.append(LanguageQuiz.produce(word, mode: mode, kind: .test, seed: seed, test: test, band: band))
        }
        let short = deck.sentences(levels: levels, limit: 30, skip: offset + (mode == .say ? 23 : 37))
            .filter { language.pack.script == .kanaKanji ? $0.text.count <= 16 : $0.text.split(separator: " ").count <= 7 }
        if let sentence = short.shuffled(using: &rng).first {
            out.append(LanguageQuiz.produce(sentence, deck: deck, mode: mode, kind: .test, seed: seed, test: test, band: band))
        }
        return out
    }

    /// Whether a production test goes on to the next band: not after one with nothing right.
    public static func continueProduction(after band: Int, attempts: [Attempt]) -> Bool {
        band + 1 < listeningLevels.count && attempts.contains { $0.band == band && $0.correct }
    }

    /// Any banded skill test: each band's share (corrected for guessing where there were choices),
    /// harder bands weighing more in the score, and the reach in words for the skill's level.
    public static func skillResult(_ kind: TestKind, _ attempts: [Attempt], date: Date, language: Language, choices: Bool,
                                   placement: Bool = false) -> TestResult {
        let tested = attempts.filter { $0.test == kind && $0.band != nil }
        var weighted = 0.0, weights = 0.0, words = 0.0
        var detail: [String: Double] = [:]
        for band in Set(tested.compactMap(\.band)).sorted() {
            let inBand = tested.filter { $0.band == band }
            let share = choices ? known(inBand) : Double(inBand.filter(\.correct).count) / Double(inBand.count)
            let weight = Double(band + 1)
            weighted += share * weight
            weights += weight
            words += share * Double(listeningLevels[band].count)
            detail["band\(band)"] = share
        }
        // Bands not reached weigh in as nothing, so stopping early can't flatter the score.
        for band in listeningLevels.indices where detail["band\(band)"] == nil { weights += Double(band + 1) }
        detail["words"] = words.rounded()
        detail["asked"] = Double(tested.count)
        return TestResult(test: kind, date: date, score: weights > 0 ? weighted / weights : 0, detail: detail, placement: placement,
                          language: language)
    }
}
