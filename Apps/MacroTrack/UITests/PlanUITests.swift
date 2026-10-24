import XCTest

/// The phase plan, meal prep and the supplements, from seeded data.
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
    func testARequestForOneJapaneseCurryPlansJustThat() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "plan", "-unlocked"])

        app.scrollTo(app.element("mealPrep.planWeek")).waitToAppear().tap()
        app.element("mealPlanSetup.make").waitToAppear()
        // Below the meals, the diet and what to leave out: the form makes it once it's scrolled to.
        app.scrollTo(app.element("mealPlanSetup.request")).waitToAppear()
            .type("combine or same meal for lunch and dinner, just do a high protein Japanese curry")
        app.element("mealPlanSetup.make").tap()
        app.element("mealPlanSetup.make").waitToDisappear()

        // One batch of what was asked for, for every lunch and dinner.
        let dishes = app.descendants(matching: .any).matching(identifier: "mealPrep.dish")
        let dish = app.scrollTo(dishes.firstMatch).waitToAppear()
        XCTAssertEqual(dishes.count, 1, "one dish, not two")
        XCTAssertTrue(dish.label.hasPrefix("Japanese curry"), dish.label)
    }

    @MainActor
    func testOneDishAllWeekFromTheSetup() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "plan", "-unlocked"])

        app.scrollTo(app.element("mealPrep.planWeek")).waitToAppear().tap()
        let oneDish = app.switches["mealPlanSetup.oneDish"].waitToAppear()
        XCTAssertEqual(oneDish.value as? String, "0", "two dishes taking turns, unless asked")
        // The switch itself: a tap on the row's middle lands on its label.
        oneDish.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).press(forDuration: 0.15)
        XCTAssertEqual(oneDish.value as? String, "1")
        app.element("mealPlanSetup.make").tap()
        app.element("mealPlanSetup.make").waitToDisappear()

        let dishes = app.descendants(matching: .any).matching(identifier: "mealPrep.dish")
        app.scrollTo(dishes.firstMatch).waitToAppear()
        XCTAssertEqual(dishes.count, 1, "one dish for every lunch and dinner")
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
