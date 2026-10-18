import XCTest

/// The core loop: today's session started, sets logged and rated, then finished, minimized or
/// thrown away.
nonisolated final class SessionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStartingFromTodayLoggingAndFinishingSavesTheSession() {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.buttons["today.startSession"].waitToAppear(timeout: XCUIApplication.firstScreenTimeout).tap()
        app.element("session.screen").waitToAppear()

        app.logOneRatedSet()
        // Rated: the rest starts, and skipping it brings the next set.
        app.buttons["rest.skip"].waitToAppear().tap()
        app.buttons["logger.ratingOrange"].waitToAppear()
        XCTAssertTrue(app.buttons["session.loggedSet"].exists, "The rated set shows as logged")

        app.buttons["session.options"].tap()
        app.buttons["session.finishNow"].waitToAppear().tap()
        app.buttons["feedback.save"].waitToAppear().tap()

        // Saved: the summary, then Today again with nothing left running.
        app.buttons["summary.done"].waitToAppear().tap()
        app.element("today.screen").waitToAppear()
        XCTAssertTrue(app.buttons["today.startSession"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["today.resumeSession"].exists)
    }

    @MainActor
    func testMinimizingAndResumingASession() {
        let app = XCUIApplication.launched(["-seedSampleData", "-startSession"])
        app.element("session.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        app.logOneRatedSet()

        app.buttons["session.minimize"].tap()
        app.element("session.screen").waitToDisappear()
        let resume = app.buttons["today.resumeSession"].waitToAppear()
        XCTAssertTrue(app.element("session.accessory").exists, "The tab bar keeps the session within reach")

        resume.tap()
        app.element("session.screen").waitToAppear()
        XCTAssertTrue(app.buttons["session.loggedSet"].exists, "What was logged is still there")
    }

    @MainActor
    func testDiscardingASessionKeepsNothing() {
        let app = XCUIApplication.launched(["-seedSampleData", "-startSession"])
        app.element("session.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        app.logOneRatedSet()

        app.buttons["session.options"].tap()
        app.buttons["session.discard"].waitToAppear().tap()
        // The dialog's button can be in the tree twice while it animates in.
        app.buttons["session.confirmDiscard"].firstMatch.waitToAppear().tap()

        app.element("today.screen").waitToAppear()
        XCTAssertTrue(app.buttons["today.startSession"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["today.resumeSession"].exists)
        XCTAssertFalse(app.buttons["summary.done"].exists, "Nothing was saved, so there's no summary")
    }

    @MainActor
    func testCorrectingALoggedSet() {
        let app = XCUIApplication.launched(["-seedSampleData", "-startSession"])
        app.element("session.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        app.logOneRatedSet()
        app.buttons["rest.skip"].waitToAppear().tap()

        // The first set logged: a warm-up or the rated set, either opens for a correction.
        let logged = app.buttons.matching(identifier: "session.loggedSet").firstMatch.waitToAppear()
        let before = logged.label
        logged.tap()
        app.buttons["editSet.repsMore"].waitToAppear().tap()
        app.buttons["editSet.save"].tap()
        app.buttons["editSet.save"].waitToDisappear()
        XCTAssertNotEqual(logged.label, before, "The row shows the corrected reps")
    }
}
