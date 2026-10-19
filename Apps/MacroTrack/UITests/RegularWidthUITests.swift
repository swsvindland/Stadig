import XCTest

/// The iPad's regular-width layout: the sidebar's destinations, tables and inspectors. The iPhone
/// keeps its tab bar (AppUITests), so these skip there.
nonisolated final class RegularWidthUITests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the regular-width layout is the iPad's")
    }

    @MainActor
    func testFoodsFindsAndLogsAFood() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "foods"])

        app.element("foods.table").waitToAppear()
        let search = app.searchFields.firstMatch.waitToAppear()
        search.tap()
        search.typeText("banana raw")
        // The best match is selected, with its portion and nutrients beside the table.
        let log = app.element("foods.log").waitToAppear()
        XCTAssertTrue(log.label.contains("kcal"), log.label)
        log.tap()

        let toast = app.element("toast.message").waitToAppear()
        XCTAssertTrue(toast.label.contains("Logged"), toast.label)
    }

    @MainActor
    func testTodaysLogIsATableEditedBesideIt() {
        continueAfterFailure = false
        // Yesterday has the sample's meals in it.
        let app = XCUIApplication.launched(["-seedSampleData", "-daysAgo", "1"])

        let log = app.element("today.log").waitToAppear()
        XCTAssertTrue(app.element("today.calories").exists, "the summary is beside the log")
        XCTAssertTrue(app.element("today.datePicker").exists)
        XCTAssertTrue(app.element("toolbar.logFood").exists, "every way to log is in the toolbar")

        log.cells.element(boundBy: 1).waitToAppear().tap()
        app.element("entryEditor.save").waitToAppear()
        app.element("entryEditor.cancel").tap()
        app.element("entryEditor.save").waitToDisappear()
    }

    @MainActor
    func testHistoryShowsEveryDayAndTheSelectedDaysLog() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "history"])

        let table = app.element("history.table").waitToAppear()
        XCTAssertGreaterThan(table.cells.count, 20, "three and a half weeks of days")
        app.element("history.day").waitToAppear()
        app.element("history.showInToday").waitToAppear().tap()
        app.element("today.log").waitToAppear()
    }

    @MainActor
    func testTheMealPlanShowsTheWeekGroceriesAndPrepTogether() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedMealPlan", "-tab", "mealplan"])

        app.element("mealPlan.week").waitToAppear()
        XCTAssertTrue(app.element("mealPlan.groceries").exists, "the grocery list is beside the week, not behind a picker")
        XCTAssertFalse(app.element("mealPlan.page").exists)
    }
}
