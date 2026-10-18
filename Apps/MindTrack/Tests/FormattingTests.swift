import Foundation
import MindEngine
import SwiftUI
import SystemCore
import Testing

@testable import MindTrack

/// What handwriting is scored on: Vision's lines put back into paragraphs.
@MainActor
struct TextRecognizerTests {
    /// A line `index` lines down the page, each 0.04 tall with 0.01 between them, `gap` extra lines
    /// of space above it.
    func line(_ text: String, _ index: Double, gap: Double = 0) -> TextRecognizer.Line {
        let top = 0.9 - index * 0.05 - gap * 0.05
        return TextRecognizer.Line(text: text, top: top, bottom: top - 0.04)
    }

    @Test func linesAreReadTopToBottomAndJoined() {
        let lines = [line("over the lazy dog.", 2), line("The quick brown fox", 0), line("jumps", 1)]
        #expect(TextRecognizer.paragraphs(lines) == "The quick brown fox jumps over the lazy dog.")
    }

    @Test func aWiderGapStartsAParagraph() {
        let lines = [
            line("First paragraph,", 0), line("still the first.", 1), line("Second paragraph.", 2, gap: 1.5), line("Its second line.", 3, gap: 1.5),
        ]
        #expect(TextRecognizer.paragraphs(lines) == "First paragraph, still the first.\n\nSecond paragraph. Its second line.")
    }

    @Test func aWordHyphenatedAcrossLinesIsJoined() {
        #expect(TextRecognizer.paragraphs([line("It was an extra-", 0), line("ordinary day.", 1)]) == "It was an extraordinary day.")
        // A capital after the hyphen is a real hyphen (or a name): kept.
        #expect(TextRecognizer.paragraphs([line("the Austro-", 0), line("Hungarian empire", 1)]) == "the Austro- Hungarian empire")
    }

    @Test func blankAndSingleLines() {
        #expect(TextRecognizer.paragraphs([]) == "")
        #expect(TextRecognizer.paragraphs([line("   ", 0)]) == "")
        #expect(TextRecognizer.paragraphs([line("  Just one.  ", 0)]) == "Just one.")
        #expect(TextRecognizer.paragraphs([line("One.", 0), line(" ", 1), line("Two.", 2)]) == "One. Two.")
    }

    @Test func fragmentsOnOneLineStayInOneParagraph() {
        let first = TextRecognizer.Line(text: "Left half", top: 0.9, bottom: 0.86)
        let second = TextRecognizer.Line(text: "right half", top: 0.9, bottom: 0.86)
        let next = line("Next line.", 1)
        let text = TextRecognizer.paragraphs([first, second, next])
        #expect(!text.contains("\n"))
        #expect(text.hasSuffix("Next line."))
    }
}

/// What a missed maths question shows, and when a timed one moves on by itself.
@MainActor
struct QuestionFormattingTests {
    func question(_ key: CardKey, _ answer: Answer, seconds: Double = 8) -> Question {
        Question(id: "q", key: key, kind: .review, instruction: "Work it out", prompt: .math("$x$"), answer: answer, expectedSeconds: seconds)
    }

    @Test func theAnswerShownAfterAMiss() {
        // Numeracy outside fractions shows a decimal: 0.34 kg, not 17/50.
        #expect(question(.numeracy(.percentages, level: 3), .number(Rational(17, 50))).shownAnswer == "0.34")
        #expect(question(.numeracy(.fractions, level: 3), .number(Rational(17, 50))).shownAnswer == #"\frac{17}{50}"#)
        // A third has no decimal that ends: exact.
        #expect(question(.numeracy(.arithmetic, level: 3), .number(Rational(1, 3))).shownAnswer == #"\frac{1}{3}"#)
        #expect(question(.topic("fractions"), .number(Rational(3, 4))).shownAnswer == #"\frac{3}{4}"#)
        #expect(question(.topic("negative"), .number(Rational(-5, 2))).shownAnswer == #"-\frac{5}{2}"#)
        #expect(question(.topic("rounding"), .number(Rational(1, 3), tolerance: 0.01)).shownAnswer == "0.33", "rounded as asked")
        #expect(question(.topic("whole"), .number(Rational(12))).shownAnswer == "12")
        #expect(question(.topic("choice"), .choice(1)).shownAnswer == "")
    }

    @Test func fluentMeansRightInsideTheTargetTime() {
        let timed = question(.numeracy(.arithmetic, level: 2), .number(Rational(7)), seconds: 6)
        #expect(timed.fluent(4))
        #expect(timed.fluent(6))
        #expect(!timed.fluent(6.5))
        #expect(!timed.fluent(nil), "no time kept, no auto-advance")
    }
}

/// The session summary's line for each test, whatever the result carries.
@MainActor
struct TestLineTests {
    let date = TestApp.wednesday

    @Test func everyTestKindHasALine() {
        for kind in TestKind.allCases {
            let bare = TestLine.text(TestResult(test: kind, date: date, score: 0.75, language: .japanese))
            #expect(!bare.isEmpty, "\(kind)")
            // A language skill's level 0 is real (under 100 words' reach); elsewhere it'd be a missing key.
            if LanguageSkills.skill(kind) == nil {
                #expect(!bare.contains("level 0"), "a missing level isn't shown as 0: \(kind) said \(bare)")
            }
            #expect(!bare.contains("tier 0"), "\(kind) said \(bare)")
            #expect(!bare.contains(" 0 words a minute"), "\(kind) said \(bare)")
        }
    }

    @Test func linesWithTheirDetails() {
        #expect(
            TestLine.text(TestResult(test: .vocabulary, date: date, score: 1200, detail: ["low": 900, "high": 1500], language: .japanese))
                == "About 1,200 Japanese words known (900–1,500)")
        #expect(
            TestLine.text(TestResult(test: .numeracy, date: date, score: 0.8, detail: ["level": 6, "seconds": 5.6]))
                == "Numeracy: level 6 of 10 · 80% right, 6 s a problem")
        #expect(TestLine.text(TestResult(test: .numeracy, date: date, score: 0.8)) == "Numeracy: 80% right")
        #expect(
            TestLine.text(TestResult(test: .maths, date: date, score: 0.5, detail: ["level": 4], placement: true)).hasSuffix(
                "placed at level 4 of 10"))
        #expect(
            TestLine.text(TestResult(test: .maths, date: date, score: 0.5, detail: ["reach": 7, "seconds": 30])).hasSuffix(
                "level 7 reached · 50% right, 30 s a problem"))
        #expect(
            TestLine.text(TestResult(test: .readingTest, date: date, score: 0.9, detail: ["tier": 6, "wpm": 240])).hasPrefix("Reading test: tier 6"))
        #expect(TestLine.text(TestResult(test: .readingTest, date: date, score: 0.9)) == "Reading test done")
        #expect(
            TestLine.text(TestResult(test: .episode, date: date, score: 2.0 / 3, language: .japanese))
                == "Japanese episode without subtitles: followed most")
        #expect(TestLine.text(TestResult(test: .blindComparison, date: date, score: 1)) == "Blind comparison: the newer piece was picked")
    }
}

/// A piece with its slips marked: offsets count Characters, and a bad one never traps.
@MainActor
struct MarkedTextTests {
    /// A slip from the checker, moved to `offset` (the type has no public initialiser).
    func slip(_ offset: Int, _ length: Int) throws -> WritingSlip {
        var slip = try #require(WritingCheck.slips("teh", misspelled: ["teh"]).first)
        slip.offset = offset
        slip.length = length
        return slip
    }

    func marked(_ text: String, _ slips: [WritingSlip]) -> [String] {
        let attributed = MarkedText.attributed(text, slips: slips)
        return attributed.runs.filter { $0.underlineStyle != nil }.map { String(attributed[$0.range].characters) }
    }

    @Test func theCheckersOwnSlipsAreMarked() {
        let text = "I recieved it and and kept it."
        #expect(marked(text, WritingCheck.slips(text, misspelled: ["recieved"])) == ["recieved", "and and"])
    }

    @Test func slipsAreMarkedWhereTheyAre() throws {
        #expect(marked("I recieved it", [try slip(2, 8)]) == ["recieved"])
        #expect(marked("the the end", [try slip(0, 7)]) == ["the the"])
        #expect(marked("ends in teh", [try slip(8, 3)]) == ["teh"], "a slip at the very end")
    }

    @Test func offsetsCountCharactersNotBytes() throws {
        // Emoji, curly quotes and accents are one Character each, as the checker counts them.
        #expect(marked("👍🏽 “Café” teh", [try slip(9, 3)]) == ["teh"])
        #expect(marked("naïve wrod", [try slip(6, 4)]) == ["wrod"])
    }

    @Test func slipsOutsideTheTextAreLeftUnmarked() throws {
        #expect(marked("short", [try slip(3, 9)]).isEmpty)
        #expect(marked("short", [try slip(9, 1)]).isEmpty)
        #expect(marked("short", [try slip(-1, 2)]).isEmpty)
        #expect(marked("short", [try slip(1, -1)]).isEmpty)
        #expect(marked("short", [try slip(5, 0)]).isEmpty)
        #expect(marked("", [try slip(0, 1)]).isEmpty)
        #expect(marked("short", [try slip(Int.max, 2)]).isEmpty)
    }
}

/// Furigana and stress guides line up with what they're over: plain runs split so they wrap.
@MainActor
struct ScaffoldedTextTests {
    @Test func japaneseSplitsByCharacterAndKeepsHelpedItemsWhole() {
        let text = Scaffolded(
            language: .japanese,
            segments: [
                .init(text: "猫", help: "ねこ", kind: .furigana), .init(text: "がいる"),
            ])
        #expect(ScaffoldedText(text: text).pieces.map(\.text) == ["猫", "が", "い", "る"])
        #expect(ScaffoldedText(text: text).pieces.first?.help == "ねこ")
    }

    @Test func otherScriptsSplitByWordKeepingTheirSpaces() {
        let text = Scaffolded(
            language: .spanish,
            segments: [
                .init(text: "Me gusta el "), .init(text: "corazón", help: "co·ra·ZÓN", kind: .stress), .init(text: " rojo"),
            ])
        #expect(ScaffoldedText(text: text).pieces.map(\.text) == ["Me ", "gusta ", "el ", "corazón", " ", "rojo"])
    }
}
