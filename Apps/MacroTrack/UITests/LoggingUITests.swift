import XCTest

/// Logging, end to end: a food from search, Undo, a quick add, a weigh-in, and the links the
/// widgets and controls open. On an iPad the ways to log are in Today's toolbar rather than the
/// bar above the tabs, and a search is the Foods destination.
nonisolated final class LoggingUITests: XCTestCase {
    /// Searches for a banana and logs it: on an iPhone from the logger's results, on an iPad from
    /// Foods, where Return in the search field logs the best match.
    @MainActor
    func logABanana(_ app: XCUIApplication) {
        app.logButton("search").tap()
        let search = app.foodSearchField()
        search.tap()
        if XCUIApplication.isPad {
            search.typeText("banana\n")
        } else {
            search.typeText("banana")
            app.element("logger.addFood").waitToAppear().tap()
        }
    }

    /// Back to Today once the food is logged: the iPhone's search stays up for the next food until
    /// Done; an iPad's Foods is a destination of its own, whose search, open, takes the place of
    /// the tab bar, so Go ▸ Today (⌘1) from the keyboard.
    @MainActor
    func leaveSearch(_ app: XCUIApplication) {
        if XCUIApplication.isPad {
            app.typeKey("1", modifierFlags: .command)
        } else {
            app.element("logger.done").waitToAppear().tap()
        }
    }

    /// The amount panel: it opens on the food's usual amount, selected, so the first key replaces it.
    @MainActor
    func testAnAmountIsTypedOnThePanelAndTheKeyboardComesBack() throws {
        try XCTSkipIf(XCUIApplication.isPad, "An iPad's search is the Foods destination, with its own amount")
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "search"])
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.food").waitToAppear().tap()

        app.element("amount.panel").waitToAppear()
        app.shot("amount-add")
        app.element("amount.key.2").tap()
        app.element("amount.key.5").tap()
        XCTAssertEqual((app.element("amount.quantity").value as? String)?.hasPrefix("25 "), true, "typed over what was offered")
        app.element("portion.add").tap()

        app.element("amount.panel").waitToDisappear()
        XCTAssertTrue(app.element("toast.message").waitToAppear().label.hasPrefix("Logged "))
        // The search takes the keyboard back for the next food, with no tap on its field.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard came back")
        search.typeText("oats")
        XCTAssertTrue(app.element("logger.food").waitToAppear().exists)
    }

    @MainActor
    func testAnEntrysAmountChangesOnThePanel() throws {
        try XCTSkipIf(XCUIApplication.isPad, "An iPad's Today edits an entry beside the table (RegularWidthUITests)")
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedSupplements"])
        let calories = app.element("today.calories").waitToAppear()
        let before = calories.label
        app.scrollTo(app.element("today.entry")).waitToAppear().tap()

        app.element("amount.panel").waitToAppear()
        app.shot("amount-edit")
        app.element("amount.key.9").tap()
        app.element("amount.key.0").tap()
        app.element("amount.key.0").tap()
        app.element("entryEditor.save").tap()

        app.element("amount.panel").waitToDisappear()
        calories.waitForLabel(toChangeFrom: before)
    }

    @MainActor
    func testLoggingAFoodFromSearchUpdatesToday() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        let calories = app.element("today.calories").waitToAppear()
        let before = calories.label

        logABanana(app)
        let toast = app.element("toast.message").waitToAppear()
        XCTAssertTrue(toast.label.hasPrefix("Logged "), toast.label)
        leaveSearch(app)

        calories.waitForLabel(toChangeFrom: before)
        XCTAssertTrue(app.scrollTo(app.todayEntry(containing: "banana")).waitToAppear().exists)
    }

    @MainActor
    func testUndoTakesBackAFoodJustLogged() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        let calories = app.element("today.calories").waitToAppear()
        let before = calories.label

        logABanana(app)
        app.element("toast.undo").waitToAppear().tap()
        app.element("toast.message").waitToDisappear()
        leaveSearch(app)

        calories.waitToAppear()
        XCTAssertEqual(calories.label, before)
        XCTAssertTrue(app.scrollTo(app.element("today.nothingLogged")).waitToAppear().exists)
    }

    @MainActor
    func testQuickAddLogsCaloriesToToday() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "quickAdd"])

        app.element("quickAdd.kcal").waitToAppear().type("500")
        app.closeNumberPad()
        app.element("quickAdd.protein").type("30")
        app.closeNumberPad()
        let add = app.element("quickAdd.add")
        XCTAssertTrue(add.label.contains("500 kcal"), add.label)
        add.tap()

        add.waitToDisappear()
        let entry = app.scrollTo(app.todayEntry(containing: "Quick add")).waitToAppear()
        // An iPad's table has the calories in a column of their own.
        XCTAssertTrue(XCUIApplication.isPad ? entry.staticTexts["500"].exists : entry.label.contains("500"), entry.debugDescription)
    }

    @MainActor
    func testWeighingInFromTheQuickLogBar() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.calories").waitToAppear()

        app.logButton("weighIn").tap()
        let field = app.textFields["weighIn.value"].waitToAppear()
        // Ready with the last weight: a nudge and Save.
        let last = field.value as? String ?? ""
        XCTAssertFalse(last.isEmpty)
        app.element("weighIn.heavier").tap()
        let weight = field.value as? String ?? ""
        XCTAssertNotEqual(weight, last)
        app.element("weighIn.save").tap()

        let reading = app.element("today.weight").waitToAppear()
        XCTAssertTrue(reading.label.contains("\(weight) kg"), "\(reading.label) after saving \(weight)")
    }

    @MainActor
    func testWidgetLinksOpenTheirStepInPlaceOfAnotherSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.calories").waitToAppear()

        try app.openLink("macrotrack://weigh")
        app.textFields["weighIn.value"].waitToAppear()

        // The quick add control, while the weigh-in is up: the weigh-in gives way.
        try app.openLink("macrotrack://quickadd")
        app.element("quickAdd.kcal").waitToAppear()
        app.textFields["weighIn.value"].waitToDisappear()
    }

    @MainActor
    func testAWidgetLinkClosesASheetTodayOpened() throws {
        try XCTSkipIf(
            XCUIApplication.isPad,
            "An iPad's Today edits an entry in its inspector, not a sheet (RegularWidthUITests.testTodaysLogIsATableEditedBesideIt)")
        continueAfterFailure = false
        // The supplement sample logs this morning's coffee, so Today has an entry to open.
        let app = XCUIApplication.launched(["-seedSampleData", "-seedSupplements"])
        app.element("today.calories").waitToAppear()

        app.scrollTo(app.element("today.entry")).waitToAppear().tap()
        let save = app.element("entryEditor.save").waitToAppear()

        // Today's own sheet, not one of the root's: the link still lands on its step, in its place
        // rather than over it, so closing the weigh-in goes back to Today.
        try app.openLink("macrotrack://weigh")
        app.textFields["weighIn.value"].waitToAppear()
        save.waitToDisappear()
        app.element("weighIn.cancel").tap()
        app.textFields["weighIn.value"].waitToDisappear()
        // Today as it was left, scrolled to the entry: the link was opened in the running app.
        XCTAssertTrue(app.element("today.entry").waitToAppear().isHittable, "Today, not the editor the link replaced")
        XCTAssertFalse(save.exists)
    }
}
