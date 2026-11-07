import Foundation
import SystemCore

/// A language's practice block: a dialogue, then exercises in real use over words and sentences
/// already known: sentences by ear, saying words and saying sentences back, picture matching,
/// reading, writing and, for Japanese, telling written forms apart. Weighted like the skills,
/// listening and speaking most. Practice never schedules anything: the drills are the reviews, and
/// they're support.
struct PracticeRunner: PartRunner {
    enum Exercise: Sendable { case listen, read, picture, sayWord, sayBack, write, dictation, script }

    /// About three listening, three speaking, two reading and two writing in every ten.
    static let cycle: [Exercise] = [.listen, .sayWord, .read, .picture, .sayBack, .write, .listen, .script, .sayWord, .dictation]

    let language: Language
    var words: [Word]
    var sentences: [Sentence]
    var dialogue: Dialogue?
    /// Sessions the dialogue was practised in before: its lines stop being shown after two.
    var dialogueSeen: Int
    var line = 0
    var phrase = 0
    var turn = 0
    var usedWords: Set<Int> = []
    var usedSentences = 0
    /// "Can't speak now", or speaking exercises off: nothing more to say this part.
    var muted: Bool
    var current: SpeakingTask?

    init(language: Language, state: StudyState, deck: LanguageDeck, frontier: Int) {
        self.language = language
        var rng = SeededRandom(state.today.iso, language.rawValue, "practice")
        // The words that most need using: known, least stable first, a little shuffled.
        let known = state.cards.values.filter { $0.memory != nil && $0.key.language == language && !$0.key.isKana }
            .sorted { ($0.memory?.stability ?? 0, $0.key) < ($1.memory?.stability ?? 0, $1.key) }
            .compactMap { $0.key.wordID.flatMap(deck.word) }
        words = Array(known.prefix(60)).shuffled(using: &rng)
        sentences = LanguageModule.sentencePool(deck, state: state, frontier: frontier)
        let level = Dialogues.level(frontier: frontier, known: known.count)
        let practised = Dialogues.practised(language, sessions: state.sessions)
        dialogue = known.count >= 15 ? Dialogues.next(language, level: level, practised: practised) : nil
        dialogueSeen = dialogue.map { practised[$0.id, default: 0] } ?? 0
        muted = !state.settings.speaking
    }

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        current = nil
        if let dialogue, !muted, let step = phraseStep(dialogue, run: run) { return step }
        if let dialogue, line < dialogue.lines.count {
            line += 1
            return dialogueStep(dialogue, line - 1, run: run)
        }
        guard run.partSeconds < run.budget, let deck = run.catalogs.deck(language) else { return nil }
        for _ in Self.cycle.indices {
            let exercise = Self.cycle[turn % Self.cycle.count]
            turn += 1
            if let step = step(exercise, deck: deck, run: run) { return step }
        }
        return nil
    }

    mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool {
        guard let task = current else { return false }
        current = nil
        if case .skip = response {
            if task.mode == .say { muted = true }
            return true
        }
        guard let answer = StudyRun.produced(response) else { return false }
        run.mark(task, answer: answer)
        return true
    }

    // MARK: Exercises

    mutating func step(_ exercise: Exercise, deck: LanguageDeck, run: StudyRun) -> StudyRun.Step? {
        let seed = run.seed
        let context = run.scaffolds(language)
        switch exercise {
        case .listen:
            guard let sentence = nextSentence() else { return nil }
            return .question(
                LanguageQuiz.sentence(
                    sentence, language: language, kind: .learn, others: sentences, seed: seed,
                    key: .practice(language, "sentences")))
        case .read:
            guard let sentence = nextSentence() else { return nil }
            return .question(
                LanguageQuiz.read(
                    sentence, help: Scaffolds.sentence(sentence, deck: deck, context), others: sentences,
                    kind: .learn, seed: seed))
        case .picture:
            guard let word = nextWord(where: { Pictures.symbol(for: $0) != nil }), let symbol = Pictures.symbol(for: word) else { return nil }
            var rng = SeededRandom(seed, "pictures")
            let others = Array(Set(Pictures.symbols.values)).sorted().shuffled(using: &rng)
            return .question(
                LanguageQuiz.picture(
                    word, symbol: symbol, others: others, heard: turn % 2 == 0,
                    help: Scaffolds.word(word, context), kind: .learn, seed: seed))
        case .sayWord, .write:
            if exercise == .sayWord && muted { return nil }
            guard let word = nextWord(where: LanguageQuiz.producible) else { return nil }
            return speak(LanguageQuiz.produce(word, mode: exercise == .sayWord ? .say : .write, kind: .learn, seed: seed))
        case .sayBack, .dictation:
            if exercise == .sayBack && muted { return nil }
            guard let sentence = nextSentence(short: true) else { return nil }
            return speak(LanguageQuiz.produce(sentence, deck: deck, mode: exercise == .sayBack ? .say : .write, kind: .learn, seed: seed))
        case .script:
            // Still on the first hiragana, written forms would be guesses, as readings would.
            guard language.pack.script == .kanaKanji, LanguagePlan.asksReading(run.settings, has: { run.cards[$0] != nil }),
                let word = nextWord(where: { $0.hasKanji || $0.hasKatakana }),
                let question = LanguageQuiz.script(word, deck: deck, kind: .learn, seed: seed)
            else { return nil }
            return .question(question)
        }
    }

    mutating func speak(_ task: SpeakingTask) -> StudyRun.Step {
        current = task
        return .speak(task)
    }

    mutating func nextWord(where wanted: (Word) -> Bool) -> Word? {
        guard let word = words.first(where: { !usedWords.contains($0.id) && wanted($0) }) else { return nil }
        usedWords.insert(word.id)
        return word
    }

    /// The next sentence in the pool; short ones to say back or write down.
    mutating func nextSentence(short: Bool = false) -> Sentence? {
        while usedSentences < sentences.count {
            let sentence = sentences[usedSentences]
            usedSentences += 1
            let length = language.pack.script == .kanaKanji ? sentence.text.count : sentence.text.split(separator: " ").count
            if !short || length <= (language.pack.script == .kanaKanji ? 14 : 6) { return sentence }
        }
        return nil
    }

    // MARK: The dialogue

    /// Lines that can stand as wrong answers for `line`: never one with the same English, or one
    /// that would count as saying it ("ありがとうございました" for "Thank you very much.").
    static func wrongOptions(for line: Dialogue.Line, in lines: [Dialogue.Line], language: Language) -> [Dialogue.Line] {
        let english = Question.normalised(line.english)
        return lines.filter { other in
            other != line && Question.normalised(other.english) != english
                && !AnswerMatch.matches(other.text, expected: line.expected, language: language)
        }
    }

    /// A line of yours in writing, with its romaji for someone who can't read its kana yet.
    func written(_ line: Dialogue.Line, seen: Int, run: StudyRun) -> (hint: Scaffolded, romaji: String?) {
        let context = run.scaffolds(language)
        if let romaji = Scaffolds.romaji(line, context) { return (.plain(line.text, language), romaji) }
        return (Scaffolds.line(line.text, reading: line.reading, language: language, seen: seen, context), nil)
    }

    /// Before a dialogue's first run-through, each line of yours on its own: what it means, how it
    /// sounds, then said back. The conversation then asks for phrases that have been taught.
    mutating func phraseStep(_ dialogue: Dialogue, run: StudyRun) -> StudyRun.Step? {
        let yours = dialogue.lines.filter { $0.speaker == .you }
        guard dialogueSeen == 0, phrase < yours.count else { return nil }
        let line = yours[phrase]
        phrase += 1
        let written = written(line, seen: 0, run: run)
        return speak(
            SpeakingTask(
                id: "\(dialogue.key.raw).phrase.\(phrase).\(run.today.iso)", key: dialogue.key, language: language, kind: .learn,
                instruction: "Repeat after me", gloss: line.english, prompt: .audio(line.text, language), hint: written.hint,
                romaji: written.romaji, expected: line.expected, shape: .sentence(line.text, words: []), answer: line.text,
                meaning: line.english, expectedSeconds: 10))
    }

    mutating func dialogueStep(_ dialogue: Dialogue, _ index: Int, run: StudyRun) -> StudyRun.Step {
        let line = dialogue.lines[index]
        var rng = SeededRandom(run.seed, dialogue.id, "\(index)")
        let others = Dialogues.dialogues(language).filter { $0.id != dialogue.id }.shuffled(using: &rng).flatMap(\.lines)
        let id = "\(dialogue.key.raw).\(index).\(run.today.iso)"
        let options = Self.wrongOptions(for: line, in: dialogue.lines + others, language: language)
        let romaji = Scaffolds.romaji(line, run.scaffolds(language))
        switch line.speaker {
        case .them:
            let wrong = options.map(\.english)
            return .question(
                .choosing(
                    id: id, key: dialogue.key, kind: .learn, instruction: "\(dialogue.title): what did they say?",
                    prompt: .audio(line.text, language), correct: line.english, wrong: wrong.shuffled(using: &rng),
                    expectedSeconds: 10, reveal: .note("\(line.text)\n\(line.english)"), rng: &rng))
        case .you:
            if muted {
                let yours = options.filter { $0.speaker == .you }
                let wrong = yours.map { romaji == nil ? $0.text : $0.romaji ?? $0.text }
                return .question(
                    .choosing(
                        id: id, key: dialogue.key, kind: .learn, instruction: "\(dialogue.title): what would you say?",
                        prompt: .text("“\(line.english)”"), correct: romaji ?? line.text, wrong: wrong.shuffled(using: &rng),
                        style: romaji == nil ? .foreign : .text, expectedSeconds: 10, reveal: .note("\(line.text)\n\(line.english)"), rng: &rng))
            }
            let written = dialogueSeen < 2 ? written(line, seen: dialogueSeen, run: run) : nil
            return speak(
                SpeakingTask(
                    id: id, key: dialogue.key, language: language, kind: .learn, instruction: "\(dialogue.title): your turn",
                    prompt: .text("“\(line.english)”"), hint: written?.hint, romaji: romaji, expected: line.expected,
                    shape: .sentence(line.text, words: []), answer: line.text, meaning: line.english,
                    expectedSeconds: 10))
        }
    }
}

/// The speaking or writing test: a word from its meaning and a sentence said back (or written
/// down), level by level, until a level where nothing comes out right. "Can't speak now" leaves
/// the speaking test for next time without a result.
struct ProductionTestRunner: PartRunner {
    let language: Language
    let mode: SpeakingTask.Mode
    let seed: String
    let offset: Int
    var band = 0
    var queue: [SpeakingTask]
    var current: SpeakingTask?
    var cancelled = false

    init(language: Language, mode: SpeakingTask.Mode, deck: LanguageDeck, seed: String, offset: Int) {
        self.language = language
        self.mode = mode
        self.seed = seed
        self.offset = offset
        queue = LanguageTests.production(mode, band: 0, deck: deck, seed: seed, offset: offset)
    }

    var kind: TestKind { mode == .say ? .speaking : .languageWriting }

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        current = nil
        guard !cancelled, run.partSeconds < run.budget * 2.5, let deck = run.catalogs.deck(language) else { return nil }
        if queue.isEmpty {
            guard LanguageTests.continueProduction(after: band, attempts: run.partAttempts.filter { $0.test == kind }) else { return nil }
            band += 1
            queue = LanguageTests.production(mode, band: band, deck: deck, seed: seed, offset: offset)
        }
        guard !queue.isEmpty else { return nil }
        current = queue.removeFirst()
        return current.map(StudyRun.Step.speak)
    }

    mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool {
        guard let task = current else { return false }
        current = nil
        if case .skip = response {
            if mode == .say {
                cancelled = true
            } else {
                // "Don't know" on the writing test.
                run.log(task.key, kind: .test, correct: false, skipped: true, expected: task.expectedSeconds, test: kind, band: task.band)
            }
            return true
        }
        guard let answer = StudyRun.produced(response) else { return false }
        run.mark(task, answer: answer)
        return true
    }

    mutating func finish(_ run: inout StudyRun) {
        let tested = run.partAttempts.filter { $0.test == kind }
        guard !cancelled, tested.count >= 2 else { return }
        run.newTests.append(LanguageTests.skillResult(kind, tested, date: run.now, language: language, choices: false))
    }
}

extension StudyRun {
    /// What decides a language's scaffolding now: this session's cards, the placement level and
    /// whether kana is read yet.
    func scaffolds(_ language: Language) -> Scaffolds.Context {
        Scaffolds.Context(cards: cards, frontier: frontier(language), readsKana: settings.readsKana)
    }

    /// A sentence with its fading scaffold, for showing after an answer or in a lesson.
    public func scaffold(_ sentence: Sentence, in language: Language) -> Scaffolded {
        guard let deck = catalogs.deck(language) else { return .plain(sentence.text, language) }
        return Scaffolds.sentence(sentence, deck: deck, scaffolds(language))
    }

    /// A word with its fading scaffold.
    public func scaffold(_ word: Word) -> Scaffolded { Scaffolds.word(word, scaffolds(word.language)) }
}
