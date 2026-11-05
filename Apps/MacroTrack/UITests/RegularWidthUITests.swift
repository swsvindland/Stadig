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

    /// A food opened from the hours is a look, not a change of plan: the logger under it comes back
    /// as it was, with the cursor in its search. A review is kept the same way, and a simulator
    /// can't run the model to make one, so what's typed stands in for it.
    @MainActor
    func testAFoodOpenedBesideTheLoggerLeavesItAsItWas() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1", "-log", "search"])
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.food").waitToAppear()

        app.scrollTo(app.element("log.entry"), beside: app.element("log.list")).waitToAppear().tap()
        let cancel = app.element("entryEditor.cancel").waitToAppear()
        for hidden in ["logger.done", "logger.search", "logger.pickTime"] {
            XCTAssertFalse(app.element(hidden).isEnabled, "\(hidden) can't be reached under the food")
        }

        cancel.tap()
        cancel.waitToDisappear()
        XCTAssertEqual(search.waitToAppear().value as? String, "banana")
        app.typeText(" raw")
        XCTAssertEqual(search.value as? String, "banana raw", "the cursor came back to the search")
    }

    /// The same with an amount open in the pane: it's back, with what was typed.
    @MainActor
    func testAnAmountComesBackFromUnderAFood() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1", "-log", "search"])
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.food").waitToAppear().tap()
        let add = app.element("portion.add").waitToAppear()
        app.element("amount.key.7").tap()

        app.scrollTo(app.element("log.entry"), beside: app.element("log.list")).waitToAppear().tap()
        let cancel = app.element("entryEditor.cancel").waitToAppear()
        cancel.tap()
        cancel.waitToDisappear()

        add.waitToAppear()
        XCTAssertEqual(app.element("amount.quantity").value as? String, "7 nlea serving", "as it was left")
    }

    /// An hour's + or ⌘L asks for the logger: it shows at once, rather than under the food open.
    @MainActor
    func testAskingForTheLoggerShowsItOverAFoodsAmount() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1"])
        app.element("log.list").waitToAppear()
        let food = app.scrollTo(app.element("log.entry"), beside: app.element("log.list")).waitToAppear()
        let save = app.element("entryEditor.save")
        let done = app.element("logger.done")

        food.tap()
        save.waitToAppear()
        app.scrollTo(app.element("log.add.20"), beside: app.element("log.list")).waitToAppear().tap()
        save.waitToDisappear()
        done.waitToAppear()

        // Over a logger already open, where nothing about `logger` changes.
        app.scrollTo(food, beside: app.element("log.list")).waitToAppear().tap()
        save.waitToAppear()
        app.typeKey("l", modifierFlags: .command)
        save.waitToDisappear()
        done.waitToAppear()
    }

    /// While a food is open over the logger there's nowhere to show a toast, so its few seconds
    /// don't run under there: Undo comes back with the logger.
    @MainActor
    func testUndoOutlastsAFoodOpenedOverTheLogger() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1", "-log", "search", "-toastSeconds", "5"])
        let food = app.scrollTo(app.element("log.entry"), beside: app.element("log.list")).waitToAppear()
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()
        app.element("toast.undo").waitToAppear()

        food.tap()
        let cancel = app.element("entryEditor.cancel").waitToAppear()
        Thread.sleep(forTimeInterval: 7)
        cancel.tap()

        app.element("toast.undo").waitToAppear()
    }

    /// View > Show Inspector with nothing beside the hours: the pane opens on the logger, rather
    /// than the menu doing nothing, and the same command closes it.
    @MainActor
    func testShowInspectorOpensThePane() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log"])
        app.element("log.list").waitToAppear()
        let done = app.element("logger.done")
        XCTAssertFalse(done.exists)

        app.typeKey("i", modifierFlags: [.command, .control])
        done.waitToAppear()

        app.typeKey("i", modifierFlags: [.command, .control])
        done.waitToDisappear()
    }

    /// The toolbar's button for the way the pane opened with, once it's gone back to its search.
    @MainActor
    func testTheToolbarFindsTheWayThePaneOpenedWith() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log"])
        app.logButton("quickAdd").tap()
        let kcal = app.element("quickAdd.kcal").waitToAppear()
        kcal.type("250")
        app.closeNumberPad()
        app.element("quickAdd.add").waitToAppear().tap()
        kcal.waitToDisappear()

        app.logButton("quickAdd").tap()
        kcal.waitToAppear()
    }

    /// An hour's + aims the pane at that hour and leaves it as it is, on any way of logging: an AI
    /// review would otherwise go with it.
    @MainActor
    func testAnHoursPlusLeavesThePaneAsItIs() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1"])
        app.logButton("quickAdd").tap()
        let kcal = app.element("quickAdd.kcal").waitToAppear()
        kcal.type("250")
        app.closeNumberPad()

        app.scrollTo(app.element("log.add.20")).waitToAppear().tap()

        XCTAssertEqual(kcal.waitToAppear().value as? String, "250")
    }

    /// Return straight after typing, before the rows for what was typed are in, waits for them.
    @MainActor
    func testReturnInThePaneLogsTheBestMatchOfWhatsTyped() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-log", "search", "-toastSeconds", "30"])
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana raw\n")

        app.element("toast.message", labelContaining: "Logged Bananas").waitToAppear()
        XCTAssertEqual(search.value as? String, "", "the search is clear for the next one")
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

    /// A weigh-in asked for from the menu opens over the pane, as the toolbar's does: the logger
    /// isn't a sheet to clear away, and what's in it would be lost with it.
    @MainActor
    func testTheWeighInShortcutLeavesThePaneAsItIs() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-log", "search"])
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.food").waitToAppear()

        app.typeKey("m", modifierFlags: [.command, .shift])
        app.element("weighIn.save").waitToAppear()
        app.element("weighIn.cancel").tap()
        app.element("weighIn.save").waitToDisappear()

        XCTAssertEqual(app.foodSearchField().value as? String, "banana")
    }

    /// With the columns showing, a row's numbers are read out with their names.
    @MainActor
    func testARowsColumnsSayWhatTheyAre() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-daysAgo", "1"])
        let food = app.scrollTo(app.element("log.entry"), beside: app.element("log.list")).waitToAppear()
        for word in ["calories", "grams protein", "grams carbs", "grams fat"] { XCTAssertTrue(food.label.contains(word), food.label) }
    }

    /// With no meals saved, Foods' Meals says where one's saved from, which isn't Today now.
    @MainActor
    func testFoodsMealsSaysWhereToSaveOne() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-sampleNoMeals", "-tab", "foods"])
        app.element("foods.scope").waitToAppear().buttons["Meals"].tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'saved as a meal'")).firstMatch.waitToAppear()
        XCTAssertTrue(note.label.contains("in Log"), note.label)
        XCTAssertFalse(note.label.contains("Today"), note.label)
    }

    /// A food corrected from its row in the hours, under the same food in a review beside it: the
    /// review comes back with the new numbers, which is what its Log says and what's logged.
    @MainActor
    func testACorrectionFromTheHoursReachesTheReviewBesideThem() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedReview", "-tab", "log", "-log", "describe"])
        // Logged once, so it's in the hours, and open again on a fresh review of it.
        app.element("review.log").waitToAppear().tap()
        app.element("toast.message", labelContaining: "Logged Beef stew").waitToAppear()
        app.element("logger.done").waitToAppear().tap()
        app.toolbarItem("toolbar.describe", title: "Describe a Meal").tap()
        let log = app.element("review.log").waitToAppear()
        XCTAssertTrue(log.label.contains("300 kcal"), log.label)

        app.scrollTo(app.logEntry(containing: "Beef stew"), beside: app.element("log.list")).waitToAppear().tap()
        app.element("portion.editFood").waitToAppear().tap()
        let kcal = app.element("foodEditor.kcal").waitToAppear()
        // The number sits at the field's right edge, so a tap there leaves the cursor after it.
        kcal.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        kcal.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "360")
        app.closeNumberPad()
        let save = app.element("foodEditor.save").waitToAppear()
        save.tap()
        save.waitToDisappear()
        app.element("entryEditor.cancel").waitToAppear().tap()

        XCTAssertTrue(app.element("review.log", labelContaining: "360 kcal").waitToAppear().exists)
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
