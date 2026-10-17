import Foundation

/// One maths problem. Text with inline maths between dollar signs, in a small TeX subset the app
/// draws natively: \frac, \sqrt, ^{}, _{}, \pi, \theta, \times, \div, \cdot, \le, \ge, \pm, \infty,
/// \to, \int, \lim, \sin, \cos, \tan, \ln, \log.
public struct Problem: Hashable, Sendable {
    public var topic: String
    public var prompt: String
    public var answer: Answer
    /// TeX choices when the answer is a choice.
    public var choices: [String]
    /// The worked solution, shown after answering.
    public var steps: [String]
    public var expectedSeconds: Double

    init(prompt: String, answer: Answer, choices: [String] = [], steps: [String]) {
        topic = ""
        self.prompt = prompt
        self.answer = answer
        self.choices = choices
        self.steps = steps
        expectedSeconds = 30
    }

    static func number(_ prompt: String, _ value: Rational, steps: [String], tolerance: Double = 0) -> Problem {
        Problem(prompt: prompt, answer: .number(value, tolerance: tolerance), steps: steps)
    }

    static func number(_ prompt: String, _ value: Int, steps: [String]) -> Problem {
        number(prompt, Rational(value), steps: steps)
    }

    /// Multiple choice from the right answer and plausible slips; duplicates are dropped and the
    /// order shuffled.
    static func choice(_ prompt: String, correct: String, wrong: [String], steps: [String], rng: inout SeededRandom) -> Problem {
        var options = [correct]
        for option in wrong where !options.contains(option) {
            options.append(option)
            if options.count == 4 { break }
        }
        options.shuffle(using: &rng)
        return Problem(prompt: prompt, answer: .choice(options.firstIndex(of: correct)!), choices: options, steps: steps)
    }

    public func question(kind: AttemptKind, id: String) -> Question {
        Question(id: id, key: .topic(topic), kind: kind, instruction: choices.isEmpty ? "Type the answer" : "Choose the answer",
                 prompt: .math(prompt), choices: choices, choiceStyle: .math, answer: answer, expectedSeconds: expectedSeconds,
                 reveal: .steps(steps))
    }
}

/// A topic in the skill graph: what it teaches, what it builds on, and endless problems for it.
public struct MathTopic: Sendable, Identifiable {
    public let id: String
    public let title: String
    /// 1 (arithmetic) to 10 (integration techniques).
    public let level: Int
    public let prerequisites: [String]
    public let lesson: String
    /// About how long a problem takes someone who knows the topic.
    public let seconds: Double
    let make: @Sendable (inout SeededRandom) -> Problem

    public var key: CardKey { .topic(id) }
    public var info: MathTopicInfo { MathTopicInfo(id: id, title: title, lesson: lesson) }

    public func problem(seed: String) -> Problem {
        var rng = SeededRandom("maths", id, seed)
        var problem = make(&rng)
        problem.topic = id
        problem.expectedSeconds = seconds
        return problem
    }
}

// MARK: TeX helpers

enum TeX {
    /// A polynomial from coefficients by power (index 0 is the constant): [5, -3, 2] is 2x² − 3x + 5.
    static func poly(_ coefficients: [Int], _ x: String = "x") -> String {
        var terms: [(Int, String)] = []
        for power in stride(from: coefficients.count - 1, through: 0, by: -1) {
            let c = coefficients[power]
            guard c != 0 else { continue }
            let variable = power == 0 ? "" : power == 1 ? x : "\(x)^{\(power)}"
            let magnitude = abs(c) == 1 && power > 0 ? "" : "\(abs(c))"
            terms.append((c, magnitude + variable))
        }
        return join(terms)
    }

    /// Like `poly`, with fraction coefficients.
    static func poly(_ coefficients: [Rational], _ x: String = "x") -> String {
        var terms: [(Int, String)] = []
        for power in stride(from: coefficients.count - 1, through: 0, by: -1) {
            let c = coefficients[power]
            guard c != 0 else { continue }
            let variable = power == 0 ? "" : power == 1 ? x : "\(x)^{\(power)}"
            let magnitude = Rational(abs(c.numerator), c.denominator)
            let written = magnitude == 1 && power > 0 ? "" : magnitude.tex
            terms.append((c.numerator, written + variable))
        }
        return join(terms)
    }

    /// Signed terms joined: [(1, "2x"), (-1, "5")] is 2x − 5.
    static func join(_ terms: [(Int, String)]) -> String {
        guard let first = terms.first else { return "0" }
        var out = (first.0 < 0 ? "-" : "") + first.1
        for term in terms.dropFirst() { out += (term.0 < 0 ? " - " : " + ") + term.1 }
        return out
    }

    /// ax + b.
    static func linear(_ a: Int, _ b: Int, _ x: String = "x") -> String { poly([b, a], x) }

    /// ax + by.
    static func twoVariable(_ a: Int, _ b: Int) -> String {
        join([(a, (abs(a) == 1 ? "" : "\(abs(a))") + "x"), (b, (abs(b) == 1 ? "" : "\(abs(b))") + "y")])
    }

    /// (x + 3) or (x - 3).
    static func factor(_ root: Int, _ x: String = "x") -> String { root < 0 ? "(\(x) - \(-root))" : "(\(x) + \(root))" }

    /// A number in brackets when it's negative: 3 or (-3).
    static func paren(_ n: Int) -> String { n < 0 ? "(\(n))" : "\(n)" }
    static func paren(_ n: Rational) -> String { n < 0 ? "(\(n.tex))" : n.tex }

    /// "+ 3" or "- 3".
    static func signed(_ n: Int) -> String { n < 0 ? "- \(-n)" : "+ \(n)" }
}
