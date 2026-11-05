#if os(macOS)
import AppKit
import SwiftUI
import SystemCore
import Testing

@testable import MacroTrack

/// The Mac's window stays `.active` behind another app's and while it sleeps, so the app's own
/// activation and the workspace's sleep are what say someone left. The notifications are posted
/// here; that macOS sends them is its side of the bargain.
@MainActor
struct MacAppSwitchTests {
    @Observable
    final class Heard {
        var left = 0
        var returned = 0
    }

    func wait(until done: () -> Bool) async throws {
        for _ in 0..<200 where !done() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func anotherAppInFrontAndBackAreHeard() async throws {
        let heard = Heard()
        let view = Color.clear.frame(width: 10, height: 10)
            .onGoingAway(left: { heard.left += 1 }, returned: { heard.returned += 1 })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        defer { window.close() }
        window.layoutIfNeeded()
        // Past the view's first update, when it starts listening.
        try await Task.sleep(for: .milliseconds(100))

        let center = NotificationCenter.default
        let left = heard.left
        center.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        try await wait { heard.left > left }
        #expect(heard.left > left)

        let returned = heard.returned
        center.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        try await wait { heard.returned > returned }
        #expect(heard.returned > returned)
    }

    @Test func theMacGoingToSleepIsHeard() async throws {
        let heard = Heard()
        let view = Color.clear.frame(width: 10, height: 10)
            .onGoingAway(left: { heard.left += 1 }, returned: { heard.returned += 1 })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        defer { window.close() }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            let left = heard.left
            workspace.post(name: name, object: NSWorkspace.shared)
            try await wait { heard.left > left }
            #expect(heard.left > left, "\(name.rawValue)")
        }
    }

    /// The model's side: the first of the signals sets the time away, and the second says nothing.
    @Test func sleepAndWakeCountAsAWhileAway() {
        let model = TestEnvironment().model()
        model.onboard()
        let yesterday = model.today.adding(days: -1)
        model.selectedDay = yesterday
        let night = Date().addingTimeInterval(-5 * 3600)
        model.wentToBackground(at: night)
        model.wentToBackground(at: night.addingTimeInterval(60))
        model.cameToFront()
        #expect(model.selectedDay == model.today)
    }
}
#endif
