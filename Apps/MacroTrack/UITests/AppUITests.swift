import XCTest

/// The app as a person meets it: the first run, and every tab with data in it.
nonisolated final class AppUITests: XCTestCase {
    @MainActor
    func testSeededLaunchShowsEachTab() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])

        app.element("today.calories").waitToAppear()
        XCTAssertTrue(app.logButton("search").exists, "logging is one tap away on Today")

        app.openTab("Log")
        app.element("log.list").waitToAppear()

        app.openTab("Plan")
        // Three and a half weeks: the assessment is done and a phase is recommended.
        app.element("plan.start").waitToAppear()

        app.openTab("Progress")
        app.element("progress.trendWeight").waitToAppear()
        XCTAssertTrue(app.element("progress.range").exists, "weeks of weigh-ins draw a chart")

        app.openTab("Today")
        app.element("today.calories").waitToAppear()
    }

    /// A second device, with the person's log in iCloud: the wait for it rather than onboarding, with
    /// a way out to set up as new.
    @MainActor
    func testASecondDeviceWaitsForICloudBeforeOnboarding() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-simulateICloudData"])
        app.element("icloud.waiting").waitToAppear()
        XCTAssertFalse(app.element("onboarding.getStarted").exists, "no onboarding over data on its way")

        app.buttons["icloud.setUpAsNew"].waitToAppear().tap()
        app.element("onboarding.getStarted").waitToAppear()
        XCTAssertFalse(app.element("icloud.waiting").exists)
    }

    @MainActor
    func testFirstRunOnboardingReachesToday() {
        continueAfterFailure = false
        let app = XCUIApplication.launched()

        app.element("onboarding.getStarted").waitToAppear().tap()
        app.element("onboarding.goal.leaner").waitToAppear().tap()
        // The region is the US, so the units start as pounds and inches.
        app.element("onboarding.height").type("71")
        app.closeNumberPad()
        app.element("onboarding.continue").tap()

        app.element("onboarding.history.none").waitToAppear().tap()
        app.element("onboarding.weight").type("181.4")
        app.closeNumberPad()
        app.element("onboarding.continue").tap()

        // No Health under UI tests: only "Not now".
        let connect = app.element("onboarding.connectHealth").waitToAppear()
        XCTAssertFalse(connect.isEnabled)
        app.element("onboarding.notNow").tap()

        app.element("today.calories").waitToAppear()
        XCTAssertTrue(app.logButton("search").exists)
        let weight = app.element("today.weight").waitToAppear()
        XCTAssertTrue(weight.label.contains("181.4 lb"), "the first weigh-in is today's: \(weight.label)")
    }
}
