import Foundation
import Testing

@testable import FoodDatabase

/// Reports search latency; never fails on timing.
@Suite("Search latency", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"), .serialized)
struct BenchmarkTests {
    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
    }

    @Test("keystroke searches over the basket")
    func latency() {
        let clock = ContinuousClock()
        // A fresh catalog, so the first searches pay for spelling lookups as they would after launch.
        let catalog = FoodCatalog(usda: Catalogs.usdaURL, off: Catalogs.offURL, region: "us")
        var first: [(String, Double)] = []
        for query in ["warm", "celsius", "kodiak cakes", "chiken", "protien bar"] {
            first.append((query, Self.milliseconds(clock.measure { _ = catalog.search(query) })))
        }
        let keystrokes = ["ch", "co", "ba", "sa", "po", "chi", "chic", "chick", "chicke", "trader joes mini wheats", "great value whole milk"]
        let queries = searchBasket.map(\.0) + firstResults.map(\.0) + keystrokes
        var medians: [(String, Double)] = []
        var all: [Double] = []
        for query in queries {
            var runs: [Double] = []
            for _ in 0..<5 { runs.append(Self.milliseconds(clock.measure { _ = catalog.search(query) })) }
            all += runs
            medians.append((query, Self.percentile(runs, 0.5)))
        }
        let typical = medians.map(\.1)
        let slowest = medians.sorted { $0.1 > $1.1 }.prefix(8).map { "\($0.0) \(String(format: "%.1f", $0.1))" }
        print(
            """
            Search latency (\(queries.count) queries × 5 runs, warm):
              median \(String(format: "%.2f", Self.percentile(typical, 0.5))) ms, \
            p95 \(String(format: "%.2f", Self.percentile(typical, 0.95))) ms, \
            max \(String(format: "%.2f", typical.max() ?? 0)) ms (all runs p95 \(String(format: "%.2f", Self.percentile(all, 0.95))) ms)
              slowest: \(slowest.joined(separator: ", "))
              first time (spelling lookups): \(first.map { "\($0.0) \(String(format: "%.1f", $0.1))" }.joined(separator: ", ")) ms
            """)
        var candidates: [Double] = []
        for name in ["lettuce", "tomato slice", "hamburger bun", "bacon", "french fries", "chicken", "white rice", "cheese"] {
            candidates.append(Self.milliseconds(clock.measure { _ = catalog.candidates(name: name, brand: nil) }))
        }
        candidates.append(Self.milliseconds(clock.measure { _ = catalog.candidates(name: "Mini Wheats", brand: "Trader Joe's") }))
        print(
            "Candidates latency: median \(String(format: "%.2f", Self.percentile(candidates, 0.5))) ms, "
                + "max \(String(format: "%.2f", candidates.max() ?? 0)) ms")
    }
}
