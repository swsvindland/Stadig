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
    /// A small chart the problem is about, when it has one.
    public var figure: DataFigure?

    init(prompt: String, answer: Answer, choices: [String] = [], steps: [String], figure: DataFigure? = nil) {
        topic = ""
        self.prompt = prompt
        self.answer = answer
        self.choices = choices
        self.steps = steps
        expectedSeconds = 30
        self.figure = figure
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
                 reveal: .steps(steps), figure: figure)
    }

    /// The same problem with its chart.
    func with(_ figure: DataFigure) -> Problem {
        var problem = self
        problem.figure = figure
        return problem
    }
}

/// A topic in a strand's skill graph: what it teaches, what it builds on, and endless problems
/// for it.
public struct MathTopic: Sendable, Identifiable {
    public let id: String
    public let title: String
    /// 1 to 10 within its strand: arithmetic to integration techniques on the classic ladder,
    /// reading a chart to least squares in statistics and logic.
    public let level: Int
    public let prerequisites: [String]
    public let lesson: String
    /// About how long a problem takes someone who knows the topic.
    public let seconds: Double
    public let strand: MathsStrand
    let make: @Sendable (inout SeededRandom) -> Problem
    /// A problem about the person's own numbers, when the System apps have published enough.
    private(set) var personal: (@Sendable (inout SeededRandom, SystemData) -> Problem?)?

    init(id: String, title: String, level: Int, prerequisites: [String], lesson: String, seconds: Double,
         strand: MathsStrand = .classic, make: @escaping @Sendable (inout SeededRandom) -> Problem) {
        self.id = id
        self.title = title
        self.level = level
        self.prerequisites = prerequisites
        self.lesson = lesson
        self.seconds = seconds
        self.strand = strand
        self.make = make
    }

    /// The same topic, drawing on the person's data about half the time it can.
    func withData(_ make: @escaping @Sendable (inout SeededRandom, SystemData) -> Problem?) -> MathTopic {
        var topic = self
        topic.personal = make
        return topic
    }

    public var key: CardKey { .topic(id) }
    public var info: MathTopicInfo { MathTopicInfo(id: id, title: title, lesson: lesson) }
    public var usesData: Bool { personal != nil }

    /// A problem for the topic. With the person's data, about half are about their own week.
    public func problem(seed: String, data: SystemData = .none) -> Problem {
        var rng = SeededRandom("maths", id, seed)
        var problem: Problem?
        if let personal, !data.isEmpty, rng.chance(0.5) { problem = personal(&rng, data) }
        var made = problem ?? make(&rng)
        made.topic = id
        made.expectedSeconds = seconds * (made.figure == nil ? 1 : 1.2)
        return made
    }

    /// Only a problem about the person's data, or nil when there isn't enough of it.
    public func personalProblem(seed: String, data: SystemData) -> Problem? {
        var rng = SeededRandom("maths", id, "personal", seed)
        guard var problem = personal?(&rng, data) else { return nil }
        problem.topic = id
        problem.expectedSeconds = seconds * (problem.figure == nil ? 1 : 1.2)
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
