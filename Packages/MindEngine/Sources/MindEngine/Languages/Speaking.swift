import Foundation

/// Something to produce in the language: say it out loud (the app listens with on-device speech
/// recognition and hands back what it heard as `.spoken`) or write it (typed, handed back as
/// `.written`). A word, a sentence said back or written down as it's heard, or a reply in a
/// dialogue. The language's runner marks it with `AnswerMatch`.
public struct SpeakingTask: Hashable, Sendable, Identifiable {
    public enum Mode: String, Hashable, Sendable {
        case say, write
    }

    /// What's being produced, which decides how it's marked.
    public enum Shape: Hashable, Sendable {
        /// A word or short phrase: any of `expected` anywhere in the answer.
        case phrase
        /// A sentence: most of its words, or any of `expected` whole.
        case sentence(String, words: [Word])
    }

    public var id: String
    public var key: CardKey
    public var language: Language
    public var kind: AttemptKind
    public var mode: Mode
    public var instruction: String
    /// What it means, shown above a prompt that's played: English, then the language.
    public var gloss: String?
    /// What's shown or played: say this, repeat this, or answer this.
    public var prompt: Prompt
    /// Shown under the prompt as support, fading as the item is mastered: the line to say, in a
    /// dialogue's first run-throughs.
    public var hint: Scaffolded?
    /// The line in romaji for someone who can't read its kana yet: under the hint, and the answer.
    public var romaji: String?
    /// Answers that count, in the language's script.
    public var expected: [String]
    public var shape: Shape
    /// The answer to show afterwards, and its meaning.
    public var answer: String
    public var meaning: String?
    public var expectedSeconds: Double
    public var test: TestKind?
    public var band: Int?

    public init(
        id: String, key: CardKey, language: Language, kind: AttemptKind, mode: Mode = .say, instruction: String, gloss: String? = nil, prompt: Prompt,
        hint: Scaffolded? = nil, romaji: String? = nil, expected: [String], shape: Shape = .phrase, answer: String? = nil, meaning: String? = nil,
        expectedSeconds: Double, test: TestKind? = nil, band: Int? = nil
    ) {
        self.id = id
        self.key = key
        self.language = language
        self.kind = kind
        self.mode = mode
        self.instruction = instruction
        self.gloss = gloss
        self.prompt = prompt
        self.hint = hint
        self.romaji = romaji
        self.expected = expected
        self.shape = shape
        self.answer = answer ?? expected.first ?? ""
        self.meaning = meaning
        self.expectedSeconds = expectedSeconds
        self.test = test
        self.band = band
    }

    /// Whether this answer counts.
    public func check(_ answer: String) -> Bool {
        if AnswerMatch.matches(answer, expected: expected, language: language) { return true }
        if case .sentence(let text, let words) = shape {
            return AnswerMatch.coverage(answer, of: text, words: words, language: language) >= AnswerMatch.sentenceShare
        }
        return false
    }

    /// The task as a question, so the session can show how it went the way it does for any answer.
    var asQuestion: Question {
        Question(
            id: id, key: key, kind: kind, instruction: instruction, prompt: prompt, answer: .choice(0), expectedSeconds: expectedSeconds,
            reveal: .note(meaning.map { "\(answer) · \($0)" } ?? answer), test: test, band: band)
    }
}

extension StudyRun {
    /// Marks a spoken or written answer to a task, logs it and, outside tests, shows how it went.
    /// What was heard rides along as the feedback's typed text. Returns whether it counted.
    @discardableResult
    mutating func mark(_ task: SpeakingTask, answer: String) -> Bool {
        let correct = task.check(answer)
        log(task.key, kind: task.kind, correct: correct, expected: task.expectedSeconds, test: task.test, band: task.band)
        if task.kind != .test {
            feedback = Feedback(question: task.asQuestion, correct: correct, skipped: false, chosen: nil, typed: answer)
        }
        return correct
    }

    /// What the person said or wrote, from either kind of response.
    static func produced(_ response: StepResponse) -> String? {
        switch response {
        case .spoken(let transcript, _): transcript
        case .written(let text, _): text
        default: nil
        }
    }
}
