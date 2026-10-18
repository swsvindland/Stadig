import Foundation
import SystemCore

/// The passages the reading test draws on: several at each tier, public domain or written for
/// Mind Track, each with its comprehension questions.
public struct PassageBank: Sendable {
    public var passages: [Passage]

    public init(passages: [Passage]) { self.passages = passages }

    private struct File: Decodable { var passages: [Passage] }

    public static let standard: PassageBank = {
        guard let url = Bundle.module.url(forResource: "passages", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            mindLog.error("The reading test's passages are missing")
            return PassageBank(passages: [])
        }
        do {
            return PassageBank(passages: try JSONDecoder().decode(File.self, from: data).passages)
        } catch {
            mindLog.error("The reading test's passages are unreadable: \(String(describing: error))")
            return PassageBank(passages: [])
        }
    }()

    public func passages(tier: Int, language: Language? = nil) -> [Passage] {
        passages.filter { $0.tier == tier && $0.language == language }
    }

    public func passage(_ id: String) -> Passage? { passages.first { $0.id == id } }
}

/// The reading test: short passages, each a little harder or easier depending on the last, read
/// silently and timed in the background, then two or three questions apiece. A staircase: up after
/// a passage understood, down after one that wasn't, in steps of two until the first turn, then one.
public struct ReadingTest: Hashable, Sendable {
    public struct Result: Hashable, Sendable {
        public var passage: String
        public var tier: Int
        public var words: Int
        public var seconds: Double
        public var right: Int
        public var asked: Int

        public init(passage: String, tier: Int, words: Int, seconds: Double, right: Int, asked: Int) {
            self.passage = passage
            self.tier = tier
            self.words = words
            self.seconds = seconds
            self.right = right
            self.asked = asked
        }

        public var comprehension: Double { Double(right) / Double(max(1, asked)) }
        public var wordsPerMinute: Double { Double(words) / max(1, seconds) * 60 }
        /// Understood: two of three right (or both of two), read at a pace that isn't a struggle.
        public var passed: Bool { comprehension >= 0.66 && wordsPerMinute >= ReadingTest.slowest }
    }

    /// Slower than this, a passage was hard work even if the questions came out right.
    public static let slowest = 60.0

    public private(set) var results: [Result] = []
    public let start: Int
    public let maxPassages: Int
    public let minPassages: Int
    private var step: Int
    public private(set) var nextTier: Int?

    /// A placement starts from a hint and steps two at a time; a check-in starts at the level and
    /// steps one.
    public init(start: Int, placement: Bool) {
        self.start = clamp(start, 1, 10)
        maxPassages = placement ? 5 : 3
        minPassages = 3
        step = placement ? 2 : 1
        nextTier = self.start
    }

    public var done: Bool { nextTier == nil }

    public mutating func record(_ result: Result) {
        let previous = results.last
        results.append(result)
        if let previous, previous.passed != result.passed { step = 1 }
        let tier = result.tier + (result.passed ? step : -step)
        let bracketed = results.contains { pass in pass.passed && results.contains { !$0.passed && $0.tier == pass.tier + 1 } }
        // One lucky passage at either end isn't enough: the top and bottom are confirmed with a second.
        let ends = results.suffix(2)
        let topped = ends.count == 2 && ends.allSatisfy { $0.passed && $0.tier == 10 }
        let bottomed = ends.count == 2 && ends.allSatisfy { !$0.passed && $0.tier == 1 }
        if results.count >= maxPassages || (results.count >= minPassages && bracketed) || topped || bottomed {
            nextTier = nil
        } else {
            nextTier = clamp(tier, 1, 10)
        }
    }

    /// The level the passages show: the most likely tier given every answer, where a question at a
    /// tier well below the level is nearly always right and one well above it is a guess among four.
    /// Two of three right counts for less than three of three, and answers on a passage read
    /// laboriously slowly count half.
    public static func estimate(_ results: [Result]) -> Double? {
        guard !results.isEmpty else { return nil }
        func chance(_ tier: Int, _ level: Double) -> Double { 0.25 + 0.72 / (1 + exp(-2 * (level - Double(tier) + 0.5))) }
        var best = (level: 1.0, likelihood: -Double.infinity)
        for step in 0...90 {
            let level = 1 + Double(step) / 10
            let likelihood = results.map { result -> Double in
                let p = chance(result.tier, level)
                let right = Double(result.right) * (result.wordsPerMinute >= slowest ? 1 : 0.5)
                return right * log(p) + (Double(result.asked) - right) * log(1 - p)
            }.reduce(0, +)
            if likelihood > best.likelihood + 1e-9 { best = (level, likelihood) }
        }
        return best.level
    }

    /// The test as a result: the level in `tier`, pace and each passage's share right, so the next
    /// test can choose passages not seen before.
    public func result(at date: Date, placement: Bool) -> TestResult? {
        guard let level = Self.estimate(results) else { return nil }
        let asked = results.map(\.asked).reduce(0, +)
        let right = results.map(\.right).reduce(0, +)
        let paced = results.filter(\.passed).isEmpty ? results : results.filter(\.passed)
        let pace = paced.map(\.wordsPerMinute).sorted()[paced.count / 2]
        var detail: [String: Double] = ["tier": level, "wpm": pace.rounded(), "passages": Double(results.count), "start": Double(start)]
        for result in results { detail["passage.\(result.passage)"] = result.comprehension }
        return TestResult(test: .readingTest, date: date, score: Double(right) / Double(max(1, asked)), detail: detail, placement: placement)
    }
}

/// Runs the reading test in a session: a passage, then its questions, then the next passage the
/// staircase asks for, until it's settled or the time is well past.
struct ReadingTestRunner: PartRunner {
    var test: ReadingTest
    let placement: Bool
    let bank: PassageBank
    var current: Passage?
    var readSeconds: Double?
    var queue: [Question] = []
    var right = 0
    var asked = 0
    var used: Set<String> = []

    init(placement: Bool, start: Int, bank: PassageBank = .standard) {
        test = ReadingTest(start: start, placement: placement)
        self.placement = placement
        self.bank = bank
    }

    mutating func next(_ run: inout StudyRun) -> StudyRun.Step? {
        if !queue.isEmpty { return .question(queue.removeFirst()) }
        if current != nil { close() }
        guard let tier = test.nextTier, run.partSeconds < run.budget * 2, let passage = pick(tier, run: run) else { return nil }
        current = passage
        readSeconds = nil
        right = 0
        asked = 0
        used.insert(passage.id)
        return .passage(passage)
    }

    mutating func respond(_ response: StepResponse, _ run: inout StudyRun) -> Bool {
        guard case .passageRead(let seconds) = response, let passage = current, readSeconds == nil else { return false }
        readSeconds = seconds
        queue = Self.questions(passage, seed: run.today.iso)
        return true
    }

    mutating func record(_ question: Question, correct: Bool, _ run: inout StudyRun) {
        guard question.test == .readingTest else { return }
        asked += 1
        if correct { right += 1 }
    }

    mutating func finish(_ run: inout StudyRun) {
        if current != nil, asked >= 2 { close() }
        guard test.results.count >= 2, let result = test.result(at: run.now, placement: placement) else { return }
        run.newTests.append(result)
    }

    /// The passage just read and its answers, into the staircase.
    private mutating func close() {
        if let passage = current, let seconds = readSeconds, asked > 0 {
            test.record(.init(passage: passage.id, tier: passage.tier, words: passage.words, seconds: seconds, right: right, asked: asked))
        }
        current = nil
        readSeconds = nil
    }

    /// A passage at the tier not used in this test, preferring one no earlier test has shown, then
    /// the one shown longest ago.
    func pick(_ tier: Int, run: StudyRun) -> Passage? {
        let earlier = run.tests.filter { $0.test == .readingTest }
        func lastShown(_ passage: Passage) -> Int {
            earlier.lastIndex { $0.detail["passage.\(passage.id)"] != nil } ?? -1
        }
        let options = bank.passages(tier: tier).filter { !used.contains($0.id) }
        return options.min { (lastShown($0), $0.id) < (lastShown($1), $1.id) }
    }

    static func questions(_ passage: Passage, seed: String) -> [Question] {
        var rng = SeededRandom("reading-test", passage.id, seed)
        return passage.questions.enumerated().map { index, item in
            var question = Question.choosing(
                id: "reading.\(passage.id).\(index).\(seed)", key: CardKey("reading.passage.\(passage.id).\(index)"),
                kind: .test, instruction: "About the passage", prompt: .text(item.prompt), correct: item.answer,
                wrong: item.wrong, expectedSeconds: 20, rng: &rng
            ).asTest(.readingTest)
            question.band = passage.tier
            return question
        }
    }
}
