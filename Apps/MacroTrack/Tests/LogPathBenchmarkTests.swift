import Foundation
import NutritionEngine
import SwiftUI
import SystemCore
import Testing

@testable import MacroTrack
@testable import SystemStore

/// Reports the main thread's time on the two paths Stadig Macro has to keep fast, over a long
/// history in a store on disk, as the app's is; never fails on timing. Each line is one signposted
/// step (`LogPath`), and the steps nest: `log` holds `reload`, which holds `recompute`, which holds
/// the rest. "On screen" adds SwiftUI: from the change until the main thread is free again with
/// Today in a window, which is everything but the render server's own work.
/// BENCHMARKS=1 turns it on, since seeding takes minutes (docs/testing.md has the command, with the
/// optimized build the budget is judged on).
@MainActor
@Suite("Log path latency", .enabled(if: ProcessInfo.processInfo.environment["BENCHMARKS"] != nil, "set BENCHMARKS=1"), .serialized)
struct LogPathBenchmarkTests {
    /// Main-thread p95 at 5 years, in milliseconds: a frame.
    static let budget = 16.0
    static let runs = 40

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
    }

    static func lines(_ steps: [String: [Double]], order: [String]) -> [String] {
        order.compactMap { name in
            guard let times = steps[name], !times.isEmpty else { return nil }
            let p95 = percentile(times, 0.95)
            return String(
                format: "  %@: median %.2f ms, p95 %.2f ms, max %.2f ms%@", name, percentile(times, 0.5), p95, times.max() ?? 0,
                p95 > budget ? " (over a frame)" : "")
        }
    }

    /// What Today reads while it draws a day: the same work a `body` does after a log or a day change.
    static func todayReads(_ model: AppModel, on day: Day) {
        let moments = Timeline.moments(model.entries(on: day))
        _ = moments.count
        _ = model.usualNow
        _ = model.usualMeals
        _ = model.catchUp
    }

    /// Puts Today in a window of the test host, where SwiftUI updates it as the app's would. On the
    /// Mac nothing's shown, and "On screen" is only the model.
    static func show(_ model: AppModel) -> AnyObject? {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: TodayView().environment(model).environment(model.purchases))
        window.isHidden = false
        return window
        #else
        return nil
        #endif
    }

    /// Back on the main thread after two turns of its run loop: SwiftUI's update for whatever just
    /// changed has run by then.
    static func settled() async {
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    /// Runs `work`, gathering the signposted steps and, when `whole`, the whole of it as `name`.
    static func measure(_ name: String, into steps: inout [String: [Double]], whole: Bool = true, _ work: () -> Void) {
        var heard: [(String, Double)] = []
        LogPath.onInterval = { step, duration in heard.append((step, milliseconds(duration))) }
        let elapsed = ContinuousClock().measure(work)
        LogPath.onInterval = nil
        for (step, time) in heard { steps[step, default: []].append(time) }
        if whole { steps[name, default: []].append(milliseconds(elapsed)) }
    }

    @Test("logging a food and changing day", arguments: [1, 5, 10])
    func latency(years: Int) async throws {
        let folder = URL.temporaryDirectory.appending(path: "LogPathBenchmark \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecordStore(name: "LogPathBenchmark", cloudKitContainer: nil, inMemory: false, directory: folder)
        let model = TestEnvironment(store: store).model()
        let clock = ContinuousClock()
        let seeding = clock.measure { SampleData.seedLongHistory(model, years: years) }
        try #require(model.onboarded)
        #expect(model.analysis?.dueCheckIn == nil)
        let food = try model.entry(foodID: Foods.bananaID, grams: 120)
        let screen = Self.show(model)
        defer { _ = screen }
        await Self.settled()

        var logging: [String: [Double]] = [:]
        var reads: [String: [Double]] = [:]
        for _ in 0..<Self.runs {
            var entry = food
            entry.id = UUID()
            entry.date = Date()
            entry.day = model.today
            Self.measure("log", into: &logging, whole: false) { model.log([entry]) }
            Self.measure("Today's reads", into: &reads) { Self.todayReads(model, on: model.today) }
            // A person logs seconds apart: what the log started off the main thread gets to run.
            try await Task.sleep(for: .milliseconds(5))
            await Self.settled()
            model.toast = nil
            let start = clock.now
            var again = entry
            again.id = UUID()
            model.log([again])
            await Self.settled()
            logging["On screen", default: []].append(Self.milliseconds(clock.now - start))
            try await Task.sleep(for: .milliseconds(5))
            await Self.settled()
        }

        var changing: [String: [Double]] = [:]
        var changedReads: [String: [Double]] = [:]
        let today = model.today
        for run in 0..<Self.runs {
            let day = run.isMultiple(of: 2) ? today.adding(days: -(run % 20) - 1) : today
            await Self.settled()
            let start = clock.now
            Self.measure("whole change", into: &changing) { model.selectedDay = day }
            await Self.settled()
            changing["On screen", default: []].append(Self.milliseconds(clock.now - start))
            Self.measure("Today's reads", into: &changedReads) { Self.todayReads(model, on: day) }
        }

        let order = [
            "On screen", "log", "save", "reload", "readEntries", "readShared", "recompute", "analyse", "rankings", "publish", "refreshCatchUp",
        ]
        print(
            ([
                "Log path over \(years) years: \(model.entries.count) entries, seeded in \(String(format: "%.1f", Self.milliseconds(seeding) / 1000)) s"
            ]
                + ["Logging a food:"] + Self.lines(logging, order: order) + Self.lines(reads, order: ["Today's reads"])
                + ["Changing day:"] + Self.lines(changing, order: ["On screen", "whole change", "refreshCatchUp"])
                + Self.lines(changedReads, order: ["Today's reads"]))
                .joined(separator: "\n"))
    }
}
