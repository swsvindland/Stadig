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
        let search = app.foodSearchField()
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
    func testFoodsListsSavedMealsAndLogsOneFromItsInspector() {
        continueAfterFailure = false
        // The sample saves its breakfast and lunch as meals.
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "foods"])

        app.element("foods.scope").waitToAppear().buttons["Meals"].tap()
        app.element("foods.meal", labelContaining: "Chicken and rice").waitToAppear().tap()
        let log = app.element("savedMeal.log").waitToAppear()
        XCTAssertTrue(log.label.contains("3 foods"), log.label)
        // One food left out for this time.
        app.element("savedMeal.include").tap()
        XCTAssertTrue(app.element("savedMeal.log", labelContaining: "2 of 3").waitToAppear().exists)
        log.tap()

        app.element("toast.message", labelContaining: "Logged Chicken and rice, 2 of 3").waitToAppear()
    }

    @MainActor
    func testTheLogHasColumnsAndEditsAnEntry() {
        continueAfterFailure = false
        // Yesterday has the sample's meals in it.
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1"])

        app.element("log.list").waitToAppear()
        XCTAssertTrue(app.element("toolbar.logFood").waitToAppear().exists, "every way to log is in the toolbar")
        app.shot("log-wide")

        app.scrollTo(app.element("log.entry")).waitToAppear().tap()
        app.element("entryEditor.save").waitToAppear()
        app.element("entryEditor.cancel").tap()
        app.element("entryEditor.save").waitToDisappear()
    }

    /// A food's amount takes the pane, and the toast its place in it: the toast is back with the
    /// search, with its Undo, rather than lost to the amount opening.
    @MainActor
    func testUndoComesBackWithThePaneAfterAnAmount() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-log", "search", "-toastSeconds", "30"])
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()
        app.element("toast.undo").waitToAppear()

        search.typeText("apple")
        app.element("logger.food").waitToAppear().tap()
        let close = app.element("portion.close").waitToAppear()
        close.tap()
        close.waitToDisappear()

        app.element("toast.undo").waitToAppear()
    }

    /// The pane stays open beside the selection bar, so what it opened can go from under it. Save
    /// would put the food back where it was, or bring it back, with no toast and no Undo.
    @MainActor
    func testMovingAFoodClosesItsPane() {
        continueAfterFailure = false
        let (app, food) = openFoodInThePane()

        food.press(forDuration: 0.8)
        app.element("selection.to.tomorrow").waitToAppear().tap()

        app.element("entryEditor.save").waitToDisappear()
        app.element("toast.message", labelContaining: "Moved").waitToAppear()
    }

    @MainActor
    func testDeletingAFoodClosesItsPane() {
        continueAfterFailure = false
        let (app, food) = openFoodInThePane()

        food.press(forDuration: 0.8)
        app.element("selection.delete").waitToAppear().tap()

        app.element("entryEditor.save").waitToDisappear()
        app.element("toast.message", labelContaining: "Deleted").waitToAppear()
    }

    /// Yesterday, which has the sample's meals in it, with its first food open beside the hours.
    @MainActor
    private func openFoodInThePane() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1", "-toastSeconds", "30"])
        app.element("log.list").waitToAppear()
        let food = app.scrollTo(app.element("log.entry")).waitToAppear()
        food.tap()
        app.element("entryEditor.save").waitToAppear()
        return (app, food)
    }

    /// The pane is part of the Log tab: leaving it closes the pane, so a food logged on another tab
    /// says so there, with its Undo, rather than in a pane out of sight.
    @MainActor
    func testLeavingTheLogClosesThePane() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-toastSeconds", "30"])
        app.scrollTo(app.element("log.add.20")).waitToAppear().tap()
        app.element("logger.done").waitToAppear()

        app.openTab("Foods")
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana raw")
        app.element("foods.log").waitToAppear().tap()
        app.element("toast.undo").waitToAppear()

        // ⌘2: the search field has the sidebar's toggle out of reach.
        app.typeKey("2", modifierFlags: .command)
        app.element("log.list").waitToAppear()
        XCTAssertFalse(app.element("logger.done").waitForExistence(timeout: 2), "the pane stayed closed")
    }

    @MainActor
    func testTheDaySortsFromItsMenu() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1"])
        let hour = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'log.hour.'")).firstMatch
        hour.waitToAppear()

        app.toolbarItem("log.sort", title: "Sort").tap()
        app.buttons["Calories"].waitToAppear().tap()
        hour.waitToDisappear()
        app.element("log.entry").waitToAppear()
        app.shot("log-sorted")

        app.toolbarItem("log.sort", title: "Sort").tap()
        app.buttons["Time"].waitToAppear().tap()
        hour.waitToAppear()
    }

    @MainActor
    func testHistoryShowsEveryDayAndTheSelectedDaysLog() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "history"])

        let table = app.element("history.table").waitToAppear()
        XCTAssertGreaterThan(table.cells.count, 20, "three and a half weeks of days")
        // Show in Log ends the day's log, at the foot of the pane: up from the screen's edge.
        let day = app.element("history.day").waitToAppear()
        day.swipeUp(velocity: .slow)
        app.element("history.showInLog").waitToAppear().tap()
        app.element("log.list").waitToAppear()
    }

    /// The table's own way there: a row's menu, as a right-click has it. The Mac's double-click takes
    /// the same path, and the Mac has no UI tests.
    @MainActor
    func testATableRowsMenuShowsItsDayInTheLog() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "history"])

        // Two cells of headers, then the newest day: this row is yesterday's ("Tue, Nov 3").
        let row = app.element("history.table").waitToAppear().cells.element(boundBy: 3).waitToAppear()
        let date = try XCTUnwrap(row.staticTexts.firstMatch.label.split(separator: " ").last)
        row.press(forDuration: 1.2)
        // The pane beside the table has a button of this name too.
        let menuItem = NSPredicate(format: "label == 'Show in Log' AND identifier != 'history.showInLog'")
        app.buttons.matching(menuItem).firstMatch.waitToAppear().tap()

        // The Log tab, on that day ("Tuesday, November 3. Choose a day").
        let title = app.element("log.title").waitToAppear().label
        XCTAssertFalse(title.hasPrefix("Today"), title)
        XCTAssertTrue(title.contains(" \(date)."), title)
    }

    /// ⌘⇧M follows the day: a day to come has nothing to weigh, and the sheet would throw a weight
    /// away. Going from each to the other shows the menu keeps up with the day.
    @MainActor
    func testTheWeighInShortcutIsOffOnADayAhead() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "-1"])
        app.element("log.backToToday").waitToAppear()
        let weigh = app.element("weighIn.save")

        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertFalse(weigh.waitForExistence(timeout: 2), "nothing to weigh tomorrow")

        app.element("log.backToToday").tap()
        app.typeKey("m", modifierFlags: [.command, .shift])
        weigh.waitToAppear()
        app.element("weighIn.cancel").tap()
        weigh.waitToDisappear()

        // ⌘]: tomorrow again.
        app.typeKey("]", modifierFlags: .command)
        app.element("log.backToToday").waitToAppear()
        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertFalse(weigh.waitForExistence(timeout: 2), "nothing to weigh tomorrow")
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
