import Foundation
import SystemCore

/// Languages: one module for every pack. Placement is a vocabulary test from common words to rare;
/// sessions teach new words (and, for Japanese without kana, kana first), then sentence listening.
enum LanguageModule: SubjectModule {
    static func needsPlacement(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> Bool {
        guard let language = domain.language, catalogs.deck(language) != nil else { return false }
        // Japanese without kana starts with hiragana; the vocabulary test waits.
        if language == .japanese && state.settings.readsKana == false { return false }
        return state.latest(.vocabulary, in: domain) == nil
    }

    static func placementParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        [PlanPart(kind: .placement, domain: domain, minutes: 4, title: "\(domain.label) level",
                  detail: "Words from common to rare until they're mostly new")]
    }

    static func mainParts(_ domain: Domain, minutes: Int, kind: StudyKind, state: StudyState, catalogs: Catalogs,
                          notes: inout [String]) -> [PlanPart] {
        if kind == .review {
            let practice = max(2, minutes / 2)
            return [PlanPart(kind: .practice, domain: domain, minutes: practice, title: "\(domain.label) practice", detail: "Reviews ahead of schedule"),
                    PlanPart(kind: .sentences, domain: domain, minutes: minutes - practice, title: "Listening",
                             detail: "Sentences made of words you know")]
        }
        let learn = learnPart(domain, minutes: Int((Double(minutes) * 0.65).rounded()), session: state.settings.schedule.minutes, state: state,
                              catalogs: catalogs, notes: &notes)
        let known = state.cards.values.filter { $0.domain == domain && $0.memory != nil && !$0.key.isKana }.count
        if let language = domain.language, known < 15 && LanguagePlan.frontier(state.tests, language) < 100 {
            var all = learn
            all.minutes = minutes
            return [all]
        }
        return [learn, PlanPart(kind: .sentences, domain: domain, minutes: minutes - learn.minutes, title: "Listening",
                                detail: "Sentences made of words you know")]
    }

    /// New material for a part of `minutes`, paced for a session of `session` minutes.
    static func learnPart(_ domain: Domain, minutes: Int, session: Int, state: StudyState, catalogs: Catalogs,
                          notes: inout [String]) -> PlanPart {
        guard let language = domain.language else { return PlanPart(kind: .learn, domain: domain, minutes: minutes, title: "", detail: "") }
        let retention = LanguagePlan.retention(state.sessions, today: state.today, language)
        let dueWeek = state.cards.values.filter { $0.domain == domain && ($0.memory.map { Day($0.due) <= state.today.adding(days: 6) } ?? false) }.count
        let pace = LanguagePlan.newWords(retention: retention, dueThisWeek: dueWeek, minutes: session, reviewWeek: false)
        if let reason = pace.reason { notes.append("\(domain.label): \(reason)") }
        let deck = catalogs.deck(language)
        let items = deck.map { LanguagePlan.next(count: pace.count, cards: Set(state.cards.keys), deck: $0, readsKana: state.settings.readsKana,
                                                 frontier: LanguagePlan.frontier(state.tests, language)) } ?? []
        let kana = items.filter { if case .kana = $0 { true } else { false } }.count
        let words = items.count - kana
        var detail = [String]()
        if kana > 0 { detail.append("\(kana) new kana") }
        if words > 0 { detail.append("\(words) new words") }
        if deck == nil { detail = ["The \(domain.label) catalog isn't installed"] }
        return PlanPart(kind: .learn, domain: domain, minutes: minutes, title: "New \(domain.label)", detail: detail.joined(separator: ", "),
                        items: pace.count)
    }

    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        guard let deck = catalogs.deck(for: domain) else { return [] }
        var parts = [PlanPart(kind: .test(.vocabulary), domain: domain, minutes: 4, title: "\(domain.label) vocabulary",
                              detail: "Five words from each frequency band, with “Don't know”")]
        if deck.sentences(levels: 1...500, limit: 4).count >= 4 {
            parts.append(PlanPart(kind: .test(.listening), domain: domain, minutes: 3, title: "\(domain.label) listening",
                                  detail: "Ten sentences by ear, easy to hard"))
        }
        return parts
    }

    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> (any PartRunner)? {
        guard let language = part.domain?.language, let deck = catalogs.deck(language) else { return nil }
        let frontier = LanguagePlan.frontier(state.tests, language)
        switch part.kind {
        case .learn:
            let items = LanguagePlan.next(count: part.items, cards: Set(state.cards.keys), deck: deck, readsKana: state.settings.readsKana,
                                          frontier: frontier)
            return LearnRunner(language: language, fresh: items)
        case .sentences:
            return SentencesRunner(language: language, pool: sentencePool(deck, state: state, frontier: frontier))
        case .placement:
            return VocabularyRunner(language: language, queue: LanguageTests.vocabulary(band: 0, deck: deck, seed: "placement"), placement: true)
        case .test(.vocabulary):
            return VocabularyRunner(language: language, queue: LanguageTests.vocabulary(band: 0, deck: deck, seed: state.today.iso),
                                    placement: false)
        case .test(.listening):
            return QuestionListRunner(queue: LanguageTests.listening(deck: deck, seed: state.today.iso, offset: state.today.ordinal)) { attempts, run in
                let tested = attempts.filter { $0.test == .listening }
                guard tested.count >= 4 else { return }
                run.newTests.append(LanguageTests.listeningResult(tested, date: run.now, language: language))
            }
        default:
            return nil
        }
    }

    static func question(for key: CardKey, kind: AttemptKind, run: StudyRun) -> Question? {
        let reps = run.cards[key]?.memory?.reps ?? 0
        if key.isKana, let kana = KanaTable.byKana[key.item] {
            let introduced = KanaTable.all.filter { run.cards[$0.key]?.memory != nil }
            return LanguageQuiz.question(kana, reps: reps + (kind == .learn ? 1 : 0), kind: kind, introduced: introduced, seed: run.seed)
        }
        guard let language = key.language, let deck = run.catalogs.deck(language), let id = key.wordID, let word = deck.word(id) else { return nil }
        let ask = kind == .learn ? .meaning : LanguageQuiz.ask(for: word, reps: reps)
        return LanguageQuiz.question(word, ask: ask, kind: kind, deck: deck, seed: run.seed)
    }

    static func usable(_ key: CardKey, catalogs: Catalogs) -> Bool {
        if key.isKana { return KanaTable.byKana[key.item] != nil }
        guard let language = key.language, let id = key.wordID else { return false }
        return catalogs.deck(language)?.word(id) != nil
    }

    static func reviewSeconds(_ card: MemoryCard) -> Double { card.key.isKana ? 5 : 8 }

    /// Vocabulary on a log scale, with listening when there is one. Self-rated episodes and
    /// conversations never count.
    static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)] {
        var listening: Double?
        var out: [(Day, Double)] = []
        for test in state.tests where test.domain == domain && (test.test == .vocabulary || test.test == .listening) {
            if test.test == .listening { listening = test.score * 100 }
            guard let vocabulary = state.tests.last(where: { $0.test == .vocabulary && $0.domain == domain && $0.date <= test.date }) else { continue }
            let words = LanguageTests.vocabularyScore(vocabulary.score)
            out.append((test.day, listening.map { 0.6 * words + 0.4 * $0 } ?? words))
        }
        return out
    }

    static func label(_ domain: Domain, state: StudyState) -> String {
        "\(domain.label) ~\(Int(state.latest(.vocabulary, in: domain)?.score ?? 0).formatted()) words"
    }

    /// Sentences of known words, with at most one new one.
    static func sentencePool(_ deck: LanguageDeck, state: StudyState, frontier: Int) -> [Sentence] {
        let known = Set(state.cards.values.filter { $0.memory != nil && $0.key.language == deck.language }.compactMap(\.key.wordID))
        let ranks = known.compactMap { deck.word($0)?.rank }
        let top = max(frontier, ranks.max() ?? 0)
        guard top >= 30 else { return [] }
        return deck.sentences(levels: 1...top, limit: 300, skip: state.today.ordinal).filter { sentence in
            sentence.words.filter { id in !known.contains(id) && (deck.word(id)?.rank ?? .max) > frontier }.count <= 1
        }
    }
}
