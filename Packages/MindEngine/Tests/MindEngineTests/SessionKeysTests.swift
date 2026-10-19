import Foundation
import SystemCore
import Testing

@testable import MindEngine

/// The session's keyboard: which key does what on each step, and that typing an answer never sets
/// off a shortcut.
struct SessionKeysTests {
    func question(
        choices: Int = 4, kind: AttemptKind = .review, prompt: Prompt = .text("What is 2 + 2?"), dontKnow: Bool = false,
        figure: DataFigure? = nil
    ) -> Question {
        Question(
            id: "q", key: .topic("arithmetic"), kind: kind, instruction: "Choose", prompt: prompt,
            choices: (1...max(1, choices)).map { "Choice \($0)" }, answer: choices > 0 ? .choice(2) : .number(Rational(4)),
            allowsDontKnow: dontKnow, expectedSeconds: 8, figure: figure)
    }

    func typedQuestion(dontKnow: Bool = true) -> Question {
        Question(
            id: "q", key: .topic("arithmetic"), kind: .test, instruction: "Work it out", prompt: .math("$2 + 2$"),
            answer: .number(Rational(4)), allowsDontKnow: dontKnow, expectedSeconds: 8)
    }

    func feedback(_ question: Question) -> StudyRun.Feedback {
        StudyRun.Feedback(question: question, correct: true, skipped: false, chosen: 2, typed: nil)
    }

    func actions(_ bindings: [SessionKeyBinding]) -> Set<SessionKey> { Set(bindings.map(\.action)) }

    func task(source: String? = nil, notes: String? = nil, exercise: WritingExercise = .prompt, reviewing: UUID? = nil) -> WritingTask {
        WritingTask(
            id: "w", exercise: exercise, instruction: "Write about the last shift.", source: source, notes: notes, minutes: 8,
            reviewing: reviewing)
    }

    func piece() -> WritingPiece {
        WritingPiece(date: Date(timeIntervalSince1970: 0), exercise: .prompt, writingKind: .creative, prompt: "A prompt", text: "Some words.")
    }

    @Test func digitsPickTheChoicesInTheOrderShown() throws {
        let bindings = SessionKeys.bindings(step: .question(question(choices: 4)), feedback: nil)
        let picks = bindings.filter { if case .choose = $0.action { true } else { false } }
        #expect(picks.map(\.label) == ["1", "2", "3", "4"])
        #expect(picks.map(\.action) == [.choose(0), .choose(1), .choose(2), .choose(3)])
        #expect(picks.allSatisfy { $0.modifiers.isEmpty })
        #expect(SessionKeys.label(choice: 0) == "1")
        #expect(SessionKeys.label(choice: 8) == "9")
        #expect(SessionKeys.label(choice: 9) == nil, "a tenth choice has no key")
        let many = SessionKeys.bindings(step: .question(question(choices: 12)), feedback: nil)
        #expect(many.filter { if case .choose = $0.action { true } else { false } }.count == 9)
        // No Return before answering a multiple-choice question: there's nothing to check.
        #expect(!actions(bindings).contains(.submit))
    }

    @Test func returnMovesOnOnceAnsweredExceptFromATest() {
        let review = question()
        #expect(actions(SessionKeys.bindings(step: .question(review), feedback: feedback(review))) == [.submit])
        let test = question(kind: .test)
        #expect(SessionKeys.bindings(step: .question(test), feedback: feedback(test)).isEmpty, "a test moves on by itself")
        #expect(SessionKeys.label(for: .submit, in: SessionKeys.bindings(step: nil, feedback: nil)) == "↩", "Done on the summary")
    }

    @Test func dontKnowIsOfferedOnlyWhereTheQuestionIs() {
        #expect(!actions(SessionKeys.bindings(step: .question(question()), feedback: nil)).contains(.dontKnow))
        let bindings = SessionKeys.bindings(step: .question(question(kind: .test, dontKnow: true)), feedback: nil)
        #expect(bindings.filter { $0.action == .dontKnow }.map(\.label) == ["?", "⌘D"])
    }

    @Test func typingNeverSetsOffAPlainKey() {
        // A typed answer: Return, digits, Space and ? all go into the field; only ⌘ keys stay.
        let typing = SessionKeys.bindings(step: .question(typedQuestion()), feedback: nil, typing: true)
        #expect(typing.map(\.label) == ["⌘D"])
        let notTyping = SessionKeys.bindings(step: .question(typedQuestion()), feedback: nil, typing: false)
        #expect(actions(notTyping) == [.submit, .dontKnow], "with the field put aside, Return checks")

        let say = SpeakingTask(
            id: "s", key: .practice(.spanish, "sentence"), language: .spanish, kind: .review, mode: .write, instruction: "Write what you hear",
            prompt: .audio("Hola", .spanish), expected: ["hola"], expectedSeconds: 6)
        let writing = SessionKeys.bindings(step: .speak(say), feedback: nil, typing: true)
        #expect(writing.isEmpty, "no replay on Space or R while writing the answer")
        #expect(actions(SessionKeys.bindings(step: .speak(say), feedback: nil)) == [.submit, .replay, .replaySlowly])

        for step in [
            StudyRun.Step.compose(task()),
            .reflect(Book(title: "Dune", author: "Frank Herbert", tier: 4, pages: 600, genres: [.sciFi], status: .reading), finished: false),
        ] {
            let bindings = SessionKeys.bindings(step: step, feedback: nil, typing: true, canHandIn: true)
            #expect(bindings.map(\.label) == ["⌘↩"], "\(step)")
            #expect(SessionKeys.bindings(step: step, feedback: nil, typing: true, canHandIn: false).isEmpty, "nothing to hand in yet")
        }
    }

    @Test func replayIsForWhatCanBeHeard() {
        let heard = question(prompt: .audio("ねこ", .japanese))
        let bindings = SessionKeys.bindings(step: .question(heard), feedback: nil)
        #expect(bindings.filter { $0.action == .replay }.map(\.label) == ["Space", "R"])
        #expect(bindings.filter { $0.action == .replaySlowly }.map(\.label) == ["⌥R"])
        #expect(actions(SessionKeys.bindings(step: .question(heard), feedback: feedback(heard))).contains(.replay), "and after answering")
        #expect(!actions(SessionKeys.bindings(step: .question(question()), feedback: nil)).contains(.replay))
        let kana = Kana(kana: "あ", romaji: "a", script: .hiragana, group: 0)
        #expect(actions(SessionKeys.bindings(step: .lesson(.kana(kana)), feedback: nil)) == [.submit, .replay, .replaySlowly])
        let skill = WritingSkill(id: "commas", title: "Commas", level: 1, lesson: "Lists take commas.", example: "Red, green and blue.")
        #expect(actions(SessionKeys.bindings(step: .lesson(.skill(skill)), feedback: nil)) == [.submit])
    }

    @Test func comparisonsAndBooksAreChosenByKey() {
        let pair = BlindPair(id: "p", first: piece(), second: piece(), prompt: "Which is stronger?")
        let compare = SessionKeys.bindings(step: .compare(pair), feedback: nil)
        #expect(compare.map(\.label) == ["A", "B"])
        #expect(compare.map(\.action) == [.pick(0), .pick(1)])
        let books = Array(ReadingLadder.standard.books.prefix(3))
        #expect(actions(SessionKeys.bindings(step: .pickBook(books), feedback: nil)) == [.choose(0), .choose(1), .choose(2)])
        #expect(actions(SessionKeys.bindings(step: .compose(task(reviewing: UUID())), feedback: nil)) == [.submit], "Done after the notes")
    }

    @Test func noKeyIsBoundTwiceOnAStep() {
        let pair = BlindPair(id: "p", first: piece(), second: piece(), prompt: "Which?")
        let steps: [(StudyRun.Step?, StudyRun.Feedback?)] = [
            (.question(question(kind: .test, prompt: .audio("ねこ", .japanese), dontKnow: true)), nil),
            (.question(question(choices: 12)), nil),
            (.question(typedQuestion()), nil),
            (.compare(pair), nil),
            (.compose(task(reviewing: UUID())), nil),
            (nil, nil),
        ]
        for (step, feedback) in steps {
            let bindings = SessionKeys.bindings(step: step, feedback: feedback, canHandIn: true)
            let keys = bindings.map { "\($0.key)\($0.modifiers.rawValue)" }
            #expect(Set(keys).count == keys.count, "\(String(describing: step))")
        }
    }

    @Test func wideWindowsPutLongPromptsAndSourcesBeside() {
        #expect(!SessionLayout.sideBySide(question(prompt: .foreign("猫", .japanese))), "a word stays over its choices")
        #expect(!SessionLayout.sideBySide(question(prompt: .audio("ねこ", .japanese))))
        #expect(!SessionLayout.sideBySide(question(prompt: .text("Which word means cat?"))))
        let story = String(repeating: "A train leaves at nine and travels at sixty miles an hour. ", count: 3)
        #expect(SessionLayout.sideBySide(question(prompt: .text(story))))
        let week = DataFigure(title: "Steps", unit: "steps", points: [.init(label: "Mon", value: 9000)])
        #expect(SessionLayout.sideBySide(question(prompt: .text("Which day was busiest?"), figure: week)), "a chart sits beside")

        #expect(!SessionLayout.sideBySide(task()), "a prompt alone sits above the editor")
        #expect(SessionLayout.sideBySide(task(source: "Hi, can u send the thing", exercise: .practical)))
        #expect(SessionLayout.sideBySide(task(source: "The original", notes: "my notes", exercise: .franklinRewrite)), "the notes, not the original")
        #expect(!SessionLayout.sideBySide(task(source: "The original", exercise: .franklinRewrite)), "a rewrite works from notes alone")
        #expect(!SessionLayout.sideBySide(task(source: "Hi", exercise: .practical, reviewing: UUID())), "the review lays itself out")
    }
}
