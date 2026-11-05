import Foundation
import SystemCore
import SystemStore

@testable import Hub

/// A clock a test moves by hand, so every date the model makes is known.
@MainActor
final class TestClock {
    var now: Date

    init(_ now: Date = TestApp.wednesday) { self.now = now }

    func advance(hours: Double) { now += hours * 3600 }
    func advance(days: Int) { now += Double(days) * 86_400 }
}

/// App models for tests: an in-memory store and a shared container in a fresh temporary folder,
/// never the real ones, on a fixed clock.
@MainActor
enum TestApp {
    /// Wednesday 14 October 2026, 10:00 here.
    static let wednesday = Day(year: 2026, month: 10, day: 14).date().addingTimeInterval(10 * 3600)
    static var monday: Day { Day(wednesday).startOfWeek }

    static func folder() -> URL {
        URL.temporaryDirectory.appending(path: "HubTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    static func store() -> RecordStore { RecordStore(name: "HubTests", cloudKitContainer: nil, inMemory: true) }

    static func model(clock: TestClock = TestClock(), shared: SharedContainer? = nil, store: RecordStore? = nil) -> AppModel {
        AppModel(store: store ?? self.store(), shared: shared ?? SharedContainer(directory: folder()), now: { clock.now })
    }
}
