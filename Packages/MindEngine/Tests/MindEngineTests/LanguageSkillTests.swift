import Foundation
import SystemCore
import Testing

@testable import MindEngine

/// A made-up Spanish deck: a few real words first (so pictures, dialogues and matching have
/// something to work with), then numbered ones, and sentences of three words from common to rare.
enum SpanishFixture {
    static let real: [(String, String, String)] = [
        ("comer", "to eat", "verb"), ("el perro", "dog", "noun"), ("la casa", "house; home", "noun"), ("hablar", "to speak; to talk", "verb"),
        ("el gato", "cat", "noun"), ("el agua", "water", "noun"), ("el sol", "sun", "noun"), ("el libro", "book", "noun"),
        ("el coche", "car", "noun"), ("el árbol", "tree", "noun"), ("el pez", "fish", "noun"), ("la luna", "moon", "noun"),
    ]

    static func deck(words count: Int = 3000, sentences: Int = 3000) -> LanguageDeck {
        let kinds = ["noun", "verb", "adjective"]
        let words = (1...count).map { i -> Word in
            if i <= real.count {
                return Word(id: 200_000 + i, language: .spanish, rank: i, text: real[i - 1].0, meaning: real[i - 1].1, pos: real[i - 1].2)
            }
            return Word(id: 200_000 + i, language: .spanish, rank: i, text: "palabra\(Self.letters(i))", meaning: "meaning \(i)", pos: kinds[i % 3])
        }
        let list = (0..<sentences).map { $0 + 1 }.map { i -> Sentence in
            let ranks = [1 + i % 40, 1 + (i * 13) % 400, 1 + (i * 31) % max(1, min(count, i * 3))]
            return Sentence(
                id: i, text: "Frase \(Self.letters(i)) aquí.", english: "Sentence number \(i) in English.", level: ranks.max()!,
                words: ranks.map { 200_000 + $0 })
        }
        return LanguageDeck(language: .spanish, words: words, sentences: list)
    }

    /// A number as letters, so made-up words have no digits in them: 12 is "bc".
    static func letters(_ n: Int) -> String {
        String(String(n).map { Character(UnicodeScalar(UInt8(97 + Int(String($0))!))) })
    }
}

/// Runs a session like `Student.run`, answering speaking and writing with the right answer unless
/// told otherwise, and keeps every step it saw.
struct Driver {
    var student: Student
    var steps: [StudyRun.Step] = []
    var speak: (SpeakingTask) -> StepResponse = { .spoken(transcript: $0.expected.first ?? "", seconds: 4) }
    /// Sentences up to this test band are understood (and said, and written); harder ones aren't.
    var sentenceBand = 1

    mutating func run(_ run: inout StudyRun, from start: Date) {
        var now = start
        var guardSteps = 0
        while let step = run.step, guardSteps < 2000 {
            guardSteps += 1
            steps.append(step)
            switch step {
            case .speak(let task):
                now += 6
                let response = (task.band ?? 0) <= sentenceBand ? speak(task) : .spoken(transcript: "no sé", seconds: 4)
                run.respond(task.mode == .write ? written(response) : response, now: now)
                if run.feedback != nil { run.next(now: now + 2) }
            case .question(let question):
                now += max(1, question.expectedSeconds * student.pace)
                let sentence = question.key.domain.isLanguage && question.key.wordID == nil && !question.key.isKana
                let known =
                    sentence
                    ? (question.band.map { $0 <= sentenceBand } ?? true)
                    : student.knows(question, cards: run.cards, now: now) ?? false
                if known, let index = question.correctChoice {
                    run.choose(index, now: now)
                } else if question.allowsDontKnow {
                    run.dontKnow(now: now)
                } else if let index = question.correctChoice {
                    run.choose((index + 1) % max(1, question.choices.count), now: now)
                } else {
                    run.type(student.answerText(question), now: now)
                }
                run.next(now: now + 2)
            case .lesson:
                now += 20
                run.next(now: now)
            default:
                // Nothing else comes up in a language-only session.
                run.skipPart(now: now)
            }
        }
        run.finish(now: now)
    }

    /// Runs the day's planned session, if there is one, and keeps it.
    @discardableResult
    mutating func study(_ store: inout Store, on day: Day, deck: LanguageDeck) -> StudyRun? {
        let state = store.state(on: day)
        let catalogs = Fixtures.catalogs(deck)
        guard let plan = SessionPlanner.checkIns(state, catalogs: catalogs).first ?? SessionPlanner.today(state, catalogs: catalogs) else {
            return nil
        }
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        self.run(&run, from: state.now)
        store.save(run)
        return run
    }

    func written(_ response: StepResponse) -> StepResponse {
        if case .spoken(let text, _) = response { return .written(text: text, source: .typed) }
        return response
    }

    var questions: [Question] { steps.compactMap { if case .question(let q) = $0 { q } else { nil } } }
    var tasks: [SpeakingTask] { steps.compactMap { if case .speak(let t) = $0 { t } else { nil } } }
}

@Suite("Spanish sounds")
struct SpanishSoundsTests {
    @Test("syllables and stress follow the spelling: accents, the vowel-n-s rule, diphthongs, clusters and digraphs")
    func syllables() {
        let cases = [
            "perro": "PE·rro", "hablar": "ha·BLAR", "corazón": "co·ra·ZÓN", "agua": "A·gua", "ciudad": "ciu·DAD", "país": "pa·ÍS",
            "día": "DÍ·a", "guitarra": "gui·TA·rra", "queso": "QUE·so", "llamar": "lla·MAR", "examen": "e·XA·men",
            "construir": "cons·TRUIR", "aeropuerto": "a·e·ro·PUER·to", "pingüino": "pin·GÜI·no", "ayer": "a·YER", "estoy": "es·TOY",
            "hombre": "HOM·bre", "instante": "ins·TAN·te", "ahora": "a·HO·ra",
        ]
        for (word, guide) in cases { #expect(SpanishSounds.guide(word) == guide, "\(word)") }
        #expect(SpanishSounds.guide("sol") == nil, "one syllable needs no guide")
        #expect(SpanishSounds.guide("el perro") == "el PE·rro", "the article stays as it is")
        #expect(SpanishSounds.bare("el/la estudiante") == "estudiante")
    }
}

@Suite("Fading scaffolds")
struct ScaffoldTests {
    let eat = Word(id: 1, language: .japanese, rank: 300, text: "食べる", kana: "たべる", meaning: "to eat", pos: "verb")
    let tea = Word(id: 2, language: .japanese, rank: 400, text: "お茶", kana: "おちゃ", meaning: "tea")
    let japan = Word(id: 3, language: .japanese, rank: 200, text: "日本", kana: "にほん", meaning: "Japan")
    let book = Word(id: 4, language: .japanese, rank: 500, text: "本", kana: "ほん", meaning: "book")
    let now = Fixtures.monday.date()

    func card(_ word: Word, stability: Double) -> MemoryCard {
        MemoryCard(key: word.key, memory: Memory(stability: stability, difficulty: 5, lastReview: now, due: now), introduced: now)
    }

    @Test("furigana sits over the kanji only: 食 reads た before べる, お comes before 茶")
    func alignment() throws {
        let eat = try #require(Scaffolds.furigana(eat))
        #expect(eat.prefix == "" && eat.stem == "食" && eat.reading == "た" && eat.suffix == "べる")
        let tea = try #require(Scaffolds.furigana(tea))
        #expect(tea.prefix == "お" && tea.stem == "茶" && tea.reading == "ちゃ")
        #expect(Scaffolds.furigana(Word(id: 9, language: .japanese, rank: 10, text: "この", meaning: "this")) == nil, "kana needs no furigana")
    }

    @Test("in a sentence each word keeps its furigana until it's mastered, then loses it on its own")
    func perWord() {
        let kono = Word(id: 6, language: .japanese, rank: 20, text: "この", meaning: "this")
        let deck = LanguageDeck(language: .japanese, words: [eat, japan, book, kono])
        let sentence = Sentence(id: 1, text: "この日本の本を食べました。", english: "I ate this Japanese book.", level: 500, words: [6, 3, 4, 1])
        let learning = Scaffolds.sentence(sentence, deck: deck, Scaffolds.Context(cards: [:], frontier: 0, readsKana: true))
        #expect(learning.text == sentence.text)
        #expect(learning.segments.filter { $0.help != nil }.map(\.text) == ["日本", "本", "食"], "日本 claims its 本 first")
        let someMastered = Scaffolds.Context(
            cards: [japan.key: card(japan, stability: 40), eat.key: card(eat, stability: 3)],
            frontier: 0, readsKana: true)
        let fading = Scaffolds.sentence(sentence, deck: deck, someMastered)
        #expect(fading.segments.filter { $0.help != nil }.map(\.text) == ["本", "食"])
        #expect(fading.segments.first { $0.text == "食" }?.help == "た")
        // Below the placement level and never carded: known, so no help.
        let placed = Scaffolds.sentence(sentence, deck: deck, Scaffolds.Context(cards: [:], frontier: 1000, readsKana: true))
        #expect(!placed.hasHelp)
    }

    @Test("romaji shows under each kana not yet mastered, only for someone still learning kana")
    func romaji() {
        let kore = Word(id: 5, language: .japanese, rank: 50, text: "これ", meaning: "this")
        let none = Scaffolds.word(kore, Scaffolds.Context(cards: [:], frontier: 0, readsKana: true))
        #expect(!none.hasHelp, "people who read kana never see romaji")
        let all = Scaffolds.word(kore, Scaffolds.Context(cards: [:], frontier: 0, readsKana: false))
        #expect(all.segments.compactMap(\.help) == ["ko", "re"])
        let ko = KanaTable.byKana["こ"]!
        var mastered = MemoryCard(key: ko.key, memory: Memory(stability: 30, difficulty: 5, lastReview: now, due: now), introduced: now)
        mastered.updatedAt = now
        let half = Scaffolds.word(kore, Scaffolds.Context(cards: [ko.key: mastered], frontier: 0, readsKana: false))
        #expect(half.segments.compactMap(\.help) == ["re"], "こ is mastered, れ isn't")
        #expect(KanaTable.romaji("きょう") == "kyou")
        #expect(KanaTable.romaji("ちょっと") == "chotto")
        #expect(KanaTable.romaji("コーヒー") == "koohii")
    }

    @Test("for someone still learning kana, a kanji word's reading shows in romaji until its kana are mastered, then as furigana")
    func romajiOverKanji() {
        let learning = Scaffolds.word(eat, Scaffolds.Context(cards: [:], frontier: 0, readsKana: false))
        #expect(learning.segments.map(\.text) == ["食", "べ", "る"])
        #expect(learning.segments.map(\.help) == ["ta", "be", "ru"] && learning.segments[0].kind == .romaji)
        let ta = KanaTable.byKana["た"]!
        let known = MemoryCard(key: ta.key, memory: Memory(stability: 30, difficulty: 5, lastReview: now, due: now), introduced: now)
        let kanaIn = Scaffolds.word(eat, Scaffolds.Context(cards: [ta.key: known], frontier: 0, readsKana: false))
        #expect(kanaIn.segments[0].help == "た" && kanaIn.segments[0].kind == .furigana, "た is read now, so the furigana is")
        let sentence = Sentence(id: 1, text: "本を食べた。", english: "I ate the book.", level: 500, words: [4, 1])
        let deck = LanguageDeck(language: .japanese, words: [eat, book])
        let line = Scaffolds.sentence(sentence, deck: deck, Scaffolds.Context(cards: [:], frontier: 0, readsKana: false))
        #expect(line.segments.first { $0.text == "本" }?.help == "hon" && line.segments.first { $0.text == "食" }?.help == "ta")
    }

    @Test("a Spanish word shows its stress guide until it's mastered; in a sentence only the words still being learned do")
    func spanish() {
        let deck = SpanishFixture.deck(words: 50, sentences: 0)
        let perro = deck.word(200_002)!
        let comer = deck.word(200_001)!
        #expect(Scaffolds.word(perro, Scaffolds.Context(cards: [:], frontier: 0, readsKana: nil)).segments.first?.help == "el PE·rro")
        let sentence = Sentence(
            id: 1, text: "El perro comía en casa.", english: "The dog was eating at home.", level: 3, words: [200_002, 200_001, 200_003])
        let context = Scaffolds.Context(cards: [perro.key: card(perro, stability: 30)], frontier: 0, readsKana: nil)
        let helped = Scaffolds.sentence(sentence, deck: deck, context).segments.filter { $0.help != nil }
        #expect(helped.map(\.text) == ["comía", "casa"], "\(helped)")
        #expect(helped.first?.help == "co·MÍ·a")
        _ = comer
    }
}

@Suite("Spoken and written answers")
struct AnswerMatchTests {
    @Test("Spanish: accents, case, punctuation and the article don't count against an answer; ñ does; digits are numbers")
    func spanish() {
        #expect(AnswerMatch.matches("el perro", expected: ["perro"], language: .spanish))
        #expect(AnswerMatch.matches("Perro.", expected: ["el perro", "perro"], language: .spanish))
        #expect(
            AnswerMatch.matches("cafe con leche por favor", expected: ["Un café con leche, por favor."], language: .spanish) == false,
            "a sentence isn't a phrase inside another")
        #expect(AnswerMatch.matches("un cafe con leche, por favor", expected: ["café con leche"], language: .spanish))
        #expect(!AnswerMatch.matches("ano", expected: ["año"], language: .spanish), "ñ is a letter, not an accent")
        #expect(AnswerMatch.matches("Son 2 euros", expected: ["son dos euros"], language: .spanish))
        #expect(!AnswerMatch.matches("perrito", expected: ["perro"], language: .spanish), "whole words only")
        #expect(!AnswerMatch.matches("", expected: ["perro"], language: .spanish))
    }

    @Test("Japanese: kanji or kana, katakana or hiragana, and full-width digits all count")
    func japanese() {
        let eat = Word(id: 1, language: .japanese, rank: 300, text: "食べる", kana: "たべる", meaning: "to eat", pos: "verb")
        let variants = AnswerMatch.variants(eat)
        #expect(AnswerMatch.matches("食べる", expected: variants, language: .japanese))
        #expect(AnswerMatch.matches("たべる。", expected: variants, language: .japanese))
        #expect(AnswerMatch.matches("タベル", expected: variants, language: .japanese))
        #expect(AnswerMatch.matches("コーヒーをひとつください", expected: ["こーひーをひとつください"], language: .japanese))
        #expect(AnswerMatch.matches("３人です", expected: ["三人です"], language: .japanese))
    }

    @Test("a sentence said back counts when most of its words are there")
    func coverage() {
        #expect(AnswerMatch.coverage("el perro come en casa", of: "El perro come en la casa.", words: [], language: .spanish) >= 0.75)
        #expect(AnswerMatch.coverage("el gato", of: "El perro come en la casa.", words: [], language: .spanish) < 0.5)
        let words = [
            Word(id: 1, language: .japanese, rank: 300, text: "食べる", kana: "たべる", meaning: "to eat", pos: "verb"),
            Word(id: 2, language: .japanese, rank: 400, text: "パン", meaning: "bread"),
        ]
        #expect(
            AnswerMatch.coverage("ぱんをたべました", of: "パンを食べました。", words: words, language: .japanese) == 1,
            "found by kana stem though written in kana")
        let task = SpeakingTask(
            id: "t", key: .practice(.spanish, "speaking"), language: .spanish, kind: .learn, instruction: "", prompt: .text(""),
            expected: ["El perro come en la casa."], shape: .sentence("El perro come en la casa.", words: []), expectedSeconds: 5)
        #expect(task.check("el perro come en casa"))
        #expect(!task.check("el perro"))
    }
}

@Suite("Four skills")
struct FourSkillsTests {
    func result(_ kind: TestKind, bands: [Double], on day: Day, language: Language = .spanish) -> TestResult {
        var detail: [String: Double] = [:]
        for (band, share) in bands.enumerated() { detail["band\(band)"] = share }
        return TestResult(test: kind, date: day.date(), score: 0, detail: detail, language: language)
    }

    @Test("a skill's reach is each band's share times its width, and its level doubles from 100 words")
    func levels() throws {
        let listening = result(.listening, bands: [1, 0.5, 0.25], on: Fixtures.monday)
        #expect(LanguageSkills.words(listening) == 500 + 250 + 250)
        let level = try #require(LanguageSkills.level(listening))
        #expect(level.level == 4 && level.skill == .listening, "1,000 words is level 4")
        #expect(LanguageSkills.level(words: 99) == 0 && LanguageSkills.level(words: 100) == 1 && LanguageSkills.level(words: 4000) == 6)
        #expect(abs(level.score - LanguageTests.vocabularyScore(1000)) < 0.001, "on the vocabulary test's scale")
    }

    @Test("the language's score needs every skill measured, and listening and speaking move it most")
    func weighting() {
        let day = Fixtures.monday
        let base = [
            result(.listening, bands: [0.5], on: day), result(.speaking, bands: [0.5], on: day),
            result(.languageReading, bands: [0.5], on: day), result(.languageWriting, bands: [0.5], on: day),
        ]
        let all = LanguageSkill.allCases
        #expect(LanguageSkills.score(LanguageSkills.levels(.spanish, tests: Array(base.prefix(3))), skills: all) == nil)
        let even = LanguageSkills.score(LanguageSkills.levels(.spanish, tests: base), skills: all)!
        func raised(_ kind: TestKind) -> Double {
            let tests = base.map { $0.test == kind ? result(kind, bands: [1, 1], on: day) : $0 }
            return LanguageSkills.score(LanguageSkills.levels(.spanish, tests: tests), skills: all)! - even
        }
        #expect(raised(.listening) > raised(.languageReading) && raised(.speaking) > raised(.languageWriting))
        #expect(abs(raised(.listening) - raised(.speaking)) < 0.001)
        // Speaking off and never measured: the other three make the score.
        var settings = Fixtures.settings([.spanish])
        settings.speaking = false
        #expect(LanguageSkills.enabled(settings, tests: [], domain: .spanish) == [.listening, .reading, .writing])
        #expect(LanguageSkills.enabled(settings, tests: base, domain: .spanish).count == 4, "measured before, so it stays")
    }

    @Test("the series is vocabulary until all four skills are in, then the skills alone, so the first skill test isn't a change")
    func series() {
        var store = Store(settings: Fixtures.settings([.spanish]))
        let monday = Fixtures.monday
        store.tests = [
            TestResult(test: .vocabulary, date: monday.date(), score: 800, placement: true, language: .spanish),
            result(.listening, bands: [0.8, 0.4], on: monday.adding(days: 1)),
            result(.speaking, bands: [0.5], on: monday.adding(days: 1)),
        ]
        let early = LanguageModule.series(.spanish, state: store.state(on: monday.adding(days: 2)))
        #expect(early.count == 1 && abs(early[0].score - LanguageTests.vocabularyScore(800)) < 0.001)
        store.tests += [
            result(.languageReading, bands: [0.9, 0.6], on: monday.adding(days: 3)),
            result(.languageWriting, bands: [0.4], on: monday.adding(days: 3)),
        ]
        let measured = LanguageModule.series(.spanish, state: store.state(on: monday.adding(days: 4)))
        #expect(measured.count == 1 && measured[0].day == monday.adding(days: 3), "\(measured)")
        store.tests += [result(.listening, bands: [1, 0.8, 0.5], on: monday.adding(days: 50))]
        let later = LanguageModule.series(.spanish, state: store.state(on: monday.adding(days: 51)))
        #expect(later.count == 2 && later[1].score > later[0].score)
    }
}

@Suite("Language sessions")
struct LanguageSessionTests {
    let deck = SpanishFixture.deck()

    /// A Spanish learner who's done the placement and knows `known` words from the app.
    func store(known: Int, speaking: Bool = true, skills: Bool = true) -> Store {
        var settings = Fixtures.settings([.spanish])
        settings.speaking = speaking
        var store = Store(settings: settings)
        let now = Fixtures.monday.date()
        store.sessions = [
            StudySession(
                purpose: .placement, start: now, end: now, plannedMinutes: 25, domains: [.spanish], planned: true,
                ranToEnd: true)
        ]
        store.tests = [TestResult(test: .vocabulary, date: now, score: 400, placement: true, language: .spanish)]
        if skills {
            for kind in [TestKind.listening, .speaking, .languageReading, .languageWriting] {
                store.tests.append(TestResult(test: kind, date: now, score: 0.3, detail: ["band0": 0.6, "words": 300], language: .spanish))
            }
        }
        for word in deck.words.prefix(known) {
            store.cards[word.key] = MemoryCard(key: word.key, memory: Scheduler.known(stability: 20, at: now), introduced: now)
        }
        return store
    }

    func practice(_ store: Store, on day: Day) throws -> (StudyRun, Driver) {
        let state = store.state(on: day)
        let plan = SessionPlanner.block(.spanish, state: state, catalogs: Fixtures.catalogs(deck))
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        var driver = Driver(student: Student(vocabulary: 400, mathsLevel: 0, writingLevel: 0, deck: deck))
        driver.run(&run, from: state.now)
        return (run, driver)
    }

    @Test("a regular session teaches new words, then practises in real use: a dialogue, listening, speaking, pictures, reading and writing")
    func practiceKinds() throws {
        let store = store(known: 120)
        let day = Fixtures.monday.adding(days: 1)
        let plan = SessionPlanner.block(.spanish, state: store.state(on: day), catalogs: Fixtures.catalogs(deck))
        #expect(plan.parts.map { "\($0.kind)" }.suffix(2) == ["learn", "sentences"], "\(plan.parts)")
        #expect(plan.parts.last?.title == "Listening and speaking")
        let (run, driver) = try practice(store, on: day)
        let keys = driver.questions.map(\.key.raw) + driver.tasks.map(\.key.raw)
        #expect(keys.contains { $0.hasPrefix("es.dialogue.") }, "a dialogue")
        #expect(driver.questions.contains { $0.key.raw == "es.sentences" }, "sentences by ear")
        #expect(driver.questions.contains { $0.key.raw == "es.reading" }, "sentences to read")
        #expect(driver.questions.contains { $0.choiceStyle == .picture }, "picture matching")
        #expect(driver.tasks.contains { $0.mode == .say && $0.key.wordID != nil }, "saying words")
        #expect(driver.tasks.contains { $0.mode == .say && $0.key.raw == "es.speaking" }, "saying sentences back")
        #expect(driver.tasks.contains { $0.mode == .write }, "writing")
        // Practice measures nothing and schedules nothing.
        #expect(run.newTests.isEmpty)
        #expect(run.changedCards.allSatisfy { $0.wordID != nil })
    }

    @Test("with speaking off there's nothing to say: dialogue answers are picked and nothing asks for the microphone")
    func speakingOff() throws {
        let store = store(known: 120, speaking: false)
        let day = Fixtures.monday.adding(days: 1)
        let plan = SessionPlanner.block(.spanish, state: store.state(on: day), catalogs: Fixtures.catalogs(deck))
        #expect(plan.parts.last?.title == "Listening and reading")
        let (_, driver) = try practice(store, on: day)
        #expect(!driver.tasks.contains { $0.mode == .say })
        #expect(driver.questions.contains { $0.key.raw.hasPrefix("es.dialogue.") && $0.instruction.contains("would you say") })
        let checkIn = LanguageModule.checkInParts(.spanish, state: store.state(on: day), catalogs: Fixtures.catalogs(deck))
        #expect(!checkIn.contains { $0.kind == .test(.speaking) }, "\(checkIn.map(\.kind))")
    }

    @Test("“Can't speak now” skips without a gap: no more speaking in that block, and the session still fills its time")
    func cantSpeak() throws {
        let store = store(known: 120)
        let state = store.state(on: Fixtures.monday.adding(days: 1))
        let plan = SessionPlanner.block(.spanish, state: state, catalogs: Fixtures.catalogs(deck))
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        var driver = Driver(student: Student(vocabulary: 400, mathsLevel: 0, writingLevel: 0, deck: deck))
        driver.speak = { _ in .skip }
        driver.run(&run, from: state.now)
        let said = driver.tasks.filter { $0.mode == .say }
        #expect(said.count == 1, "asked once, then never again: \(said.map(\.instruction))")
        #expect(!run.session.attempts.contains { $0.key.raw == "es.speaking" }, "the skip isn't an attempt")
        #expect(run.session.minutes > Double(plan.minutes) * 0.6, "\(run.session.minutes) minutes")
    }

    @Test("the four skills are measured once the vocabulary test finds enough words, two at a time, then at every check-in")
    func skillChecks() throws {
        var store = store(known: 120, skills: false)
        let first = SessionPlanner.block(.spanish, state: store.state(on: Fixtures.monday.adding(days: 1)), catalogs: Fixtures.catalogs(deck))
        let tests: [TestKind] = first.parts.compactMap { if case .test(let kind) = $0.kind { kind } else { nil } }
        #expect(tests == [.listening, .speaking], "\(first.parts.map(\.kind))")
        var student = Student(vocabulary: 400, mathsLevel: 0, writingLevel: 0, deck: deck)
        let state = store.state(on: Fixtures.monday.adding(days: 1))
        var run = StudyRun(plan: first, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        _ = student.run(&run, from: state.now)
        store.save(run)
        #expect(Set(store.tests.map(\.test)).isSuperset(of: [.listening, .speaking]))
        let second = SessionPlanner.block(.spanish, state: store.state(on: Fixtures.monday.adding(days: 2)), catalogs: Fixtures.catalogs(deck))
        let secondTests: [TestKind] = second.parts.compactMap { if case .test(let kind) = $0.kind { kind } else { nil } }
        #expect(secondTests == [.languageReading, .languageWriting])
        let checkIn = LanguageModule.checkInParts(
            .spanish, state: store.state(on: Fixtures.monday.adding(days: 2)), catalogs: Fixtures.catalogs(deck))
        #expect(checkIn.map(\.kind) == [.test(.vocabulary), .test(.listening), .test(.speaking), .test(.languageReading), .test(.languageWriting)])
        // Not before the vocabulary test finds 150 words.
        var beginner = self.store(known: 10, skills: false)
        beginner.tests[0].score = 60
        let early = SessionPlanner.block(.spanish, state: beginner.state(on: Fixtures.monday.adding(days: 1)), catalogs: Fixtures.catalogs(deck))
        #expect(!early.parts.contains { if case .test = $0.kind { true } else { false } })
    }

    @Test("the speaking test climbs until a level comes out wrong; “Can't speak now” leaves it for next time")
    func speakingTest() throws {
        let store = store(known: 120)
        let state = store.state(on: Fixtures.monday.adding(days: 3))
        let plan = SessionPlanner.plan(.checkIn, domains: [.spanish], state: state, catalogs: Fixtures.catalogs(deck))
        // Right up to rank 1,000, wrong beyond.
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        var driver = Driver(student: Student(vocabulary: 400, mathsLevel: 0, writingLevel: 0, deck: deck))
        driver.speak = { task in .spoken(transcript: (task.band ?? 0) <= 1 ? task.expected.first ?? "" : "no sé", seconds: 4) }
        driver.run(&run, from: state.now)
        let speaking = try #require(run.newTests.first { $0.test == .speaking })
        #expect(speaking.detail["band0"] == 1 && speaking.detail["band1"] == 1 && speaking.detail["band2"] == 0)
        #expect(speaking.detail["band3"] == nil, "stops after a level with nothing right")
        #expect(LanguageSkills.words(speaking) == 1000)
        let writing = try #require(run.newTests.first { $0.test == .languageWriting })
        #expect(LanguageSkills.level(writing)?.level ?? 0 >= 4)

        var quiet = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        var silent = Driver(student: Student(vocabulary: 400, mathsLevel: 0, writingLevel: 0, deck: deck))
        silent.speak = { task in task.mode == .say ? .skip : .spoken(transcript: task.expected.first ?? "", seconds: 4) }
        silent.run(&quiet, from: state.now)
        #expect(!quiet.newTests.contains { $0.test == .speaking })
        #expect(quiet.newTests.contains { $0.test == .languageWriting })
    }

    @Test("seven weeks of Spanish: placement, the four skills in the first week, practice every session, then a check-in that moves Intelligence")
    func sevenWeeks() throws {
        var store = Store(settings: Fixtures.settings([.spanish]))
        var driver = Driver(student: Student(vocabulary: 600, mathsLevel: 0, writingLevel: 0, deck: deck))
        for offset in 0..<(7 * 7 + 3) {
            driver.study(&store, on: Fixtures.monday.adding(days: offset), deck: deck)
        }
        let byWeekOne = store.tests.filter { $0.day < Fixtures.monday.adding(days: 7) }
        #expect(
            Set(byWeekOne.map(\.test)).isSuperset(of: [.vocabulary, .listening, .speaking, .languageReading, .languageWriting]),
            "\(byWeekOne.map(\.test))")
        let practised = store.sessions.flatMap(\.attempts).filter { $0.key.raw.hasPrefix("es.dialogue.") }
        #expect(!practised.isEmpty)
        #expect(store.cards.keys.allSatisfy { $0.wordID != nil }, "practice never makes a card")
        var checkIn: StudyRun?
        for offset in 52...56 where checkIn == nil {
            // By the check-in, sentences of the first 2,000 words are understood.
            driver.sentenceBand = 2
            if let run = driver.study(&store, on: Fixtures.monday.adding(days: offset), deck: deck), run.plan.kind == .checkIn {
                checkIn = run
            }
        }
        let run = try #require(checkIn)
        #expect(Set(run.newTests.map(\.test)) == [.vocabulary, .listening, .speaking, .languageReading, .languageWriting])
        let state = store.state(on: Fixtures.monday.adding(days: 57))
        let levels = LanguageSkills.levels(.spanish, tests: state.tests)
        #expect(levels.count == 4 && levels.values.allSatisfy { $0.level >= 3 }, "\(levels.mapValues(\.words))")
        let series = LanguageModule.series(.spanish, state: state)
        #expect(series.count >= 2 && series.last!.score > series.first!.score, "\(series)")
        let intelligence = try #require(Analyst.analyse(state, catalogs: Fixtures.catalogs(deck)).stats.first { $0.stat == .intelligence })
        #expect(intelligence.score == series.last?.score)
    }
}

@Suite("Graded readers")
struct GradedReaderTests {
    @Test("each language has readers at every level, and its own reading level beside the English ladder")
    func levels() throws {
        for language in Language.allCases {
            let readers = GradedReaders.readers(language)
            #expect(Set(readers.map(\.level)) == Set(GradedReaders.levels), "\(language)")
            #expect(Set(readers.map(\.id)).count == readers.count)
        }
        #expect(GradedReaders.targetLevel(.spanish, books: [], words: 400) == 1)
        #expect(GradedReaders.targetLevel(.spanish, books: [], words: 3000) == 4)
        var first = try #require(GradedReaders.reader("es.pobre-ana")).book(status: .finished)
        first.feel = .right
        first.finished = Fixtures.monday
        #expect(GradedReaders.comfortLevel(.spanish, books: [first]) == 1)
        #expect(GradedReaders.targetLevel(.spanish, books: [first], words: 400) == 2)
        #expect(GradedReaders.suggestions(.spanish, books: [first], words: 400).allSatisfy { abs($0.level - 2) <= 1 && $0.id != first.ladderID })
        #expect(GradedReaders.comfortLevel(.japanese, books: [first]) == nil, "Spanish readers don't place Japanese")
        // A reader on the go is never the English reading block's book.
        let reading = GradedReaders.reader("es.marina")!.book(status: .reading, started: Fixtures.monday)
        let state = StudyState(settings: Fixtures.settings(), books: [reading], today: Fixtures.monday, now: Fixtures.monday.date())
        #expect(state.currentBook == nil)
        #expect(GradedReaders.current(.spanish, books: [reading])?.title == "Marina")
    }
}

@Suite("Language content")
struct LanguageContentTests {
    @Test("dialogues: three levels in each language, a turn for you in each, and every line of yours matches itself")
    func dialogues() {
        for language in Language.allCases {
            let all = Dialogues.dialogues(language)
            #expect(Set(all.map(\.level)) == [1, 2, 3], "\(language)")
            #expect(Set(all.map(\.id)).count == all.count)
            for dialogue in all {
                #expect(dialogue.lines.contains { $0.speaker == .you } && dialogue.lines.contains { $0.speaker == .them }, "\(dialogue.id)")
                for line in dialogue.lines where line.speaker == .you {
                    #expect(AnswerMatch.matches(line.text, expected: line.expected, language: language), "\(dialogue.id): \(line.text)")
                    if let reading = line.reading { #expect(AnswerMatch.matches(reading, expected: line.expected, language: language)) }
                    for accepted in line.accept {
                        #expect(AnswerMatch.matches(accepted, expected: line.expected, language: language), "\(dialogue.id): \(accepted)")
                    }
                }
            }
        }
        #expect(Dialogues.level(frontier: 0, known: 40) == 1 && Dialogues.level(frontier: 2000, known: 0) == 3)
        let practised = ["saludos": 2, "cafe": 1]
        #expect(Dialogues.next(.spanish, level: 1, practised: practised)?.id == "estacion")
    }

    #if canImport(AppKit)
    @Test("every picture is a real SF Symbol")
    func pictures() {
        for (meaning, symbol) in Pictures.symbols {
            #expect(systemSymbolExists(symbol), "\(meaning): \(symbol)")
        }
        let dog = Word(id: 1, language: .spanish, rank: 1, text: "el perro", meaning: "dog")
        #expect(Pictures.symbol(for: dog) == "dog.fill")
        #expect(Pictures.symbol(for: Word(id: 2, language: .japanese, rank: 1, text: "食べる", meaning: "to eat")) == "fork.knife")
    }
    #endif

    @Test("the real Spanish catalog, when it's been built: common words first, nouns with their article, sentences at every level")
    func realSpanish() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../Apps/MindTrack/Catalogs/spanish.db")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let deck = try #require(LanguageDeck(url: url, language: .spanish))
        #expect(deck.words.count > 12_000)
        #expect(deck.attribution.contains("Tatoeba") && deck.attribution.contains("Wiktionary"))
        let top = Set(deck.words.prefix(60).map(\.text))
        #expect(top.isSuperset(of: ["de", "que", "ser", "estar", "tener", "ir", "hacer", "poder"]), "\(top.sorted())")
        #expect(!deck.words.prefix(2000).contains { ["el", "la", "los", "un", "me", "se", "del"].contains($0.text) }, "grammar words aren't cards")
        let eat = try #require(deck.words.first { $0.text == "comer" })
        #expect(eat.rank < 400 && eat.meaning == "to eat")
        let dog = try #require(deck.words.first { $0.text == "el perro" })
        #expect(dog.rank < 800 && dog.meaning == "dog")
        #expect(deck.words.contains { $0.text == "el agua" }, "feminine nouns with a stressed a take el")
        #expect(deck.words.first { $0.text == "la casa" }.map { $0.rank < 300 } == true, "casa is the house, not casar's form")
        let examples = deck.sentences(with: eat.id, maxLevel: 500)
        #expect(!examples.isEmpty && examples.allSatisfy { $0.level <= 500 && $0.words.contains(eat.id) })
        let question = LanguageQuiz.question(eat, ask: .meaning, kind: .review, deck: deck, seed: "t")
        #expect(question.choices.count == 4 && question.choices[question.correctChoice!] == "to eat")
        #expect(LanguageTests.listening(deck: deck, seed: "t", offset: 0).count == 10)
        #expect(LanguageTests.reading(deck: deck, seed: "t", offset: 0).count == 10)
        for band in 0..<LanguageTests.bandsAvailable(in: deck) { #expect(LanguageTests.vocabulary(band: band, deck: deck, seed: "t").count == 5) }
        for band in LanguageTests.listeningLevels.indices {
            let tasks = LanguageTests.production(.say, band: band, deck: deck, seed: "t", offset: 0)
            #expect(tasks.count == 2, "band \(band)")
            for task in tasks { #expect(task.check(task.answer), "\(task.answer) counts as itself") }
        }
        #expect(Pictures.symbol(for: dog) == "dog.fill")
    }

    @Test("the real Japanese catalog gives furigana over the kanji of everyday words")
    func realJapanese() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../Apps/MindTrack/Catalogs/japanese.db")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let deck = try #require(LanguageDeck(url: url))
        let eat = try #require(deck.words.first { $0.text == "食べる" })
        #expect(Scaffolds.furigana(eat)?.stem == "食")
        let aligned = deck.words.prefix(3000).filter(\.hasKanji)
        let missing = aligned.filter { Scaffolds.furigana($0) == nil }
        #expect(missing.count < aligned.count / 50, "\(missing.prefix(10).map(\.text))")
        let sentence = try #require(deck.sentences(with: eat.id, maxLevel: 1000).first)
        let help = Scaffolds.sentence(sentence, deck: deck, Scaffolds.Context(cards: [:], frontier: 0, readsKana: true))
        #expect(help.text == sentence.text && help.hasHelp)
        for band in LanguageTests.listeningLevels.indices {
            for task in LanguageTests.production(.write, band: band, deck: deck, seed: "t", offset: 0) {
                #expect(task.check(task.answer), "\(task.answer)")
            }
        }
    }
}

#if canImport(AppKit)
import AppKit

func systemSymbolExists(_ symbol: String) -> Bool { NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil }
#endif

extension AnswerMatchTests {
    @Test("numbers heard as digits match the words or kanji they were said as, past the first few")
    func numbers() {
        for (digits, words) in [
            ("13", "trece"), ("16", "dieciséis"), ("21", "veintiuno"), ("22", "veintidós"), ("30", "treinta"),
            ("31", "treinta y uno"), ("100", "cien"), ("101", "ciento uno"), ("200", "doscientos"), ("555", "quinientos cincuenta y cinco"),
            ("1000", "mil"), ("2024", "dos mil veinticuatro"), ("21000", "veintiún mil"),
        ] {
            #expect(AnswerMatch.matches(digits, expected: [words], language: .spanish), "\(digits) for \(words)")
        }
        #expect(
            !AnswerMatch.matches("30", expected: ["treinta y uno"], language: .spanish)
                && !AnswerMatch.matches("13", expected: ["tres"], language: .spanish))
        #expect(AnswerMatch.coverage("Tiene 30 años", of: "Tiene treinta años.", words: [], language: .spanish) == 1)

        for (digits, kanji) in [
            ("12人", "十二人"), ("20", "二十"), ("100円", "百円"), ("400", "四百"), ("2024年", "二千二十四年"), ("2024年", "二〇二四年"),
            ("15000", "一万五千"), ("３人です", "三人です"),
        ] {
            #expect(AnswerMatch.matches(digits, expected: [kanji], language: .japanese), "\(digits) for \(kanji)")
        }
        #expect(!AnswerMatch.matches("11人", expected: ["十二人"], language: .japanese))
        let twelve = Word(id: 3, language: .japanese, rank: 900, text: "十二", kana: "じゅうに", meaning: "twelve", pos: "other")
        let people = Word(id: 4, language: .japanese, rank: 100, text: "人", kana: "にん", meaning: "people")
        #expect(AnswerMatch.coverage("子供が12人", of: "子供が十二人。", words: [twelve, people], language: .japanese) == 1)

        // Big numbers as recognition writes them: digits with 万, and thousands commas.
        for (heard, kanji) in [("1万円", "一万円"), ("3万5千円", "三万五千円"), ("30,000円", "三万円"), ("1億2000万", "一億二千万")] {
            #expect(AnswerMatch.normalised(heard, language: .japanese) == AnswerMatch.normalised(kanji, language: .japanese), "\(heard) for \(kanji)")
        }
        // A number's own deck words (三, 百) are found in it, typed in kanji or heard as digits.
        let three = Word(id: 5, language: .japanese, rank: 815, text: "三", kana: "さん", meaning: "three", pos: "number")
        let hundred = Word(id: 6, language: .japanese, rank: 1341, text: "百", kana: "ひゃく", meaning: "hundred", pos: "number")
        let yen = Word(id: 7, language: .japanese, rank: 300, text: "円", kana: "えん", meaning: "yen", pos: "noun")
        for heard in ["三百円です", "300円です"] {
            #expect(AnswerMatch.coverage(heard, of: "三百円です。", words: [three, hundred, yen], language: .japanese) == 1, "\(heard)")
        }
        // A run of numerals too long to add up is compared as written, never traps.
        let long = String(repeating: "九", count: 25) + "十"
        #expect(AnswerMatch.normalised(long, language: .japanese) == long && AnswerMatch.matches(long, expected: [long], language: .japanese))
        #expect(AnswerMatch.normalised(String(repeating: "9", count: 25) + "万", language: .japanese).hasSuffix("万"))
    }
}

extension FourSkillsTests {
    @Test("turning speaking on before it's been tested keeps the three-skill score; only its test changes it")
    func speakingTurnedOn() {
        var settings = Fixtures.settings([.spanish])
        settings.speaking = false
        var store = Store(settings: settings)
        let monday = Fixtures.monday
        store.tests = [
            TestResult(test: .vocabulary, date: monday.date(), score: 1200, placement: true, language: .spanish),
            result(.listening, bands: [0.8, 0.4], on: monday.adding(days: 1)),
            result(.languageReading, bands: [0.9, 0.6], on: monday.adding(days: 1)),
            result(.languageWriting, bands: [0.4], on: monday.adding(days: 2)),
        ]
        let before = LanguageModule.series(.spanish, state: store.state(on: monday.adding(days: 3)))
        #expect(before.count == 1 && before[0].day == monday.adding(days: 2))
        store.settings.speaking = true
        let after = LanguageModule.series(.spanish, state: store.state(on: monday.adding(days: 3)))
        #expect(after.map(\.day) == before.map(\.day) && after.map(\.score) == before.map(\.score), "\(after)")

        store.tests.append(result(.speaking, bands: [0.6, 0.3], on: monday.adding(days: 10)))
        let measured = LanguageModule.series(.spanish, state: store.state(on: monday.adding(days: 11)))
        #expect(measured.map(\.day) == [monday.adding(days: 10)], "the four skills from the day all four are in")
    }
}

extension LanguageSessionTests {
    @Test("a new word's retry after a miss, and its first ask after a failed check, aren't the question just answered")
    func learnRetries() throws {
        let store = store(known: 0, skills: false)
        let state = store.state(on: Fixtures.monday.adding(days: 1))
        let plan = SessionPlan(
            day: state.today, kind: .regular, minutes: 5, domains: [.spanish],
            parts: [PlanPart(kind: .learn, domain: .spanish, minutes: 5, title: "New Spanish", detail: "", items: 1)],
            headline: "", notes: [], planned: true)
        var run = StudyRun(plan: plan, state: state, catalogs: Fixtures.catalogs(deck), now: state.now)
        var now = state.now
        func miss(_ question: Question) {
            now += 5
            run.choose((question.correctChoice! + 1) % question.choices.count, now: now)
            now += 1
            run.next(now: now)
        }
        // Below the placement level: checked first.
        guard case .question(let probe) = run.step, probe.kind == .probe else {
            Issue.record("no check: \(String(describing: run.step))")
            return
        }
        miss(probe)
        guard case .lesson = run.step else {
            Issue.record("not taught after the miss")
            return
        }
        now += 20
        run.next(now: now)
        guard case .question(let first) = run.step, first.key == probe.key else {
            Issue.record("not asked after the lesson")
            return
        }
        #expect(first.id != probe.id)
        miss(first)
        guard case .question(let retry) = run.step, retry.key == first.key else {
            Issue.record("not asked again")
            return
        }
        #expect(retry.id != first.id)
    }
}

extension LanguageContentTests {
    @Test("a dialogue line's wrong options never mean the same, or say what would count for it")
    func dialogueOptions() {
        for language in Language.allCases {
            let all = Dialogues.dialogues(language)
            let lines = all.flatMap(\.lines)
            for dialogue in all {
                for line in dialogue.lines {
                    let options = PracticeRunner.wrongOptions(for: line, in: lines, language: language)
                    #expect(
                        !options.contains { Question.normalised($0.english) == Question.normalised(line.english) }, "\(dialogue.id): \(line.english)")
                    #expect(
                        !options.contains { AnswerMatch.matches($0.text, expected: line.expected, language: language) },
                        "\(dialogue.id): \(line.text)")
                    #expect(options.filter { $0.speaker == line.speaker }.count >= 3, "\(dialogue.id): enough left to choose from")
                }
            }
        }
        let thanks = Dialogues.dialogues(.japanese).flatMap(\.lines).first { $0.text == "ありがとうございます。" }
        if let thanks {
            #expect(
                !PracticeRunner.wrongOptions(for: thanks, in: Dialogues.dialogues(.japanese).flatMap(\.lines), language: .japanese)
                    .contains { $0.text == "ありがとうございました。" })
        }
    }
}

@Suite("Dialogues while learning kana")
struct KanaLearnerDialogueTests {
    let deck = Fixtures.deck()
    let day = Fixtures.monday.adding(days: 1)

    /// Thirty words in, and not one kana mastered: the first block a dialogue reaches.
    func store(readsKana: Bool, speaking: Bool = true) -> Store {
        var settings = Fixtures.settings([.japanese], readsKana: readsKana)
        settings.speaking = speaking
        var store = Store(settings: settings)
        let now = Fixtures.monday.date()
        // Someone who reads kana is placed first, and a dialogue comes the block after.
        if readsKana { store.tests = [TestResult(test: .vocabulary, date: now, score: 30, placement: true)] }
        for word in deck.words.prefix(30) {
            store.cards[word.key] = MemoryCard(key: word.key, memory: Scheduler.known(stability: 20, at: now), introduced: now)
        }
        return store
    }

    func practice(_ store: Store) -> Driver {
        let state = store.state(on: day)
        let catalogs = Fixtures.catalogs(deck)
        var run = StudyRun(plan: SessionPlanner.block(.japanese, state: state, catalogs: catalogs), state: state, catalogs: catalogs, now: state.now)
        var driver = Driver(student: Student(vocabulary: 30, mathsLevel: 0, writingLevel: 0, deck: deck))
        driver.run(&run, from: state.now)
        return driver
    }

    @Test("every line you're asked to say comes with its romaji, and the kana line isn't left to read alone")
    func saying() {
        let lines = practice(store(readsKana: false)).tasks.filter { $0.key.raw.hasPrefix("jp.dialogue.") }
        #expect(!lines.isEmpty)
        for task in lines {
            #expect(task.romaji != nil, "\(task.answer)")
            #expect(task.hint?.hasHelp == false, "\(task.answer)")
        }
    }

    @Test("someone who reads kana keeps the reading over the line, and no romaji")
    func readers() {
        let lines = practice(store(readsKana: true)).tasks.filter { $0.key.raw.hasPrefix("jp.dialogue.") }
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.romaji == nil })
        #expect(lines.contains { $0.hint?.hasHelp == true })
    }

    @Test("with speaking off, the lines to pick from are in romaji too")
    func picking() {
        let picks = practice(store(readsKana: false, speaking: false)).questions.filter { $0.instruction.contains("would you say") }
        #expect(!picks.isEmpty)
        for pick in picks {
            #expect(pick.choices.allSatisfy { $0.allSatisfy(\.isASCII) }, "\(pick.choices)")
        }
    }

    @Test("telling written forms apart waits for the first hiragana, as readings do")
    func writtenForms() {
        let questions = practice(store(readsKana: false)).questions
        #expect(!questions.contains { $0.instruction == "Which is it written?" || $0.instruction == "Which spells it?" })
    }

    @Test("a dialogue's first run starts by teaching each line of yours: its English, then heard, then repeated")
    func phrases() throws {
        let tasks = practice(store(readsKana: false)).tasks
        let taught = tasks.prefix { $0.instruction == "Repeat after me" }
        let dialogue = try #require(Dialogues.dialogues(.japanese).first { tasks.first?.key == $0.key })
        let yours = dialogue.lines.filter { $0.speaker == .you }
        #expect(taught.map(\.answer) == yours.map(\.text))
        for (task, line) in zip(taught, yours) {
            #expect(task.gloss == line.english)
            #expect(task.prompt == .audio(line.text, .japanese))
            #expect(task.romaji == line.romaji)
        }
        #expect(tasks.dropFirst(taught.count).first?.key == dialogue.key, "then the conversation, with phrases it has taught")
    }

    @Test("phrases are taught once: a dialogue that's been run through goes straight to the conversation")
    func phrasesOnce() throws {
        var store = store(readsKana: false)
        for dialogue in Dialogues.dialogues(.japanese) {
            let now = Fixtures.monday.date()
            let attempt = Attempt(key: dialogue.key, kind: .learn, correct: true, seconds: 5, at: now)
            store.sessions.append(
                StudySession(purpose: .regular, start: now, plannedMinutes: 25, domains: [.japanese], planned: true, attempts: [attempt]))
        }
        #expect(!practice(store).tasks.contains { $0.instruction == "Repeat after me" })
    }

    @Test("nothing's repeated with speaking off, or once \"Can't speak now\" is tapped")
    func phrasesMuted() {
        #expect(!practice(store(readsKana: false, speaking: false)).tasks.contains { $0.instruction == "Repeat after me" })
        let state = store(readsKana: false).state(on: day)
        let catalogs = Fixtures.catalogs(deck)
        var run = StudyRun(plan: SessionPlanner.block(.japanese, state: state, catalogs: catalogs), state: state, catalogs: catalogs, now: state.now)
        var driver = Driver(student: Student(vocabulary: 30, mathsLevel: 0, writingLevel: 0, deck: deck))
        driver.speak = { _ in .skip }
        driver.run(&run, from: state.now)
        #expect(driver.tasks.filter { $0.instruction == "Repeat after me" }.count == 1)
    }

    @Test("a line's romaji goes once every kana in it is mastered")
    func fades() throws {
        let line = try #require(Dialogues.dialogues(.japanese).flatMap(\.lines).first { $0.text == "はい、どうぞ。" })
        #expect(Scaffolds.romaji(line, Scaffolds.Context(cards: [:], frontier: 0, readsKana: false)) == "Hai, douzo.")
        #expect(Scaffolds.romaji(line, Scaffolds.Context(cards: [:], frontier: 0, readsKana: true)) == nil)
        let now = Fixtures.monday.date()
        var cards: [CardKey: MemoryCard] = [:]
        for kana in KanaTable.all {
            cards[kana.key] = MemoryCard(key: kana.key, memory: Memory(stability: 30, difficulty: 5, lastReview: now, due: now), introduced: now)
        }
        #expect(Scaffolds.romaji(line, Scaffolds.Context(cards: cards, frontier: 0, readsKana: false)) == nil)
    }

    @Test("the hand-written romaji of every line of yours says the line's kana, spaces and particles aside")
    func romajiMatchesKana() throws {
        func fold(_ text: String) -> String {
            text.lowercased().filter(\.isLetter).replacingOccurrences(of: "wa", with: "ha").replacingOccurrences(of: "wo", with: "o")
        }
        let lines = Dialogues.dialogues(.japanese).flatMap(\.lines).filter { $0.speaker == .you }
        #expect(!lines.isEmpty)
        for line in lines {
            let written = try #require(line.romaji, "\(line.text)")
            let kana = (line.reading ?? line.text).filter { $0 != "。" && $0 != "、" }
            // The table has no small ぇ, so ソフトウェア can't be spelled out here.
            guard !kana.contains("ぇ") else { continue }
            let table = try #require(KanaTable.romaji(kana), "\(line.text)")
            #expect(fold(written) == fold(table), "\(line.text)")
        }
    }
}
