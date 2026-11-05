import Foundation
import SystemCore

/// What a Japanese session teaches next, and how much. New words come only as fast as recall
/// holds up: difficulty rises when performance shows mastery, never because a week went by.
public enum LanguagePlan {
    /// New words in a 25-minute session with recall on target: two Japanese days a week makes
    /// about 1,500 words a year.
    public static let baseNewWords = 15
    public static let maxNewWords = 25
    /// Kana a session beside the words while the first hiragana (the basic rows and voiced
    /// sounds) come in, then for the combinations and katakana.
    public static let newKanaPerSession = 8
    public static let laterKanaPerSession = 6
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

    /// Words up to here are checked rather than taught: the latest vocabulary estimate in the language.
    public static func frontier(_ tests: [TestResult], _ language: Language = .japanese) -> Int {
        Int(tests.filter { $0.test == .vocabulary && $0.domain == language.domain }.max { $0.date < $1.date }?.score ?? 0)
    }

    /// The share of a language's reviews recalled in the window. Nil with too few to say.
    public static func retention(_ sessions: [StudySession], today: Day, dayStart: Int, _ language: Language = .japanese) -> Double? {
        let since = today.adding(days: -retentionWindowDays)
        let reviews = sessions.filter { $0.day(startingAt: dayStart) >= since }.flatMap(\.attempts)
            .filter { $0.kind == .review && $0.domain == language.domain }
        guard reviews.count >= 20 else { return nil }
        return Double(reviews.filter(\.correct).count) / Double(reviews.count)
    }

    /// New words for a session of `minutes`: fewer when recall slips below the aim or reviews
    /// pile up, more when recall is comfortably above it.
    public static func newWords(
        retention: Double?, dueThisWeek: Int, minutes: Int, reviewWeek: Bool, reviewLimit: Int = reviewLoadLimit
    ) -> (count: Int, reason: String?) {
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
        if dueThisWeek > reviewLimit {
            count = min(count, 4)
            reason = "\(dueThisWeek) reviews are due this week, so new words wait while they're cleared."
        }
        return (min(maxNewWords, max(0, Int(count.rounded()))), reason)
    }

    /// Reviews a week above which a course's new words wait: what its warm-ups can hold. Four blocks
    /// a week teach twice the words the old sessions did, and hold more reviews to match; a flat limit
    /// would stall them every few weeks.
    public static func reviewLimit(_ domain: Domain, state: StudyState) -> Int {
        guard let week = state.weekSettings else { return reviewLoadLimit }
        let warmUp = Double(state.settings.schedule.minutes) * 60 * SessionPlanner.warmUpShare
        return Int(Double(max(1, week.blocks(domain))) * warmUp / LanguageModule.wordReviewSeconds)
    }

    /// A course's reviews due within the coming week, today included.
    public static func dueThisWeek(_ domain: Domain, state: StudyState) -> Int {
        let end = state.today.adding(days: 6)
        return state.cards.values.filter { $0.domain == domain && $0.isDue(on: end, dayStart: state.dayStart) }.count
    }

    /// New words a session for a language course, from its recall and the week's reviews: what a
    /// session teaches and what the Plan tab says it will. `minutes` is the session's length, the
    /// schedule's unless said.
    public static func pace(_ domain: Domain, state: StudyState, reviewWeek: Bool, minutes: Int? = nil)
        -> (count: Int, reason: String?, dueThisWeek: Int)
    {
        let retention = domain.language.flatMap { Self.retention(state.sessions, today: state.today, dayStart: state.dayStart, $0) }
        let due = dueThisWeek(domain, state: state)
        let words = newWords(
            retention: retention, dueThisWeek: due, minutes: minutes ?? state.settings.schedule.minutes, reviewWeek: reviewWeek,
            reviewLimit: reviewLimit(domain, state: state))
        return (words.count, words.reason, due)
    }

    public static func kanaIntroduced(_ script: Script, cards: Set<CardKey>) -> Bool {
        kanaIntroduced(script) { cards.contains($0) }
    }

    static func kanaIntroduced(_ script: Script, has: (CardKey) -> Bool) -> Bool {
        KanaTable.kana(script).filter { $0.group < 2 }.allSatisfy { has($0.key) }
    }

    /// Whether a word's reading can be asked: always, unless the person is still on the first
    /// hiragana, when kana choices would be guesses. Meaning and listening carry it until then.
    static func asksReading(_ settings: MindSettings, has: (CardKey) -> Bool) -> Bool {
        settings.readsKana != false || kanaIntroduced(.hiragana, has: has)
    }

    /// The next new items, in order. Words come from the first session: for Japanese without
    /// kana, kana come beside them (hiragana, then katakana), and the words carry romaji under
    /// each kana not yet mastered. Loanwords wait until katakana is in.
    public static func next(count: Int, cards: Set<CardKey>, deck: LanguageDeck, readsKana: Bool?, frontier: Int) -> [NewItem] {
        guard count > 0 else { return [] }
        var kana: [NewItem] = []
        var wordLimit = count
        let readsKana: Bool? = deck.language == .japanese ? readsKana : true
        if readsKana == false {
            let pace = kanaIntroduced(.hiragana, cards: cards) ? laterKanaPerSession : newKanaPerSession
            kana = KanaTable.all.filter { !cards.contains($0.key) }.prefix(min(pace, count)).map(NewItem.kana)
            wordLimit = max(2, count - kana.count / 2)
        }
        let katakanaReady = readsKana != false || kanaIntroduced(.katakana, cards: cards)
        var words: [NewItem] = []
        for word in deck.words {
            if words.count >= wordLimit { break }
            if cards.contains(word.key) || (!katakanaReady && word.hasKatakana) { continue }
            words.append(word.rank <= frontier ? .probe(word) : .teach(word))
        }
        // Taken in turns, so a part cut short still has some of each.
        var out: [NewItem] = []
        for index in 0..<max(kana.count, words.count) {
            if index < kana.count { out.append(kana[index]) }
            if index < words.count { out.append(words[index]) }
        }
        return out
    }
}
