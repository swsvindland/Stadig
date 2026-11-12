import XCTest

/// The first screens: every tab with sample data, and setup on a first run.
nonisolated final class LaunchAndOnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSeededLaunchShowsEveryTab() {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        XCTAssertTrue(app.buttons["today.startSession"].waitForExistence(timeout: 5))

        app.openTab("Plan")
        app.element("plan.screen").waitToAppear()
        XCTAssertTrue(app.element("plan.day").waitForExistence(timeout: 5), "The block's days are listed")

        app.openTab("Progress")
        let progress = app.element("progress.screen").waitToAppear()
        // On the iPad it's the last card of a lazy grid, made only once it's scrolled near.
        let history = app.element("progress.history")
        for _ in 0..<4 where !history.waitForExistence(timeout: 3) { progress.swipeUp() }
        XCTAssertTrue(history.exists)

        app.openTab("Body")
        app.element("body.screen").waitToAppear()
        XCTAssertTrue(app.element("body.measurement").waitForExistence(timeout: 5), "The sample measurements are listed")

        app.openTab("Today")
        app.element("today.screen").waitToAppear()
    }

    /// A second device, with the person's training in iCloud: the wait for it rather than onboarding,
    /// with a way out to set up as new.
    @MainActor
    func testASecondDeviceWaitsForICloudBeforeOnboarding() {
        let app = XCUIApplication.launched(["-simulateICloudData"])
        app.element("icloud.waiting").waitToAppear()
        XCTAssertFalse(app.buttons["onboarding.next"].exists, "no onboarding over data on its way")

        app.buttons["icloud.setUpAsNew"].waitToAppear().tap()
        XCTAssertEqual(app.buttons["onboarding.next"].waitToAppear().label, "Get started")
        XCTAssertFalse(app.element("icloud.waiting").exists)
    }

    @MainActor
    func testFirstRunOnboardingReachesToday() {
        let app = XCUIApplication.launched()
        let next = app.buttons["onboarding.next"].waitToAppear()
        XCTAssertEqual(next.label, "Get started")
        next.tap()

        // A goal is the one answer the steps need.
        XCTAssertFalse(next.isEnabled)
        app.buttons["onboarding.goalStronger"].waitToAppear().tap()
        XCTAssertTrue(next.isEnabled)

        // Every one-tap answer can be found by its identifier: one card picked on each of those steps.
        // One not picked yet, so the check below is the tap's doing (equipment and experience start
        // with their first card picked).
        for step in ["onboarding.focus", "onboarding.equipment", "onboarding.experience", "onboarding.phase"] {
            let unpicked = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == NO", step)).firstMatch
            for _ in 0..<4 where !unpicked.waitForExistence(timeout: 2) {
                next.tap()
            }
            // Found again by its own identifier: once picked, it no longer matches the query above.
            let card = app.buttons[unpicked.waitToAppear().identifier]
            card.tap()
            XCTAssertTrue(card.wait(for: \.isSelected, toEqual: true, timeout: 5), "\(step) shows as picked")
        }

        // Through the rest on their defaults, to the last step.
        for _ in 0..<12 where next.label != "Start the assessment" {
            next.tap()
        }
        XCTAssertEqual(next.label, "Start the assessment")
        next.tap()

        app.element("today.screen").waitToAppear()
        XCTAssertTrue(app.buttons["today.startSession"].waitForExistence(timeout: 10), "Today offers the first assessment session")
        // An iPad's tab bar has Plan inside its Training section.
        XCTAssertTrue(app.tabButton(XCUIApplication.isPad ? "Training" : "Plan").exists)
    }
}
