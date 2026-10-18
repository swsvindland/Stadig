import XCTest

/// The first run: setup, then the first session, which is the onboarding's last step.
nonisolated final class OnboardingUITests: XCTestCase {
    @MainActor
    func testFirstRunSetupStartsTheFirstSession() {
        let app = XCUIApplication.launched()
        app.element("onboarding.welcomeTitle").waitToAppear()
        let next = app.buttons["onboarding.next"]
        next.tap()

        // Two courses keep the setup short: maths and Japanese, the rest off.
        app.element("onboarding.coursesTitle").waitToAppear(timeout: 10)
        for course in ["writing", "reading"] {
            app.scroll(to: app.segmentedControls["onboarding.course.\(course)"]).buttons["Off"].tap()
        }
        next.tap()

        app.element("onboarding.scheduleTitle").waitToAppear(timeout: 10)
        app.segmentedControls["onboarding.sessionLength"].buttons.element(boundBy: 0).tap()
        next.tap()

        app.element("onboarding.languagesTitle").waitToAppear(timeout: 10)
        app.scroll(to: app.segmentedControls["onboarding.kana"]).buttons["Yes"].tap()
        next.tap()

        app.element("onboarding.mathsTitle").waitToAppear(timeout: 10)
        next.tap()

        app.element("onboarding.readyTitle").waitToAppear(timeout: 10)
        XCTAssertFalse(app.element("onboarding.writingTitle").exists, "a course that's off has no page")
        next.tap()

        // The first session, full screen, finding the level.
        app.buttons["session.end"].waitToAppear()
        XCTAssertTrue(app.element("session.part").exists)
        XCTAssertFalse(app.element("onboarding.readyTitle").exists)
    }

    @MainActor
    func testSetupNeedsAFocusCourse() {
        let app = XCUIApplication.launched(["-onboardingPage", "courses"])
        app.element("onboarding.coursesTitle").waitToAppear()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.isEnabled)

        app.scroll(to: app.segmentedControls["onboarding.course.spanish"]).buttons["Maintenance"].tap()
        for course in ["japanese", "maths", "writing", "reading"] {
            app.scroll(to: app.segmentedControls["onboarding.course.\(course)"]).buttons["Off"].tap()
        }
        XCTAssertFalse(next.isEnabled, "Maintenance alone is reviews of nothing")

        app.segmentedControls["onboarding.course.reading"].buttons["Focus"].tap()
        XCTAssertTrue(next.isEnabled)

        app.buttons["onboarding.back"].tap()
        app.element("onboarding.welcomeTitle").waitToAppear(timeout: 10)
    }
}
