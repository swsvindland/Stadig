import Foundation
import Testing
import SystemCore
@testable import MindEngine

@Suite("Maths as drawn and spoken")
struct MathSourceTests {
    /// Everything the maths strands write with inline maths: every topic's lesson, and the
    /// prompts, choices and worked steps of its problems (with and without the person's data), and
    /// numeracy's at every level.
    static func curriculumStrings() -> [String] {
        var out: [String] = []
        let data = MathsTests.sampleData(ending: Fixtures.monday)
        func add(_ problem: Problem?) {
            guard let problem else { return }
            out += [problem.prompt] + problem.choices + problem.steps
        }
        for topic in MathCurriculum.topics {
            out.append(topic.lesson)
            for seed in 0..<60 {
                add(topic.problem(seed: "\(seed)"))
                add(topic.personalProblem(seed: "\(seed)", data: data))
            }
        }
        for skill in NumeracySkill.allCases {
            for level in 1...10 {
                for seed in 0..<30 { add(skill.problem(level: level, seed: "\(seed)")) }
            }
        }
        return out
    }

    @Test("every curriculum string parses: its maths closed, every command known, and nothing of the TeX left in what VoiceOver reads")
    func curriculumParses() {
        let strings = Self.curriculumStrings()
        #expect(strings.count > 10_000)
        var failures: [String] = []
        for source in Set(strings) {
            let spoken = MathSource.spoken(source)
            let unknown = MathSource.unknownCommands(source)
            if source.filter({ $0 == "$" }).count % 2 != 0 || !unknown.isEmpty || spoken.contains(where: { "\\{}^_$".contains($0) }) {
                failures.append("\(source) → \(spoken) \(unknown)")
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(10).joined(separator: "\n"))")
    }

    @Test("\\left( reads as an opening bracket, not as \\le followed by 'ft'")
    func brackets() {
        let spoken = MathSource.spoken(#"Quotient: $\left(\frac{u}{v}\right)' = \frac{u'v - uv'}{v^{2}}$."#)
        #expect(spoken == "Quotient: ( u over v) prime = u prime v minus uv prime over v to the power 2.", "\(spoken)")
        #expect(!spoken.contains("at most") && !spoken.contains("left") && !spoken.contains("right"))
        #expect(MathSource.unknownCommands(#"$\left(x\right)$"#).isEmpty)
        #expect(MathSource.unknownCommands(#"$\alpha + \beta$"#) == ["alpha", "beta"])
    }

    @Test("\\text, \\pm, \\approx and \\binom read as words; a thin space keeps a number whole")
    func words() {
        #expect(MathSource.spoken(#"mean $\pm 2 \times \frac{s}{\sqrt{n}}$?"#) == "mean plus or minus 2 times s over square root of n?")
        #expect(MathSource.spoken(#"$\text{BMI} \approx 24.5$"#) == "BMI approximately 24.5")
        #expect(MathSource.spoken(#"A team of 3 from 5 people is $\binom{5}{3} = 10$."#) == "A team of 3 from 5 people is 5 choose 3 = 10.")
        #expect(MathSource.spoken(#"about $86\,000$."#) == "about 86000.")
        #expect(MathSource.spoken(#"$1\,234\,567$"#) == "1234567")
        #expect(MathSource.spoken(#"$\int x\,dx$"#) == "integral x dx", "a thin space anywhere else is still a space")
        #expect(MathSource.spoken(#"$\bar{x} = 4$, $P(A \mid B)$"#) == "mean of x = 4, P(A given B)")
        #expect(MathSource.spoken(#"$x^{2} - 3x$"#) == "x to the power 2 minus 3x")
        #expect(MathSource.spoken(#"$\int_{0}^{2} x \, dx$ and $\lim_{x \to 0}$"#) == "integral from 0 to 2 x dx and limit as x approaches 0")
    }

    @Test("pieces: words wrap, maths stays whole, and punctuation after maths stays with it")
    func pieces() {
        let pieces = MathSource.pieces("Solve $x = 4$. Then stop")
        #expect(pieces.count == 4)
        guard case .word("Solve") = pieces[0], case .math(let nodes) = pieces[1], case .word("Then") = pieces[2] else {
            Issue.record("\(pieces)")
            return
        }
        #expect(nodes.last == .atom(".", .text))
        #expect(MathSource.parse(#"\frac{1}{2}"#) == [.fraction([.atom("1", .number)], [.atom("2", .number)])])
        #expect(MathSource.parse(#"\frac{1}{2}"#).first?.isTall == true && MathSource.parse("x^{2}").first?.isTall == false)
    }
}
