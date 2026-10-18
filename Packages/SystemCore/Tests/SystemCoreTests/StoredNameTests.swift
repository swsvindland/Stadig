import Foundation
import Testing

@testable import SystemCore

/// Names in the code can change; the values already stored and synced can't.
@Suite("Stored names")
struct StoredNameTests {
    @Test func theRunBenchmarkKeepsItsStoredName() throws {
        #expect(EnduranceBenchmark.run2400m.rawValue == "run2_4k")
        let decoded = try JSONDecoder().decode([EnduranceBenchmark].self, from: Data(#"["run2_4k","row2k"]"#.utf8))
        #expect(decoded == [.run2400m, .row2k])
        #expect(String(decoding: try JSONEncoder().encode([EnduranceBenchmark.run2400m]), as: UTF8.self) == #"["run2_4k"]"#)
    }
}
