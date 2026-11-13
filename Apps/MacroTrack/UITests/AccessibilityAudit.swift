import XCTest

/// Apple's accessibility audit (hit regions, descriptions, traits, text without an element, and with
/// Increase Contrast on, contrast) over the main screens with sample data, in dark and in light, less
/// what it can't judge here (`UITests/Support/Audit.swift`). Only on demand, and skipped in every
/// other run (docs/testing.md):
///
///     TEST_RUNNER_ACCESSIBILITY_AUDIT=1 ONLY=AccessibilityAudit Scripts/build.sh ui macro
///
/// `ACCESSIBILITY_AUDIT=contrast` adds the contrast check, for a simulator with Increase Contrast on.
nonisolated final class AccessibilityAudit: XCTestCase {
    /// The sample person with the recommended plan started, so Today and Plan have targets.
    static let seed = ["-seedSampleData", "-seedPlan"]

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
        try audit("today", Self.seed + ["-seedToday"], ready: "today.calories")
    }

    @MainActor
    func testComposerWhileTyping() throws {
        try audit("composer", Self.seed + ["-seedToday"], ready: "today.composer", pages: 1) { app in
            app.element("today.composer").type("banana")
            app.element("today.match.0").waitToAppear()
        }
    }

    @MainActor
    func testLogger() throws {
        try audit("logger", Self.seed + ["-log", "search"], ready: "logger.search", pages: 1) { app in
            app.foodSearchField().type("oat")
            app.element("logger.results").waitToAppear()
        }
    }

    @MainActor
    func testLog() throws {
        try audit("log", Self.seed + ["-tab", "log", "-daysAgo", "1"], ready: "log.entry")
    }

    @MainActor
    func testPlan() throws {
        try audit("plan", Self.seed + ["-tab", "plan"], ready: "plan.kcal", pages: 5)
    }

    @MainActor
    func testProgress() throws {
        try audit("progress", Self.seed + ["-tab", "progress"], ready: "progress.trendWeight", pages: 5)
    }

    @MainActor
    func testYourShape() throws {
        try audit("shape", Self.seed + ["-tab", "progress", "-showShape"], ready: "progress.shapeScreen", pages: 3)
    }

    @MainActor
    func testTargetsSheet() throws {
        try audit("targets", Self.seed + ["-tab", "plan", "-sheet", "targets"], ready: "targets.kcal", pages: 3)
    }

    @MainActor
    func testSettings() throws {
        try audit("settings", Self.seed + ["-showSettings"], ready: "settings.showAllMacros")
    }

    @MainActor
    func testMealPlan() throws {
        try audit("mealPlan", Self.seed + ["-seedMealPlan", "-tab", "plan", "-mealPlan", "week"], ready: "mealPlan.page", pages: 3)
    }

    /// Launches the screen in each appearance (`then` brings it to the state under test) and audits
    /// it, and again a screen further down each time, up to `pages` screens.
    @MainActor
    func audit(_ screen: String, _ arguments: [String], ready: String, pages: Int = 4, then: (XCUIApplication) -> Void = { _ in }) throws {
        let contrast = ProcessInfo.processInfo.environment["ACCESSIBILITY_AUDIT"] == "contrast"
        for appearance in [XCUIDevice.Appearance.dark, .light] {
            // Set before the launch: a running app doesn't take it up.
            XCUIDevice.shared.appearance = appearance
            let app = XCUIApplication.launched(arguments)
            app.element(ready).waitToAppear(timeout: 40)
            then(app)
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
