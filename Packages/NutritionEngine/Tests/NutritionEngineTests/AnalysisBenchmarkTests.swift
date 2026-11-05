import Foundation
import SystemCore
import Testing

@testable import NutritionEngine

/// Reports what the app's recompute costs over long histories; never fails on timing. Debug builds
/// are several times slower than the app ships, so `-Xswiftc -O` gives the numbers to compare with
/// the budget (docs/testing.md). BENCHMARKS=1 turns it on: seeding ten years takes a while.
@Suite("Analysis latency", .enabled(if: ProcessInfo.processInfo.environment["BENCHMARKS"] != nil, "set BENCHMARKS=1"), .serialized)
struct AnalysisBenchmarkTests {
    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
    }

    /// Median, p95 and max of `runs` calls.
    static func report(_ name: String, runs: Int, _ work: () -> Void) -> String {
        let clock = ContinuousClock()
        var times: [Double] = []
        for _ in 0..<runs { times.append(milliseconds(clock.measure(work))) }
        return String(
            format: "  %@: median %.2f ms, p95 %.2f ms, max %.2f ms", name, percentile(times, 0.5), percentile(times, 0.95), times.max() ?? 0)
    }

    @Test("analyse, rankings and usual times", arguments: [1, 5, 10])
    func latency(years: Int) {
        let clock = ContinuousClock()
        var history: LongHistory?
        let seeding = clock.measure { history = LongHistory(years: years) }
        guard let history else { return }
        let state = history.state
        let now = history.now
        let yesterday = history.today.adding(days: -1)
        let lunch = yesterday.at(hour: 12, minute: 30)
        let runs = 30
        var lines = [
            """
            Analysis over \(years) years: \(history.entries.count) entries, \(history.weighIns.count) weigh-ins, \
            \(history.checkIns.count) check-ins, \(history.supplementLogs.count) doses, \(history.water.count) water, \
            \(history.fasts.count) fasts (seeded in \(String(format: "%.0f", Self.milliseconds(seeding))) ms)
            """
        ]
        var analysis: MacroAnalysis?
        lines.append(Self.report("analyse", runs: runs) { analysis = MacroAnalyst.analyse(state) })
        lines.append(Self.report("LogAgain.rank now", runs: runs) { _ = LogAgain.rank(history.entries, now: now) })
        lines.append(Self.report("LogAgain.rank at a time", runs: runs) { _ = LogAgain.rank(history.entries, now: now, at: lunch) })
        lines.append(Self.report("SavedMeals.rank now", runs: runs) { _ = SavedMeals.rank(history.savedMeals, entries: history.entries, now: now) })
        lines.append(
            Self.report("SavedMeals.rank at a time", runs: runs) {
                _ = SavedMeals.rank(history.savedMeals, entries: history.entries, now: now, at: lunch)
            })
        lines.append(Self.report("UsualMeals.on", runs: runs) { _ = UsualMeals.on(yesterday, entries: history.entries, today: history.today) })
        lines.append(Self.report("LogAgain.usualMoment", runs: runs) { _ = LogAgain.usualMoment(near: now, entries: history.entries) })
        if let analysis {
            lines.append(Self.report("nutritionSummary", runs: runs) { _ = MacroAnalyst.nutritionSummary(state, analysis) })
            lines.append(Self.report("appSummary", runs: runs) { _ = MacroAnalyst.appSummary(state, analysis) })
        }
        print(lines.joined(separator: "\n"))
        // Only a check that the history reads as a real one: every other number here is reported.
        #expect(analysis?.dueCheckIn == nil)
        #expect(history.entries.count >= years * 365 * LongHistory.entriesPerDay)
    }
}
