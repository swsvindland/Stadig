import Foundation
import MindEngine
import Testing

/// The TeX subset the maths is written in, as MindEngine parses it for MathText: how it parses
/// (what gets drawn) and what VoiceOver says. MindEngine's own MathSourceTests check every string
/// the curriculum writes; these are the cases the app's screens were first checked against.
struct MathSourceTests {
    // MARK: Parsing

    @Test func textAndMathsSplitIntoWordsAndPieces() throws {
        let pieces = MathSource.pieces("Find $x$ when $x + 1 = 4$.")
        try #require(pieces.count == 4)
        guard case .word("Find") = pieces[0], case .math = pieces[1], case .word("when") = pieces[2], case .math(let last) = pieces[3]
        else {
            Issue.record("unexpected pieces: \(pieces)")
            return
        }
        // The full stop stays with the maths, so it can't wrap onto a line of its own.
        #expect(last.last == .atom(".", .text))
    }

    @Test func fractionsScriptsAndRoots() {
        #expect(MathSource.parse(#"\frac{1}{2}"#) == [.fraction([.atom("1", .number)], [.atom("2", .number)])])
        #expect(MathSource.parse("x^{2}_i") == [.scripts(base: [.atom("x", .variable)], sup: [.atom("2", .number)], sub: [.atom("i", .variable)])])
        #expect(MathSource.parse(#"\sqrt{9}"#) == [.root([.atom("9", .number)])])
        #expect(MathSource.parse(#"\binom{5}{3}"#) == [.binom([.atom("5", .number)], [.atom("3", .number)])])
        #expect(MathSource.parse("3.14") == [.atom("3.14", .number)])
        #expect(MathSource.parse("3.").first == .atom("3", .number), "a full stop after a number isn't a decimal point")
    }

    @Test func leftRightAndTextDrawWhatTheySay() {
        #expect(
            MathSource.parse(#"\left(\frac{u}{v}\right)"#) == [
                .atom("(", .symbol), .fraction([.atom("u", .variable)], [.atom("v", .variable)]), .atom(")", .symbol),
            ])
        #expect(
            MathSource.parse(#"12\text{ cm}^2"#) == [
                .atom("12", .number), .scripts(base: [.atom(" cm", .text)], sup: [.atom("2", .number)], sub: nil),
            ])
        #expect(MathSource.parse(#"\bar{x}"#) == [.atom("x", .variable), .atom("\u{0304}", .command("bar"))])
    }

    @Test func brokenSourceDoesntTrap() {
        // Unbalanced braces, a script with nothing after it, a trailing backslash, an unclosed \text.
        #expect(MathSource.parse(#"\frac{1}{2"#) == [.fraction([.atom("1", .number)], [.atom("2", .number)])])
        #expect(MathSource.parse("x^") == [.scripts(base: [.atom("x", .variable)], sup: [], sub: nil)])
        #expect(MathSource.parse(#"2\"#) == [.atom("2", .number)])
        #expect(MathSource.parse(#"\text{cm"#) == [.atom("cm", .text)])
        #expect(MathSource.parse("}}x{") == [.atom("x", .variable)])
        let unclosed = MathSource.pieces("an odd $ count")
        #expect(unclosed.count == 3)
        if case .math = unclosed.last {} else { Issue.record("an unclosed dollar runs to the end as maths") }
    }

    // MARK: VoiceOver

    @Test func mathsIsReadAsWords() {
        #expect(MathSource.spoken(#"$\frac{a}{b}$"#) == "a over b")
        #expect(MathSource.spoken(#"$\bar{x}$"#) == "mean of x")
        #expect(MathSource.spoken(#"$P(A \mid B)$"#) == "P(A given B)")
        #expect(MathSource.spoken("$x^2$") == "x to the power 2")
        #expect(MathSource.spoken(#"$\sqrt{9}$"#) == "square root of 9")
        #expect(MathSource.spoken(#"$\binom{5}{3}$"#) == "5 choose 3")
        #expect(MathSource.spoken(#"$x \pm 1$"#) == "x plus or minus 1")
        #expect(MathSource.spoken(#"$\lim_{x \to 0}$"#) == "limit as x approaches 0")
        #expect(MathSource.spoken(#"$\int_0^1 x$"#) == "integral from 0 to 1 x")
        #expect(MathSource.spoken("Solve $x - 3 = 4$.") == "Solve x minus 3 = 4.")
    }

    @Test func theQuotientRuleTheQuadraticFormulaAndAreasReadCleanly() throws {
        let quotient = try #require(MathCurriculum.topic("product-quotient")).lesson
        let spoken = MathSource.spoken(quotient)
        #expect(spoken.contains("u over v"))
        #expect(spoken.contains("to the power 2"))
        for wrong in ["at most ft", "left", "right", "frac"] { #expect(!spoken.contains(wrong), "\(wrong) in \(spoken)") }

        let formula = MathSource.spoken(#"$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$"#)
        #expect(formula.contains("plus or minus"))
        #expect(formula.contains("square root of"))
        #expect(!words(formula).contains("pm"))

        let area = MathSource.spoken(#"The area is $12\text{ cm}^2$."#)
        #expect(area == "The area is 12 cm to the power 2.")
        #expect(!words(MathSource.spoken(#"$\binom{n}{r}$"#)).contains("binom"))
    }

    /// Every lesson, prompt, choice and worked step in the curriculum, with a few seeds each, and
    /// every numeracy level: nothing TeX is ever read out.
    @Test func noTeXIsReadOutAnywhereInTheCurriculum() {
        var sources: [String] = []
        for topic in MathCurriculum.topics {
            sources.append(topic.lesson)
            for seed in ["a", "b", "c"] {
                let problem = topic.problem(seed: seed)
                sources += [problem.prompt] + problem.choices + problem.steps
            }
        }
        for skill in NumeracySkill.allCases {
            for level in 1...10 {
                let problem = skill.problem(level: level, seed: "numeracy-\(level)")
                sources += [problem.prompt] + problem.choices + problem.steps
            }
        }
        #expect(sources.count > 500)
        let commands = ["text", "left", "right", "frac", "binom", "sqrt", "pm", "cdot", "ldots", "approx", "infty", "neq", "le", "ge"]
        var bad: [String] = []
        for source in sources {
            let all = MathSource.spoken(source)
            if all.contains(where: { "\\$^_{}".contains($0) }) || all.contains("at most ft") { bad.append(all) }
            // Only the maths: prose is free to say "left" or "right".
            let maths = MathSource.pieces(source).compactMap { piece -> String? in
                if case .math(let nodes) = piece { return MathSource.spoken(nodes) }
                return nil
            }.joined(separator: " ")
            if !Set(words(maths)).isDisjoint(with: commands) { bad.append(maths) }
        }
        #expect(bad.isEmpty, "\(bad.prefix(5))")
    }

    private func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }
}
