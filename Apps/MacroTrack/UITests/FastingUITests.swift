import XCTest

/// Meal timing and fasts on Today, from seeded data.
nonisolated final class FastingUITests: XCTestCase {
    @MainActor
    func testStartingAFastFromTodayAndEndingIt() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedMealTiming"])
        let summary = app.element("today.calories").waitToAppear()
        let beside = XCUIApplication.isPad ? summary : nil

        // The time since the last meal, and a fast from it.
        app.scrollTo(app.element("today.sinceLastMeal"), beside: beside).waitToAppear()
        app.element("today.startFast").waitToAppear().tap()
        app.element("fast.goal.16").waitToAppear().tap()
        app.element("fast.start").waitToAppear().tap()

        // Today follows it as a ring toward the goal, with its phase.
        let fast = app.scrollTo(app.element("today.fast"), beside: beside).waitToAppear()
        XCTAssertTrue(fast.label.contains("of 16 h"), fast.label)
        // The start's confirmation floats over the bottom of the list: End waits for it to go.
        app.element("toast.message").waitToDisappear()
        app.scrollTo(app.element("today.endFast"), beside: beside).waitToAppear().tap()
        app.element("today.sinceLastMeal").waitToAppear()
    }

    @MainActor
    func testTheWeeksMealTimingOnProgress() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedMealTiming", "-tab", "progress"])

        let card = app.scrollTo(app.element("progress.mealTiming")).waitToAppear()
        // The sample eats three meals and two snacks a day, logged in full most days.
        XCTAssertTrue(card.staticTexts["Meals a day"].exists && card.staticTexts["Overnight fast"].exists)
        // And the 16-hour fast it ran earlier in the week.
        XCTAssertTrue(card.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '16 h fast'")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Meal timing on Progress"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testTheFastScreenShowsWhereARunningFastIs() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedFast", "-showFast"])

        let elapsed = app.element("fast.elapsed").waitToAppear()
        XCTAssertTrue(elapsed.label.contains("to 24 h") || elapsed.label.contains("reached"), elapsed.label)
        // Every phase is listed, with what's likely happening in each.
        app.scrollTo(app.element("fast.phase.3")).waitToAppear()
        XCTAssertTrue(app.element("fast.phase.3").label.contains("Ketosis"))
        app.element("fast.done").waitToAppear().tap()
        app.element("today.fast").waitToAppear()
    }
}
