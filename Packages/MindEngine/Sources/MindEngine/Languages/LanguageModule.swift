import Foundation
import SystemCore

/// Languages: one module for every pack. Placement is a vocabulary test from common words to rare;
/// sessions teach new words (and, for Japanese without kana, kana first), then a practice block of
/// real use: a dialogue, listening, speaking, reading and writing over what's known. Each of the
/// four skills has its own level from its own test, measured once there's enough to measure and
/// again at every check-in.
enum LanguageModule: SubjectModule {
    /// Skill checks in one regular session, at most.
    static let skillChecksPerSession = 2

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
        guard let language = domain.language else { return [] }
        let practice = practicePart(domain, state: state)
        if kind == .review {
            let reviews = max(2, minutes / 2)
            var rest = practice
            rest.minutes = minutes - reviews
            return [PlanPart(kind: .practice, domain: domain, minutes: reviews, title: "\(domain.label) reviews", detail: "Reviews ahead of schedule"),
                    rest]
        }
        let checks = skillChecks(domain, state: state, catalogs: catalogs)
        if !checks.isEmpty {
            notes.append("\(domain.label): measuring \(ListFormatter.localizedString(byJoining: checks.map { $0.title.lowercased() })) for the first time.")
        }
        let remaining = max(5, minutes - checks.map(\.minutes).reduce(0, +))
        let learn = learnPart(domain, minutes: Int((Double(remaining) * 0.55).rounded()), session: state.settings.schedule.minutes, state: state,
                              catalogs: catalogs, notes: &notes)
        let known = state.cards.values.filter { $0.domain == domain && $0.memory != nil && !$0.key.isKana }.count
        if known < 15 && LanguagePlan.frontier(state.tests, language) < 100 {
            var all = learn
            all.minutes = remaining
            return checks + [all]
        }
        var rest = practice
        rest.minutes = remaining - learn.minutes
        return checks + [learn, rest]
    }

    /// The practice block. Its kind is the sentence practice's, run by `PracticeRunner`.
    static func practicePart(_ domain: Domain, state: StudyState) -> PlanPart {
        let speaking = state.settings.speaking
        return PlanPart(kind: .sentences, domain: domain, minutes: 0, title: speaking ? "Listening and speaking" : "Listening and reading",
                        detail: speaking ? "A dialogue, sentences by ear, saying and writing what you know"
                            : "A dialogue, sentences by ear, reading and writing what you know")
    }

    /// The four skills, each measured once before the first check-in: the first regular sessions
    /// after the vocabulary test fill in whichever haven't been, two at a time.
    static func skillChecks(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        guard let language = domain.language, let deck = catalogs.deck(language),
              LanguagePlan.frontier(state.tests, language) >= LanguageSkills.measuredFrom else { return [] }
        let missing = testable(state, domain: domain).filter { skill in state.latest(LanguageSkills.test(skill), in: domain) == nil }
        return missing.prefix(skillChecksPerSession).compactMap { testPart(domain, $0, deck: deck) }
    }

    static func testPart(_ domain: Domain, _ skill: LanguageSkill, deck: LanguageDeck) -> PlanPart? {
        guard deck.sentences(levels: 1...500, limit: 4).count >= 4 else { return nil }
        let detail = switch skill {
        case .listening: "Ten sentences by ear, easy to hard"
        case .speaking: "Say words and sentences back, easy to hard"
        case .reading: "Ten sentences from the page, easy to hard"
        case .writing: "Write words and what you hear, easy to hard"
        }
        return PlanPart(kind: .test(LanguageSkills.test(skill)), domain: domain, minutes: 3, title: "\(domain.label) \(skill.label.lowercased())",
                        detail: detail)
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

    /// Vocabulary, then the four skills: plain tests, nothing taught.
    static func checkInParts(_ domain: Domain, state: StudyState, catalogs: Catalogs) -> [PlanPart] {
        guard let deck = catalogs.deck(for: domain) else { return [] }
        let vocabulary = PlanPart(kind: .test(.vocabulary), domain: domain, minutes: 4, title: "\(domain.label) vocabulary",
                                  detail: "Five words from each frequency band, with “Don't know”")
        // A learner still on kana has nothing for the skill tests to find.
        guard LanguagePlan.frontier(state.tests, deck.language) >= LanguageSkills.measuredFrom || state.latest(.listening, in: domain) != nil else {
            return [vocabulary]
        }
        return [vocabulary] + testable(state, domain: domain).compactMap { testPart(domain, $0, deck: deck) }
    }

    /// The skills to test now: speaking only while speaking exercises are on (an earlier speaking
    /// result still counts in the score).
    static func testable(_ state: StudyState, domain: Domain) -> [LanguageSkill] {
        LanguageSkills.enabled(state.settings, tests: state.tests, domain: domain).filter { $0 != .speaking || state.settings.speaking }
    }

    static func runner(for part: PlanPart, state: StudyState, catalogs: Catalogs) -> (any PartRunner)? {
        guard let language = part.domain?.language, let deck = catalogs.deck(language) else { return nil }
        let frontier = LanguagePlan.frontier(state.tests, language)
        let seed = state.today.iso
        switch part.kind {
        case .learn:
            let items = LanguagePlan.next(count: part.items, cards: Set(state.cards.keys), deck: deck, readsKana: state.settings.readsKana,
                                          frontier: frontier)
            return LearnRunner(language: language, fresh: items)
        case .sentences:
            return PracticeRunner(language: language, state: state, deck: deck, frontier: frontier)
        case .placement:
            return VocabularyRunner(language: language, queue: LanguageTests.vocabulary(band: 0, deck: deck, seed: "placement"), placement: true)
        case .test(.vocabulary):
            return VocabularyRunner(language: language, queue: LanguageTests.vocabulary(band: 0, deck: deck, seed: seed), placement: false)
        case .test(.listening):
            return QuestionListRunner(queue: LanguageTests.listening(deck: deck, seed: seed, offset: state.today.ordinal)) { attempts, run in
                let tested = attempts.filter { $0.test == .listening }
                guard tested.count >= 4 else { return }
                run.newTests.append(LanguageTests.listeningResult(tested, date: run.now, language: language))
            }
        case .test(.languageReading):
            return QuestionListRunner(queue: LanguageTests.reading(deck: deck, seed: seed, offset: state.today.ordinal)) { attempts, run in
                let tested = attempts.filter { $0.test == .languageReading }
                guard tested.count >= 4 else { return }
                run.newTests.append(LanguageTests.skillResult(.languageReading, tested, date: run.now, language: language, choices: true))
            }
        case .test(.speaking), .test(.languageWriting):
            let mode: SpeakingTask.Mode = part.kind == .test(.speaking) ? .say : .write
            // Speaking off since the plan was made: nothing to ask.
            if mode == .say && !state.settings.speaking { return nil }
            return ProductionTestRunner(language: language, mode: mode, deck: deck, seed: seed, offset: state.today.ordinal)
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
        return LanguageQuiz.question(word, ask: ask, kind: kind, deck: deck, seed: run.seed, help: run.scaffold(word))
    }

    static func usable(_ key: CardKey, catalogs: Catalogs) -> Bool {
        if key.isKana { return KanaTable.byKana[key.item] != nil }
        guard let language = key.language, let id = key.wordID else { return false }
        return catalogs.deck(language)?.word(id) != nil
    }

    static func reviewSeconds(_ card: MemoryCard) -> Double { card.key.isKana ? 5 : 8 }

    /// The four skills, listening and speaking weighted most, on every day a skill was tested once
    /// they've all been measured; before that, vocabulary on its log scale. Self-rated episodes and
    /// conversations never count.
    static func series(_ domain: Domain, state: StudyState) -> [(day: Day, score: Double)] {
        let skills = LanguageSkills.enabled(state.settings, tests: state.tests, domain: domain)
        let tests = state.tests.filter { $0.domain == domain }
        let days = Set(tests.filter { LanguageSkills.skill($0.test) != nil }.map(\.day)).sorted()
        let measured: [(day: Day, score: Double)] = days.compactMap { day in
            LanguageSkills.score(LanguageSkills.levels(domain, tests: tests, on: day), skills: skills).map { (day, $0) }
        }
        if !measured.isEmpty { return measured }
        return tests.filter { $0.test == .vocabulary }.map { ($0.day, LanguageTests.vocabularyScore($0.score)) }
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
