import XCTest

/// A session from Today to the history it leaves.
nonisolated final class SessionUITests: XCTestCase {
    /// Answers the step on screen the way a person would: reads a lesson, picks the first answer
    /// (or says "Don't know"), and moves on from the feedback.
    @MainActor
    func answerStep(_ app: XCUIApplication) {
        let lesson = app.buttons["lesson.continue"]
        let choice = app.buttons["question.choice.0"]
        let dontKnow = app.buttons["question.dontKnow"]
        let field = app.textFields["question.answer"]
        if lesson.exists {
            lesson.tap()
        } else if choice.exists && choice.isEnabled {
            choice.tap()
        } else if field.exists && field.isEnabled {
            field.tap()
            field.typeText("1")
            app.buttons["question.check"].tap()
        } else if dontKnow.exists {
            dontKnow.tap()
        } else if app.buttons["speak.cantSpeak"].exists {
            app.buttons["speak.cantSpeak"].tap()
        } else if app.buttons["speak.skip"].exists {
            app.buttons["speak.skip"].tap()
        }
        // A test moves on by itself; anything else shows what was right, then Continue.
        for id in ["question.continue", "speak.continue"] where app.buttons[id].waitForExistence(timeout: 1.5) {
            app.buttons[id].tap()
        }
    }

    @MainActor
    func testTheFirstSessionCountsWhenEnded() {
        let app = XCUIApplication.launched(["-onboarded"])
        let end = app.buttons["session.end"].waitToAppear()
        let firstPart = app.element("session.part").waitToAppear().label
        XCTAssertTrue(firstPart.hasPrefix("Part 1 of"), firstPart)
        for _ in 0..<3 { answerStep(app) }

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
