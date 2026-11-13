import XCTest

/// Apple's accessibility audit (hit regions, descriptions, traits, text without an element, and with
/// Increase Contrast on, contrast) over the main screens with sample data, in dark and in light, less
/// what it can't judge here (`UITests/Support/Audit.swift`). Only on demand, and skipped in every
/// other run (docs/testing.md):
///
///     TEST_RUNNER_ACCESSIBILITY_AUDIT=1 ONLY=AccessibilityAudit Scripts/build.sh ui lift
///
/// `ACCESSIBILITY_AUDIT=contrast` adds the contrast check, for a simulator with Increase Contrast on.
nonisolated final class AccessibilityAudit: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["ACCESSIBILITY_AUDIT"] == nil, "Only runs with TEST_RUNNER_ACCESSIBILITY_AUDIT set")
    }

    override func tearDown() {
        // The simulator is left dark, as the boards were drawn.
        MainActor.assumeIsolated { XCUIDevice.shared.appearance = .dark }
    }

    @MainActor
    func testToday() throws {
        try audit("today", ["-seedSampleData"], ready: "today.screen")
    }

    @MainActor
    func testPlan() throws {
        try audit("plan", ["-seedSampleData", "-tab", "plan"], ready: "plan.screen")
    }

    @MainActor
    func testProgress() throws {
        try audit("progress", ["-seedSampleData", "-tab", "progress"], ready: "progress.screen", pages: 5)
    }

    @MainActor
    func testBody() throws {
        try audit("body", ["-seedSampleData", "-tab", "body"], ready: "body.screen")
    }

    @MainActor
    func testYourShape() throws {
        try audit("shape", ["-seedSampleData", "-tab", "progress", "-yourShape"], ready: "progress.shapePage", pages: 3)
    }

    @MainActor
    func testSessionAtASet() throws {
        try audit("session.set", ["-seedSampleData", "-startSession", "-sessionAt", "set"], ready: "logger.ratingOrange", pages: 1)
    }

    @MainActor
    func testSessionAtRest() throws {
        try audit("session.rest", ["-seedSampleData", "-startSession", "-sessionAt", "rest"], ready: "rest.skip", pages: 1)
    }

    @MainActor
    func testSettings() throws {
        try audit("settings", ["-seedSampleData", "-openSettings"], ready: "settings.screen")
    }

    /// Launches the screen in each appearance and audits it, and again a screen further down each
    /// time, up to `pages` screens.
    @MainActor
    func audit(_ screen: String, _ arguments: [String], ready: String, pages: Int = 4) throws {
        let contrast = ProcessInfo.processInfo.environment["ACCESSIBILITY_AUDIT"] == "contrast"
        for appearance in [XCUIDevice.Appearance.dark, .light] {
            // Set before the launch: a running app doesn't take it up.
            XCUIDevice.shared.appearance = appearance
            let app = XCUIApplication.launched(arguments)
            app.element(ready).waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
            for page in 0..<pages {
                if page > 0 { app.swipeUp() }
                // The scroll indicator fading out, and a chart's first layout.
                Thread.sleep(forTimeInterval: 1)
                try app.auditScreen("\(screen)[\(appearance == .dark ? "dark" : "light")]", page: page, contrast: contrast)
            }
            app.terminate()
        }
    }
}
