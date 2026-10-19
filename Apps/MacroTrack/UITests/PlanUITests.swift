import XCTest

/// The phase plan and the supplements, from seeded data.
nonisolated final class PlanUITests: XCTestCase {
    @MainActor
    func testStartingTheRecommendedPhaseShowsItsFirstWeek() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "plan", "-unlocked"])

        app.element("plan.start").waitToAppear().tap()

        let week = app.element("plan.week").waitToAppear()
        XCTAssertTrue(week.label.hasPrefix("Week 1 of"), week.label)
        XCTAssertTrue(app.element("plan.currentPhase").exists)
        XCTAssertFalse(app.element("plan.start").exists, "the recommendation gives way to the plan")
    }

    @MainActor
    func testTickingOffASupplementOnToday() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedSupplements"])
        let summary = app.element("today.calories").waitToAppear()

        // An iPad's supplements are in the column beside the log, with the summary.
        let open = app.element("supplements.dose", labelContaining: "not taken yet")
        app.scrollTo(open, beside: XCUIApplication.isPad ? summary : nil).waitToAppear().tap()
        // Its label says so: one fewer left to take.
        let taken = app.element("supplements.dose", labelContaining: ", taken")
        XCTAssertTrue(taken.waitToAppear().exists)
    }
}
