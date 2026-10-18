import Foundation

/// How a review went. Never typed in: it comes from whether the answer was right and how long it
/// took, so the schedule rests on what happened, not on how the person felt about it.
public enum Grade: Int, Codable, Sendable, Comparable {
    case again = 1, hard, good, easy

    public static func < (a: Grade, b: Grade) -> Bool { a.rawValue < b.rawValue }

    /// Wrong is Again. Right but slow (over twice the usual time) is Hard; right and quick (under
    /// half of it) is Easy, once an item has been seen before.
    public static func from(correct: Bool, seconds: Double, expected: Double, seenBefore: Bool = true) -> Grade {
        guard correct else { return .again }
        if seconds > expected * 2 { return .hard }
        if seenBefore && seconds < expected * 0.5 { return .easy }
        return .good
    }
}

/// What the model knows about one memory: how long it lasts (stability, in days), how hard it is
/// to hold (difficulty, 1–10) and when it was last reviewed.
public struct Memory: Hashable, Codable, Sendable {
    public var stability: Double
    public var difficulty: Double
    public var lastReview: Date
    public var due: Date
    public var reps: Int
    public var lapses: Int

    public init(stability: Double, difficulty: Double, lastReview: Date, due: Date, reps: Int = 1, lapses: Int = 0) {
        self.stability = stability
        self.difficulty = difficulty
        self.lastReview = lastReview
        self.due = due
        self.reps = reps
        self.lapses = lapses
    }

    public func isDue(at date: Date) -> Bool { due <= date }
}

/// Spaced repetition with the open FSRS model (version 4.5) and its published default weights:
/// the chance of recalling something falls as a power curve of time over stability, and each
/// review moves stability and difficulty by how it went and how forgettable it had become.
/// Reviews are scheduled for 90% recall, so about one in ten is expected to be missed.
public enum Scheduler {
    public static let weights: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474, 0.1367,
        1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755,
    ]
    public static let desiredRetention = 0.9
    static let decay = -0.5
    static let factor = 19.0 / 81.0
    public static let maximumInterval = 365.0 * 2

    static var w: [Double] { weights }

    /// The chance of recalling it now.
    public static func retrievability(_ memory: Memory, at date: Date) -> Double {
        retrievability(elapsed: max(0, date.timeIntervalSince(memory.lastReview) / 86_400), stability: memory.stability)
    }

    public static func retrievability(elapsed days: Double, stability: Double) -> Double {
        pow(1 + factor * days / max(0.01, stability), decay)
    }

    /// Days until recall falls to the desired retention.
    public static func interval(stability: Double, retention: Double = desiredRetention) -> Double {
        let days = stability / factor * (pow(retention, 1 / decay) - 1)
        return min(maximumInterval, max(1, days))
    }

    /// The first time it's answered (after being taught, or as a check of something already known).
    public static func first(_ grade: Grade, at date: Date) -> Memory {
        let stability = w[grade.rawValue - 1]
        let difficulty = initialDifficulty(grade)
        return Memory(
            stability: stability, difficulty: difficulty, lastReview: date,
            due: date.addingTimeInterval(roundedDays(interval(stability: stability)) * 86_400), reps: 1,
            lapses: grade == .again ? 1 : 0)
    }

    /// Something shown to be known already (a placement test, or a quick check passed): treated as
    /// a memory that has lasted `days`, so it comes back for a check well before it would fade.
    public static func known(stability days: Double, at date: Date, difficulty: Double = 5) -> Memory {
        Memory(
            stability: days, difficulty: difficulty, lastReview: date,
            due: date.addingTimeInterval(roundedDays(interval(stability: days)) * 86_400), reps: 1)
    }

    public static func review(_ memory: Memory, grade: Grade, at date: Date) -> Memory {
        let elapsed = max(0, date.timeIntervalSince(memory.lastReview) / 86_400)
        let r = retrievability(elapsed: elapsed, stability: memory.stability)
        let d = nextDifficulty(memory.difficulty, grade)
        var s: Double
        if grade == .again {
            s = min(memory.stability, forgetStability(memory.difficulty, memory.stability, r))
        } else if elapsed < 0.5 {
            // A same-day repeat says little about long-term memory: a small bump at most.
            s = memory.stability * (grade == .hard ? 1 : 1.1)
        } else {
            s = recallStability(memory.difficulty, memory.stability, r, grade)
        }
        s = max(0.1, s)
        var next = memory
        next.stability = s
        next.difficulty = d
        next.lastReview = date
        next.reps += 1
        if grade == .again { next.lapses += 1 }
        // A miss comes back the next day; anything else at the interval for 90% recall.
        let days = grade == .again ? 1 : roundedDays(interval(stability: s))
        next.due = date.addingTimeInterval(days * 86_400)
        return next
    }

    static func initialDifficulty(_ grade: Grade) -> Double {
        min(10, max(1, w[4] - exp(w[5] * Double(grade.rawValue - 1)) + 1))
    }

    static func nextDifficulty(_ d: Double, _ grade: Grade) -> Double {
        let moved = d - w[6] * Double(grade.rawValue - 3)
        // Mean reversion toward the difficulty of an item first answered Easy.
        return min(10, max(1, w[7] * initialDifficulty(.easy) + (1 - w[7]) * moved))
    }

    static func recallStability(_ d: Double, _ s: Double, _ r: Double, _ grade: Grade) -> Double {
        let hard = grade == .hard ? w[15] : 1
        let easy = grade == .easy ? w[16] : 1
        return s * (exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hard * easy + 1)
    }

    static func forgetStability(_ d: Double, _ s: Double, _ r: Double) -> Double {
        w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r))
    }

    /// Whole days, so a card is due on a day rather than at a minute.
    static func roundedDays(_ days: Double) -> Double { max(1, days.rounded()) }
}
