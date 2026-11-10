import Foundation

/// A small, fast, seedable generator (SplitMix64), so a question built for a card on a day is the
/// same on every device and in every test.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public init(_ parts: String...) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in parts.joined(separator: "|").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        state = hash
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    public mutating func nonZero(_ range: ClosedRange<Int>) -> Int {
        var value = 0
        while value == 0 { value = int(range) }
        return value
    }
    public mutating func pick<T>(_ items: [T]) -> T { items[Int.random(in: 0..<items.count, using: &self)] }
    public mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
}

/// What's shown above the answers.
public enum Prompt: Hashable, Sendable {
    case text(String)
    /// The language shown large, with a scaffold (furigana, romaji) underneath while it's needed.
    case foreign(String, Language, reading: String? = nil)
    /// The language spoken in its own voice, not shown, until it's answered.
    case audio(String, Language)
    /// The language with its fading scaffold: furigana, romaji or a stress guide on each item not
    /// yet mastered.
    case scaffolded(Scaffolded)
    /// Text with inline maths between dollar signs: "Solve $3x + 5 = 20$".
    case math(String)
}

/// How the choices are written.
public enum ChoiceStyle: String, Hashable, Sendable {
    case text, math
    /// In the language being learned.
    case foreign
    /// Pictures: each choice is an SF Symbol name (picture matching).
    case picture
}

public enum Answer: Hashable, Sendable {
    case choice(Int)
    /// A number typed in: exact for fractions, within `tolerance` for decimals.
    case number(Rational, tolerance: Double)

    public static func number(_ value: Rational) -> Answer { .number(value, tolerance: 0) }
}

/// Something to learn before it's asked.
public enum Lesson: Hashable, Sendable {
    case word(Word, kanji: [Kanji], example: Sentence?)
    case kana(Kana)
    case topic(MathTopicInfo, example: Problem)
    case skill(WritingSkill)
}

public struct MathTopicInfo: Hashable, Sendable {
    public var id: String
    public var title: String
    public var lesson: String
}

/// What's shown after answering, beyond right or wrong.
public enum Reveal: Hashable, Sendable {
    case word(Word, kanji: [Kanji])
    case sentence(Sentence, Language)
    case steps([String])
    case note(String)
}

public struct Question: Hashable, Sendable, Identifiable {
    public var id: String
    public var key: CardKey
    public var kind: AttemptKind
    public var instruction: String
    public var prompt: Prompt
    public var choices: [String]
    public var choiceStyle: ChoiceStyle
    public var answer: Answer
    /// Tests offer "Don't know", so a guess isn't counted as knowing.
    public var allowsDontKnow: Bool
    /// Typical time for someone who knows it, for grading speed.
    public var expectedSeconds: Double
    public var reveal: Reveal?
    public var test: TestKind?
    public var band: Int?
    /// A small chart shown with the prompt (a statistics problem about your week, say).
    public var figure: DataFigure?
    /// Scored on speed as well as accuracy (numeracy): a right answer moves straight on.
    public var timed: Bool
    /// How a maths problem is meant to be worked; nil outside maths.
    public var tool: MathsTool?

    public init(
        id: String, key: CardKey, kind: AttemptKind, instruction: String, prompt: Prompt, choices: [String] = [],
        choiceStyle: ChoiceStyle = .text, answer: Answer, allowsDontKnow: Bool = false, expectedSeconds: Double,
        reveal: Reveal? = nil, test: TestKind? = nil, band: Int? = nil, figure: DataFigure? = nil, timed: Bool = false,
        tool: MathsTool? = nil
    ) {
        self.id = id
        self.key = key
        self.kind = kind
        self.instruction = instruction
        self.prompt = prompt
        self.choices = choices
        self.choiceStyle = choiceStyle
        self.answer = answer
        self.allowsDontKnow = allowsDontKnow
        self.expectedSeconds = expectedSeconds
        self.reveal = reveal
        self.test = test
        self.band = band
        self.figure = figure
        self.timed = timed
        self.tool = tool
    }

    public var correctChoice: Int? {
        if case .choice(let i) = answer { return i }
        return nil
    }

    /// Whether a typed answer is right: any equal value ("6/8" for 3/4), or within the tolerance.
    public func check(typed: String) -> Bool {
        guard case .number(let value, let tolerance) = answer, let given = Rational(parsing: typed) else { return false }
        if tolerance > 0 { return abs(given.double - value.double) <= tolerance }
        return given == value
    }

    /// Builds a multiple-choice question from a right answer and wrong ones, in a shuffled order.
    public static func choosing(
        id: String, key: CardKey, kind: AttemptKind, instruction: String, prompt: Prompt, correct: String,
        wrong: [String], style: ChoiceStyle = .text, expectedSeconds: Double, reveal: Reveal? = nil,
        rng: inout SeededRandom
    ) -> Question {
        var seen: Set<String> = [normalised(correct)]
        var options = [correct]
        for option in wrong where seen.insert(normalised(option)).inserted {
            options.append(option)
            if options.count == 4 { break }
        }
        options.shuffle(using: &rng)
        return Question(
            id: id, key: key, kind: kind, instruction: instruction, prompt: prompt, choices: options, choiceStyle: style,
            answer: .choice(options.firstIndex(of: correct)!), expectedSeconds: expectedSeconds, reveal: reveal)
    }

    static func normalised(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
