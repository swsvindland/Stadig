import Foundation
import SystemCore

/// Stadig Mind's data as plain tables for CSV export: your data, portable.
public enum MindExport {
    public struct Table: Sendable {
        public var name: String
        public var header: [String]
        public var rows: [[String]]
    }

    static func iso(_ date: Date) -> String { date.ISO8601Format() }
    static func number(_ value: Double) -> String { String(format: "%.3f", value) }

    public static func tables(
        sessions: [StudySession], cards: [MemoryCard], tests: [TestResult], books: [Book],
        reflections: [Reflection], pieces: [WritingPiece] = [], comparisons: [BlindComparison] = []
    ) -> [Table] {
        let sessionRows = sessions.sorted { $0.start < $1.start }.map { s in
            [
                iso(s.start), s.end.map(iso) ?? "", s.purpose.rawValue, s.domains.map(\.rawValue).joined(separator: " "), number(s.minutes),
                "\(s.plannedMinutes)", s.planned ? "yes" : "no", "\(s.attempts.count)", "\(s.attempts.filter(\.correct).count)",
                s.reading.map { "\($0.pages)" } ?? "",
            ]
        }
        let attemptRows = sessions.sorted { $0.start < $1.start }.flatMap { s in
            s.attempts.map { a in
                [
                    iso(a.at), a.key.raw, a.domain.rawValue, a.kind.rawValue, a.correct ? "yes" : "no", a.skipped ? "yes" : "no",
                    number(a.seconds), a.test?.rawValue ?? "", a.band.map(String.init) ?? "",
                ]
            }
        }
        let cardRows = cards.sorted { $0.key < $1.key }.map { c in
            [
                c.key.raw, c.domain.rawValue, iso(c.introduced), c.knownBefore ? "yes" : "no",
                c.memory.map { number($0.stability) } ?? "", c.memory.map { number($0.difficulty) } ?? "",
                c.memory.map { iso($0.due) } ?? "", c.memory.map { "\($0.reps)" } ?? "", c.memory.map { "\($0.lapses)" } ?? "",
            ]
        }
        let testRows = tests.sorted { $0.date < $1.date }.map { t in
            [
                iso(t.date), t.test.rawValue, t.language?.rawValue ?? "", number(t.score), t.placement ? "yes" : "no",
                t.detail.sorted { $0.key < $1.key }.map { "\($0.key)=\(number($0.value))" }.joined(separator: " "),
            ]
        }
        let bookRows = books.sorted { $0.title < $1.title }.map { b in
            [
                b.title, b.author, "\(b.tier)", "\(b.pages)", b.genres.map(\.rawValue).joined(separator: " "), b.status.rawValue,
                b.started?.iso ?? "", b.finished?.iso ?? "", "\(b.page)", b.feel?.rawValue ?? "", b.format?.rawValue ?? "", b.isbn ?? "",
            ]
        }
        let titles = Dictionary(books.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let reflectionRows = reflections.sorted { $0.date < $1.date }.map { r in
            [iso(r.date), r.bookID.flatMap { titles[$0] } ?? "", r.kind.rawValue, r.page.map(String.init) ?? "", r.text]
        }
        let pieceRows = pieces.sorted { $0.date < $1.date }.map { p in
            [
                iso(p.date), p.exercise.rawValue, p.writingKind.rawValue, p.source.rawValue, "\(p.words)", p.prompt, p.text, p.feedback ?? "",
                p.metrics.sorted { $0.key < $1.key }.map { "\($0.key)=\(number($0.value))" }.joined(separator: " "),
            ]
        }
        let piecesByID = Dictionary(pieces.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func yesNo(_ value: Bool?) -> String { value.map { $0 ? "yes" : "no" } ?? "" }
        let comparisonRows = comparisons.sorted { $0.date < $1.date }.map { c in
            [
                iso(c.date), piecesByID[c.older].map { iso($0.date) } ?? "", piecesByID[c.newer].map { iso($0.date) } ?? "",
                piecesByID[c.newer]?.exercise.rawValue ?? "", yesNo(c.pickedNewer), yesNo(c.aiPickedNewer),
            ]
        }
        return [
            Table(
                name: "sessions",
                header: ["start", "end", "kind", "domains", "minutes", "planned_minutes", "planned", "questions", "correct", "pages"],
                rows: sessionRows),
            Table(name: "answers", header: ["time", "item", "domain", "kind", "correct", "dont_know", "seconds", "test", "band"], rows: attemptRows),
            Table(
                name: "memory", header: ["item", "domain", "introduced", "known_before", "stability_days", "difficulty", "due", "reviews", "lapses"],
                rows: cardRows),
            Table(name: "tests", header: ["date", "test", "language", "score", "placement", "detail"], rows: testRows),
            Table(
                name: "books",
                header: ["title", "author", "tier", "pages", "genres", "status", "started", "finished", "page", "felt", "format", "isbn"],
                rows: bookRows),
            Table(name: "reflections", header: ["date", "book", "kind", "page", "text"], rows: reflectionRows),
            Table(
                name: "writing", header: ["date", "exercise", "kind", "source", "words", "prompt", "text", "feedback", "metrics"], rows: pieceRows),
            Table(
                name: "blind_comparisons", header: ["date", "older_piece", "newer_piece", "exercise", "you_picked_newer", "ai_picked_newer"],
                rows: comparisonRows),
        ]
    }
}
