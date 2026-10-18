import Foundation
import Testing

@testable import MindEngine

@Suite("Spaced repetition")
struct MemoryTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("at its stability, a memory is at 90% recall, and the interval for 90% is the stability")
    func curve() {
        #expect(abs(Scheduler.retrievability(elapsed: 10, stability: 10) - 0.9) < 1e-9)
        #expect(abs(Scheduler.interval(stability: 10) - 10) < 1e-9)
        #expect(Scheduler.retrievability(elapsed: 30, stability: 10) < 0.8)
    }

    @Test("each remembered review pushes the next one further out; a miss brings it back tomorrow")
    func intervals() {
        var memory = Scheduler.first(.good, at: start)
        var date = start
        var gaps: [Double] = []
        for _ in 0..<4 {
            date = memory.due
            let next = Scheduler.review(memory, grade: .good, at: date)
            gaps.append(next.due.timeIntervalSince(date) / 86_400)
            memory = next
        }
        #expect(zip(gaps, gaps.dropFirst()).allSatisfy { $0 < $1 }, "\(gaps)")
        #expect(gaps.last! > 60, "four clean reviews reach two months or more: \(gaps)")
        let missed = Scheduler.review(memory, grade: .again, at: memory.due)
        #expect(missed.due.timeIntervalSince(memory.due) / 86_400 == 1)
        #expect(missed.stability < memory.stability && missed.lapses == 1)
        #expect(Scheduler.review(memory, grade: .easy, at: memory.due).stability > Scheduler.review(memory, grade: .good, at: memory.due).stability)
        #expect(Scheduler.review(memory, grade: .hard, at: memory.due).stability < Scheduler.review(memory, grade: .good, at: memory.due).stability)
    }

    @Test("a learner whose memory follows the curve recalls about 90% of reviews")
    func simulatedRetention() {
        var rng = SeededRandom(seed: 7)
        var recalled = 0
        var reviews = 0
        for _ in 0..<400 {
            var memory = Scheduler.first(.good, at: start)
            for _ in 0..<8 {
                let elapsed = memory.due.timeIntervalSince(memory.lastReview) / 86_400
                let p = Scheduler.retrievability(elapsed: elapsed, stability: memory.stability)
                let ok = Double.random(in: 0..<1, using: &rng) < p
                reviews += 1
                if ok { recalled += 1 }
                memory = Scheduler.review(memory, grade: ok ? .good : .again, at: memory.due)
            }
        }
        let rate = Double(recalled) / Double(reviews)
        #expect(rate > 0.86 && rate < 0.94, "\(rate)")
    }

    @Test("grades come from right or wrong and the time taken, never from a self-rating")
    func grades() {
        #expect(Grade.from(correct: false, seconds: 2, expected: 6) == .again)
        #expect(Grade.from(correct: true, seconds: 20, expected: 6) == .hard)
        #expect(Grade.from(correct: true, seconds: 6, expected: 6) == .good)
        #expect(Grade.from(correct: true, seconds: 2, expected: 6) == .easy)
        #expect(Grade.from(correct: true, seconds: 2, expected: 6, seenBefore: false) == .good)
    }

    @Test("typed answers: fractions, decimals, mixed numbers and any equal value")
    func rationals() throws {
        #expect(Rational(parsing: "3/4") == Rational(3, 4))
        #expect(Rational(parsing: "6/8") == Rational(3, 4))
        #expect(Rational(parsing: "-2") == Rational(-2))
        #expect(Rational(parsing: "−5") == Rational(-5))
        #expect(Rational(parsing: "0.75") == Rational(3, 4))
        #expect(Rational(parsing: "1 1/2") == Rational(3, 2))
        #expect(Rational(parsing: "-1 1/2") == Rational(-3, 2))
        #expect(Rational(parsing: "abc") == nil && Rational(parsing: "1/0") == nil && Rational(parsing: "") == nil)
        #expect(Rational(1, 3) + Rational(1, 6) == Rational(1, 2))
        #expect(Rational(2).power(-3) == Rational(1, 8))
        #expect(Rational(-3, 4).tex == #"-\frac{3}{4}"#)
        let question = Question(
            id: "q", key: .topic("x"), kind: .learn, instruction: "", prompt: .math(""), answer: .number(Rational(1, 3)),
            expectedSeconds: 10)
        #expect(question.check(typed: "2/6") && !question.check(typed: "0.333"))
        let rounded = Question(
            id: "q", key: .topic("x"), kind: .learn, instruction: "", prompt: .math(""),
            answer: .number(Rational(314, 100), tolerance: 0.011), expectedSeconds: 10)
        #expect(rounded.check(typed: "3.14") && rounded.check(typed: "3.15") && !rounded.check(typed: "3.2"))
    }

    @Test("the same key always makes the same record id, so two devices converge")
    func cardIDs() {
        #expect(CardKey.word(1_358_280).recordID == CardKey("jp.word.1358280").recordID)
        #expect(CardKey.word(1).recordID != CardKey.word(2).recordID)
        #expect(CardKey.topic("limits").domain == .maths && CardKey.skill("commas").domain == .writing && CardKey.kana("あ").domain == .japanese)
        #expect(CardKey.word(42).wordID == 42 && CardKey.kana("きゃ").item == "きゃ")
    }
}
