import Foundation
import SystemCore

/// What a Japanese session teaches next, and how much. New words come only as fast as recall
/// holds up: difficulty rises when performance shows mastery, never because a week went by.
public enum JapanesePlan {
    /// New words in a 25-minute session with recall on target: two Japanese days a week makes
    /// about 1,500 words a year.
    public static let baseNewWords = 15
    public static let maxNewWords = 25
    public static let newKanaPerSession = 12
    /// Recall on reviews over the last fortnight, against the scheduler's 90% aim.
    public static let retentionWindowDays = 14
    /// Reviews due in the coming week above which new words wait: about half an hour of them,
    /// more than the week's warm-ups hold.
    public static let reviewLoadLimit = 200

    public enum NewItem: Hashable, Sendable {
        case kana(Kana)
        /// Taught first, then asked.
        case teach(Word)
        /// Probably known (below the placement level): asked first, taught only if missed.
        case probe(Word)

        public var key: CardKey {
            switch self {
            case .kana(let kana): kana.key
            case .teach(let word), .probe(let word): word.key
            }
        }
    }

    /// Words up to here are checked rather than taught: the latest vocabulary estimate.
    public static func frontier(_ tests: [TestResult]) -> Int {
        Int(tests.filter { $0.test == .vocabulary }.max { $0.date < $1.date }?.score ?? 0)
    }

    /// The share of Japanese reviews recalled in the window. Nil with too few to say.
    public static func retention(_ sessions: [StudySession], today: Day) -> Double? {
        let since = today.adding(days: -retentionWindowDays)
        let reviews = sessions.filter { $0.day >= since }.flatMap(\.attempts).filter { $0.kind == .review && $0.domain == .japanese }
        guard reviews.count >= 20 else { return nil }
        return Double(reviews.filter(\.correct).count) / Double(reviews.count)
    }

    /// New words for a session of `minutes`: fewer when recall slips below the aim or reviews
    /// pile up, more when recall is comfortably above it.
    public static func newWords(retention: Double?, dueThisWeek: Int, minutes: Int, reviewWeek: Bool) -> (count: Int, reason: String?) {
        guard !reviewWeek else { return (0, "Review week: nothing new.") }
        var count = Double(baseNewWords) * Double(minutes) / 25
        var reason: String?
        if let retention {
            if retention < 0.8 {
                count *= 0.4
                reason = "Recall is \(Int((retention * 100).rounded()))% on reviews, under the 90% aim, so fewer new words until it recovers."
            } else if retention < 0.86 {
                count *= 0.7
                reason = "Recall is a little under the aim, so new words slow down slightly."
            } else if retention > 0.93 {
                count *= 1.3
                reason = "Recall is strong, so a few more new words."
            }
        }
        if dueThisWeek > reviewLoadLimit {
            count = min(count, 4)
            reason = "\(dueThisWeek) reviews are due this week, so new words wait while they're cleared."
        }
        return (min(maxNewWords, max(0, Int(count.rounded()))), reason)
    }

    public static func kanaIntroduced(_ script: Script, cards: Set<CardKey>) -> Bool {
        KanaTable.kana(script).filter { $0.group < 2 }.allSatisfy { cards.contains($0.key) }
    }

    /// The next new items, in order. Without kana, hiragana comes first and words wait; katakana
    /// then runs alongside words, and loanwords wait until it's in.
    public static func next(count: Int, cards: Set<CardKey>, deck: JapaneseDeck, readsKana: Bool?, frontier: Int) -> [NewItem] {
        guard count > 0 else { return [] }
        var kana: [NewItem] = []
        var wordLimit = count
        if readsKana == false {
            if !kanaIntroduced(.hiragana, cards: cards) {
                return KanaTable.kana(.hiragana).filter { !cards.contains($0.key) }.prefix(newKanaPerSession).map(NewItem.kana)
            }
            // The rest of hiragana (the combinations), then katakana, half as fast, beside words.
            let remaining = KanaTable.all.filter { !cards.contains($0.key) }
            kana = remaining.prefix(newKanaPerSession / 2).map(NewItem.kana)
            wordLimit = max(2, count - kana.count / 2)
        }
        let katakanaReady = readsKana != false || kanaIntroduced(.katakana, cards: cards)
        var words: [NewItem] = []
        for word in deck.words {
            if words.count >= wordLimit { break }
            if cards.contains(word.key) || (!katakanaReady && word.hasKatakana) { continue }
            words.append(word.rank <= frontier ? .probe(word) : .teach(word))
        }
        return kana + words
    }
}
