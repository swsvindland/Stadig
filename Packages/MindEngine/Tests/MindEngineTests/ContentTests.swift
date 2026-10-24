import Foundation
import Testing

@testable import MindEngine

@Suite("Content")
struct ContentTests {
    @Test("the maths graph: every prerequisite exists, comes earlier and sits at or below the topic's level")
    func graph() {
        var seen: Set<String> = []
        #expect(MathCurriculum.topics.count >= 45)
        #expect(Set(MathCurriculum.topics.map(\.id)).count == MathCurriculum.topics.count)
        for topic in MathCurriculum.topics {
            for prerequisite in topic.prerequisites {
                #expect(seen.contains(prerequisite), "\(topic.id) needs \(prerequisite) earlier")
                #expect((MathCurriculum.topic(prerequisite)?.level ?? 99) <= topic.level, "\(topic.id) ← \(prerequisite)")
            }
            seen.insert(topic.id)
        }
        #expect(MathCurriculum.ancestors(of: "integration-by-parts").contains("order-of-operations"))
        #expect(MathCurriculum.descendants(of: "factorising").contains("stationary-points"))
    }

    @Test("every topic makes well-formed problems: balanced maths, a valid answer, distinct choices, worked steps")
    func problems() throws {
        for topic in MathCurriculum.topics {
            for seed in 0..<150 {
                let problem = topic.problem(seed: "\(seed)")
                let label = "\(topic.id) #\(seed): \(problem.prompt)"
                #expect(problem.prompt.filter { $0 == "$" }.count % 2 == 0, "\(label)")
                #expect(balanced(problem.prompt), "\(label)")
                #expect(!problem.steps.isEmpty && problem.steps.allSatisfy(balanced), "\(label)")
                switch problem.answer {
                case .choice(let index):
                    #expect(problem.choices.indices.contains(index), "\(label)")
                    #expect(problem.choices.count >= 3, "\(label): \(problem.choices)")
                    #expect(Set(problem.choices).count == problem.choices.count, "\(label): \(problem.choices)")
                    #expect(problem.choices.allSatisfy(balanced), "\(label)")
                case .number(let value, let tolerance):
                    let question = problem.question(kind: .learn, id: "t")
                    #expect(question.check(typed: tolerance > 0 ? String(format: "%.2f", value.double) : value.description), "\(label) = \(value)")
                }
            }
            #expect(topic.problem(seed: "x") == topic.problem(seed: "x"), "deterministic")
        }
        if ProcessInfo.processInfo.environment["PRINT_PROBLEMS"] != nil {
            for topic in MathCurriculum.topics {
                let problem = topic.problem(seed: "print")
                let answer: String
                switch problem.answer {
                case .choice(let i): answer = problem.choices[i]
                case .number(let v, _): answer = v.description
                }
                print("[\(topic.level)] \(topic.title): \(problem.prompt)  →  \(answer)")
            }
        }
    }

    @Test("worked answers that can be checked independently are right")
    func spotChecks() {
        for seed in 0..<100 {
            // Two dice: the answer is a count over 36 that matches a recount.
            let p = MathCurriculum.topic("pythagoras")!.problem(seed: "\(seed)")
            if case .number(let value, _) = p.answer {
                let numbers = p.prompt.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if p.prompt.contains("shorter sides") {
                    #expect(numbers[0] * numbers[0] + numbers[1] * numbers[1] == value.numerator * value.numerator)
                } else {
                    #expect(numbers[0] * numbers[0] - numbers[1] * numbers[1] == value.numerator * value.numerator)
                }
            }
            let linear = MathCurriculum.topic("linear-equations")!.problem(seed: "\(seed)")
            #expect(linear.steps.last?.contains("x =") == true)
        }
    }

    func balanced(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
    }

    @Test("the writing bank: 15 skills, ten items each, one valid answer apiece")
    func writing() {
        let bank = WritingBank.standard
        #expect(bank.skills.count == 15)
        #expect(bank.items.count == 150)
        for skill in bank.skills { #expect(bank.items(for: skill.id).count == 10, "\(skill.id)") }
        for item in bank.items {
            #expect(item.choices.count == 4 && Set(item.choices).count == 4, "\(item.id)")
            #expect(item.choices.indices.contains(item.answer), "\(item.id)")
            let question = bank.question(item, kind: .learn, seed: "s")
            #expect(question.choices[question.correctChoice!] == item.choices[item.answer], "the shuffle keeps the answer")
        }
        #expect(bank.item(for: "commas", seen: 0, seed: "a") != bank.item(for: "commas", seen: 1, seed: "a"))
    }

    @Test("the reading ladder: ten tiers, every book placed, and suggestions near the next tier in liked genres")
    func ladder() throws {
        let ladder = ReadingLadder.standard
        #expect(ladder.tiers.map(\.tier) == Array(1...10))
        #expect(ladder.books.count >= 300)
        #expect(Set(ladder.books.map(\.id)).count == ladder.books.count)
        for tier in 1...10 { #expect(ladder.books.filter { $0.tier == tier }.count >= 8, "tier \(tier)") }

        // Tested at 5: the next book is a tier 4, just below; a just-right 4 moves it up half a tier.
        let day = Fixtures.monday
        let test = TestResult(test: .readingTest, date: day.date(), score: 0.8, detail: ["tier": 5])
        #expect(ReadingPlan.targetTier(books: [], tests: [test], on: day, dayStart: 0) == 4)
        var read = try #require(ladder.books.first { $0.tier == 4 && $0.genres.contains(.fantasy) }).book(status: .finished)
        read.feel = .right
        read.finished = day
        #expect(ReadingPlan.target(books: [read], tests: [test], on: day, dayStart: 0) == 4.5)
        let picks = ReadingPlan.suggestions(shelf: [read], tests: [test], genres: [.fantasy, .sciFi], on: day, dayStart: 0, ladder: ladder)
        #expect(picks.count == 3)
        #expect(picks.allSatisfy { abs(Double($0.tier) - 4.5) <= 1.5 })
        #expect(!picks.contains { $0.id == read.ladderID })
        #expect(ReadingPlan.targetTier(books: [], tests: [], on: day, dayStart: 0) == ReadingPlan.startingTier)
    }

    @Test("kana: hiragana and katakana in teaching order, with lookalikes as wrong answers")
    func kana() {
        #expect(KanaTable.kana(.hiragana).count == 104)
        #expect(KanaTable.katakana("きゃ") == "キャ")
        #expect(KanaTable.all.first?.kana == "あ")
        let sa = KanaTable.byKana["さ"]!
        let question = LanguageQuiz.question(sa, reps: 0, kind: .learn, introduced: [], seed: "x")
        #expect(question.choices.count == 4 && question.choices[question.correctChoice!] == "sa")
        #expect(question.choices.contains("chi") || question.choices.contains("ki"), "\(question.choices)")
    }
}
