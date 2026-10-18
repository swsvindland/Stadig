import XCTest

/// Logging, end to end: a food from search, Undo, a quick add, a weigh-in, and the links the
/// widgets and controls open.
nonisolated final class LoggingUITests: XCTestCase {
    @MainActor
    func testLoggingAFoodFromSearchUpdatesToday() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        let calories = app.element("today.calories").waitToAppear()
        let before = calories.label

        app.element("quickLog.search").tap()
        let search = app.searchFields.firstMatch.waitToAppear()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()

        let toast = app.element("toast.message").waitToAppear()
        XCTAssertTrue(toast.label.hasPrefix("Logged "), toast.label)
        // The search stays up for the next food, and Done with it.
        app.element("logger.done").waitToAppear().tap()

        calories.waitForLabel(toChangeFrom: before)
        XCTAssertTrue(app.scrollTo(app.element("today.entry", labelContaining: "banana")).waitToAppear().exists)
    }

    @MainActor
    func testUndoTakesBackAFoodJustLogged() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        let calories = app.element("today.calories").waitToAppear()
        let before = calories.label

        app.element("quickLog.search").tap()
        let search = app.searchFields.firstMatch.waitToAppear()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()
        app.element("toast.undo").waitToAppear().tap()
        app.element("toast.message").waitToDisappear()
        app.element("logger.done").waitToAppear().tap()

        calories.waitToAppear()
        XCTAssertEqual(calories.label, before)
        XCTAssertTrue(app.scrollTo(app.element("today.nothingLogged")).waitToAppear().exists)
    }

    @MainActor
    func testQuickAddLogsCaloriesToToday() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "quickAdd"])

        app.element("quickAdd.kcal").waitToAppear().type("500")
        app.element("quickAdd.protein").type("30")
        let add = app.element("quickAdd.add")
        XCTAssertTrue(add.label.contains("500 kcal"), add.label)
        add.tap()

        add.waitToDisappear()
        let entry = app.scrollTo(app.element("today.entry", labelContaining: "Quick add")).waitToAppear()
        XCTAssertTrue(entry.label.contains("500"), entry.label)
    }

    @MainActor
    func testWeighingInFromTheQuickLogBar() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.calories").waitToAppear()

        app.element("quickLog.weighIn").tap()
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
