import XCTest

/// The app as a person meets it: the first run, every tab with data in it, and Settings.
nonisolated final class AppUITests: XCTestCase {
    @MainActor
    func testSeededLaunchShowsEachTab() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])

        app.element("today.calories").waitToAppear()
        XCTAssertTrue(app.element("quickLog.search").exists, "logging is one tap away on Today")
        XCTAssertTrue(app.element("today.nothingLogged").exists, "the sample weeks end yesterday")

        app.tabBars.buttons["Plan"].tap()
        // Three and a half weeks: the assessment is done and a phase is recommended.
        app.element("plan.start").waitToAppear()

        app.tabBars.buttons["Progress"].tap()
        app.element("progress.trendWeight").waitToAppear()
        XCTAssertTrue(app.element("progress.range").exists, "weeks of weigh-ins draw a chart")

        app.tabBars.buttons["Today"].tap()
        app.element("today.calories").waitToAppear()
    }

    @MainActor
    func testFirstRunOnboardingReachesToday() {
        continueAfterFailure = false
        let app = XCUIApplication.launched()

        app.element("onboarding.getStarted").waitToAppear().tap()
        app.element("onboarding.goal.leaner").waitToAppear().tap()
        // The region is the US, so the units start as pounds and inches.
        app.element("onboarding.height").type("71")
        app.element("onboarding.continue").tap()

        app.element("onboarding.history.none").waitToAppear().tap()
        app.element("onboarding.weight").type("181.4")
        app.element("onboarding.continue").tap()

        // No Health under UI tests: only "Not now".
        let connect = app.element("onboarding.connectHealth").waitToAppear()
        XCTAssertFalse(connect.isEnabled)
        app.element("onboarding.notNow").tap()

        app.element("today.calories").waitToAppear()
        XCTAssertTrue(app.element("quickLog.search").exists)
        let weight = app.element("today.weight").waitToAppear()
        XCTAssertTrue(weight.label.contains("181.4 lb"), "the first weigh-in is today's: \(weight.label)")
    }

    @MainActor
    func testSettingsOpenFromTodayAndClose() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])

        app.element("today.settings").waitToAppear().tap()
        let done = app.element("settings.done").waitToAppear()
        XCTAssertTrue(app.element("settings.showAllMacros").exists)
        XCTAssertTrue(app.element("settings.drinks").exists)

        done.tap()
        done.waitToDisappear()
        XCTAssertTrue(app.element("today.calories").waitToAppear().isHittable)
    }

    @MainActor
    func testAnIllnessStartedInSettingsRunsUntilItsBetter() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-showSettings"])

        app.element("settings.done").waitToAppear()
        // A tap anywhere on the row opens the menu, not only on its words: here, near its far end.
        let start = app.scrollTo(app.element("settings.startLifeMode")).waitToAppear()
        let farEnd = CGVector(dx: app.windows.firstMatch.frame.maxX - 48, dy: start.frame.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(farEnd).tap()
        app.buttons["settings.lifeMode.ill"].waitToAppear().tap()

        // An illness can be open-ended; that's how it starts.
        XCTAssertTrue(app.element("lifeMode.openEnded").waitToAppear().exists)
        app.element("lifeMode.save").tap()

        let row = app.element("settings.lifeMode").waitToAppear()
        XCTAssertTrue(row.label.contains("ongoing"), "an open-ended illness: \(row.label)")
    }

    @MainActor
    func testExportingCSVOffersToShareTheFiles() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-showSettings"])

        app.element("settings.done").waitToAppear()
        app.scrollTo(app.element("settings.exportCSV")).waitToAppear().tap()
        // The share row appears under the button, which can be the bottom of the screen.
        let share = app.scrollTo(app.element("settings.shareCSV")).waitToAppear()
        XCTAssertTrue(share.label.contains("CSV files"), share.label)
    }
}
