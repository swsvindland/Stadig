import XCTest

/// A session from Today to the history it leaves.
nonisolated final class SessionUITests: XCTestCase {
    @MainActor
    func testTheFirstSessionCountsWhenEnded() {
        let app = XCUIApplication.launched(["-onboarded"])
        let end = app.buttons["session.end"].waitToAppear()
        let firstPart = app.element("session.part").waitToAppear().label
        XCTAssertTrue(firstPart.hasPrefix("Part 1 of"), firstPart)
        for _ in 0..<3 { app.answerStep() }

        end.tap()
        app.menuButton("session.endConfirm", title: "End session").waitToAppear(timeout: 5).tap()
        end.waitToDisappear()

        // Placement ended early still counts: today is done.
        app.element("today.done").waitToAppear(timeout: 10)
        XCTAssertFalse(app.buttons["today.start"].exists)
    }

    @MainActor
    func testASessionAnsweredToTheEndShowsItsSummary() {
        // -steps answers the session (right, except every third) to reach the end without tapping.
        let app = XCUIApplication.launched(["-onboarded", "-courses", "maths", "-steps", "400"])
        let summary = app.element("summary.title").waitToAppear(timeout: 60)
        XCTAssertEqual(summary.label, "Session done")
        app.buttons["summary.done"].tap()
        app.element("today.done").waitToAppear(timeout: 10)
    }

    @MainActor
    func testStartingFromTodayOpensTheSession() {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.settings").waitToAppear()
        // A study day has a Start button; a rest day or one already done has "Study anyway".
        let start = app.buttons["today.start"]
        if start.waitForExistence(timeout: 5) {
            start.tap()
        } else {
            app.buttons["today.studyAnyway"].waitToAppear(timeout: 5).tap()
            app.menuButton("today.studyAnyway.maths", title: "Maths").waitToAppear(timeout: 5).tap()
        }
        app.buttons["session.end"].waitToAppear()
        app.element("session.part").waitToAppear()
    }
}
