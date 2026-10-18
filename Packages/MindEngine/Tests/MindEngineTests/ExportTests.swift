import Foundation
import Testing

@testable import MindEngine

@Suite("Export")
struct ExportTests {
    @Test("blind comparisons export with both pieces' dates and both picks, blank where nobody picked")
    func comparisons() throws {
        let old = WritingPiece(date: Date(timeIntervalSince1970: 0), exercise: .prompt, writingKind: .creative, prompt: "A", text: "Early.")
        let new = WritingPiece(date: Date(timeIntervalSince1970: 86_400 * 40), exercise: .prompt, writingKind: .creative, prompt: "A", text: "Later.")
        let judged = BlindComparison(date: new.date, older: old.id, newer: new.id, pickedNewer: true, aiPickedNewer: false)
        let open = BlindComparison(date: new.date.addingTimeInterval(60), older: old.id, newer: new.id)
        let tables = MindExport.tables(
            sessions: [], cards: [], tests: [], books: [], reflections: [], pieces: [new, old],
            comparisons: [open, judged])
        let table = try #require(tables.first { $0.name == "blind_comparisons" })
        #expect(table.rows.count == 2)
        #expect(table.rows.allSatisfy { $0.count == table.header.count })
        #expect(table.rows[0] == [MindExport.iso(judged.date), MindExport.iso(old.date), MindExport.iso(new.date), "prompt", "yes", "no"])
        #expect(table.rows[1].suffix(2) == ["", ""])
    }
}
