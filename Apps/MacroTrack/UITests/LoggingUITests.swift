import XCTest

/// Logging, end to end: a food from search, Undo, a quick add, a weigh-in, and the links the
/// widgets and controls open. On an iPad the ways to log are in Today's toolbar rather than the
/// bar above the tabs, and a search is the Foods destination.
nonisolated final class LoggingUITests: XCTestCase {
    /// Searches for a banana and logs it.
    @MainActor
    func logABanana(_ app: XCUIApplication) {
        app.logButton("search").tap()
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()
        app.shot("logger-added")
    }

    /// Back from the logger once the food is logged: it stays up for the next food until Done.
    @MainActor
    func leaveSearch(_ app: XCUIApplication) {
        app.element("logger.done").waitToAppear().tap()
    }

    /// The ways to log sit along the bottom with Done, and give their room to the results while
    /// something's typed. Quick add's Next moves on, since a number pad has no key for it.
    @MainActor
    func testTheMethodsAreAlongTheBottomUntilSomethingsTyped() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "search"])
        let quickAdd = app.element("logger.mode.quickAdd").waitToAppear()
        app.shot("logger-empty")
        XCTAssertTrue(app.element("logger.mode.scan").exists)
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        quickAdd.waitToDisappear()
        XCTAssertTrue(app.element("logger.done").exists, "Done stays while typing")
        app.shot("logger-typing")
        if XCUIApplication.isPad { app.element("logger.clearSearch").tap() } else { search.buttons.firstMatch.tap() }
        quickAdd.waitToAppear().tap()

        let kcal = app.element("quickAdd.kcal").waitToAppear()
        kcal.tap()
        app.element("quickAdd.next").waitToAppear().tap()
        XCTAssertTrue(app.element("quickAdd.protein").value(forKey: "hasKeyboardFocus") as? Bool == true, "Next went to protein")
        XCTAssertTrue(app.element("logger.mode.search").exists, "the ribbon stays in the other ways of logging")
        app.shot("logger-quick-add")
    }

    /// The amount panel: it opens on the food's usual amount, selected, so the first key replaces it.
    @MainActor
    func testAnAmountIsTypedOnThePanelAndTheKeyboardComesBack() throws {
        continueAfterFailure = false
        // A long toast: the check below reads it, and it's two slow queries on an iPad.
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "search", "-toastSeconds", "30"])
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
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedSupplements"])
        app.element("today.calories").waitToAppear()
        app.openTab("Log")
        let entry = app.scrollTo(app.element("log.entry")).waitToAppear()
        let before = entry.label
        entry.tap()

        app.element("amount.panel").waitToAppear()
        app.shot("amount-edit")
        app.element("amount.key.9").tap()
        app.element("amount.key.0").tap()
        app.element("amount.key.0").tap()
        app.element("entryEditor.save").tap()

        app.element("amount.panel").waitToDisappear()
        // The entry, not today's total: it depends on the time of day whether a seeded food has happened.
        app.element("log.entry").waitForLabel(toChangeFrom: before)
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
        app.openTab("Log")
        XCTAssertTrue(app.scrollTo(app.logEntry(containing: "banana")).waitToAppear().exists)
    }

    @MainActor
    func testUndoTakesBackAFoodJustLogged() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        let calories = app.element("today.calories").waitToAppear()
        let before = calories.label

        logABanana(app)
        app.element("toast.undo").waitToAppear()
        app.shot("toast-in-logger")
        app.element("toast.undo").tap()
        app.shot("toast-after-undo")
        app.element("toast.message").waitToDisappear()
        leaveSearch(app)

        app.openTab("Today")
        calories.waitForLabel(toEqual: before)
        app.openTab("Log")
        app.element("log.list").waitToAppear()
        XCTAssertFalse(app.element("log.entry").exists, "the sample weeks end yesterday")
    }

    /// Closing the logger hands Undo over to the screen behind it.
    @MainActor
    func testUndoOutlastsTheLoggerClosing() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-toastSeconds", "30"])
        logABanana(app)
        app.element("toast.undo").waitToAppear()
        let done = app.element("logger.done")
        done.tap()
        done.waitToDisappear()

        // A moment after the sheet has gone, which is when the toast went with it.
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(app.element("toast.undo").exists, "Undo went with the logger")
        app.element("toast.undo").tap()
        app.element("toast.message").waitToDisappear()
        XCTAssertFalse(app.element("log.entry").exists, "the sample weeks end yesterday")
    }

    /// Changing the way of logging keeps the Undo of the food just added.
    @MainActor
    func testUndoOutlastsAChangeOfMethod() {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "search", "-toastSeconds", "30"])
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()
        app.element("toast.undo").waitToAppear()

        app.element("logger.mode.quickAdd").waitToAppear().tap()

        app.element("quickAdd.kcal").waitToAppear()
        XCTAssertTrue(app.element("toast.undo").exists, "Undo went with the search")
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

        // Back in the logger with the meal in sight, ready for the next food.
        add.waitToDisappear()
        app.shot("logger-after-quick-add")
        XCTAssertTrue(app.element("logger.meal").waitToAppear().exists)
        app.element("logger.done").waitToAppear().tap()
        app.openTab("Log")
        let entry = app.scrollTo(app.logEntry(containing: "Quick add")).waitToAppear()
        XCTAssertTrue(entry.label.contains("500"), entry.debugDescription)
    }

    /// The AI's review, left through the ribbon to add what it missed, is still there after the food
    /// is added from its amount, and only logging it ends it. (-seedReview: a simulator may have no
    /// model to read a meal with.)
    @MainActor
    func testAReviewOutlastsAFoodAddedAwayFromIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedReview", "-log", "describe"])
        app.element("review.log").waitToAppear()

        app.element("logger.mode.search").waitToAppear().tap()
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.food").waitToAppear().tap()
        app.element("portion.add").waitToAppear().tap()
        app.element("logger.done").waitToAppear()

        app.element("logger.mode.describe").waitToAppear().tap()
        let log = app.element("review.log").waitToAppear()
        app.shot("logger-review-kept")

        log.tap()
        _ = app.foodSearchField()
        // With no model and no review, the ribbon has no Describe to go back to.
        let describe = app.element("logger.mode.describe")
        if describe.exists { describe.tap() }
        XCTAssertFalse(app.element("review.log").waitForExistence(timeout: 2), "logging it ended it")
    }

    /// Finding a food for the review, with the query cleared: what's offered is foods, and a + on one
    /// answers the review rather than logging it to the day.
    @MainActor
    func testClearingTheSearchWhileFindingAFoodStillAnswersTheReview() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedReview", "-log", "describe"])
        let log = app.element("review.log").waitToAppear()
        XCTAssertTrue(log.label.hasPrefix("Log 1 food"), log.label)
        app.buttons.matching(NSPredicate(format: "label == 'Change food'")).element(boundBy: 1).tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Search for'")).firstMatch.waitToAppear().tap()
        app.element("logger.backToReview").waitToAppear()

        let search = app.foodSearchField()
        if XCUIApplication.isPad { app.element("logger.clearSearch").tap() } else { search.buttons.firstMatch.tap() }
        let again = app.element("logger.logAgain").waitToAppear()
        XCTAssertFalse(app.element("logger.savedMeal").exists, "a meal can't be one food")
        XCTAssertFalse(app.element("logger.sameAsUsual").exists, "nor can what was eaten together")
        again.tap()

        XCTAssertTrue(app.element("review.log", labelContaining: "Log 2 foods").waitToAppear().exists)
        XCTAssertFalse(app.element("toast.message").exists, "nothing went on the day")
    }

    /// From the review, the pencil on its food's amount: 300 kcal corrected to 360.
    @MainActor
    func correctTheFoodInTheReview(_ app: XCUIApplication) {
        app.element("review.amount").waitToAppear().tap()
        app.element("portion.editFood").waitToAppear().tap()
        let kcal = app.element("foodEditor.kcal").waitToAppear()
        // The number sits at the field's right edge, so a tap there leaves the cursor after it.
        kcal.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        kcal.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "360")
        app.closeNumberPad()
        let save = app.element("foodEditor.save").waitToAppear()
        save.tap()
        save.waitToDisappear()
    }

    /// A correction made from the review's amount reaches the review: its total, and what's logged.
    @MainActor
    func testACorrectionMadeFromTheReviewReachesIt() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedReview", "-log", "describe", "-toastSeconds", "30"])
        let log = app.element("review.log").waitToAppear()
        XCTAssertEqual(log.label, "Log 1 food · 300 kcal")

        correctTheFoodInTheReview(app)

        let use = app.element("portion.add").waitToAppear()
        XCTAssertEqual(use.label, "Use · 360 kcal")
        use.tap()
        log.waitForLabel(toEqual: "Log 1 food · 360 kcal")
        app.shot("logger-review-corrected")
        log.tap()
        XCTAssertEqual(app.element("toast.message").waitToAppear().label, "Logged Beef stew · 360 kcal", "the total the button said")
    }

    /// The correction is saved by then, so closing the amount without using it doesn't undo it.
    @MainActor
    func testACorrectionStandsWhenItsAmountIsClosed() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedReview", "-log", "describe"])
        let log = app.element("review.log").waitToAppear()

        correctTheFoodInTheReview(app)

        app.element("portion.close").waitToAppear().tap()
        log.waitForLabel(toEqual: "Log 1 food · 360 kcal")
    }

    /// A scanned supplement already in the stack: Take ends there, back at the search for the next
    /// thing with its Undo over the meal, in a sheet and in the pane. The simulator has no camera,
    /// so it's typed.
    @MainActor
    func testTakingAScannedSupplementGoesBackToTheSearch() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-seedSupplements", "-log", "scan", "-toastSeconds", "30"])
        let number = app.element("barcode.number").waitToAppear()
        number.tap()
        number.typeText("031604010539")
        app.element("barcode.lookUp").waitToAppear().tap()
        let take = app.element("supplementFound.take").waitToAppear()
        app.shot("logger-scanned-supplement")

        take.tap()

        take.waitToDisappear()
        _ = app.foodSearchField()
        XCTAssertTrue(app.element("logger.done").exists, "the logger stayed open")
        XCTAssertTrue(app.element("toast.undo").exists, "with the dose's Undo")
        app.shot("logger-took-supplement")
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

    /// A logger that's gone back to its search, asked again for the way it opened with: the control
    /// lands on that step, as it does with no logger up.
    @MainActor
    func testAWidgetLinkFindsTheWayTheLoggerOpenedWith() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.calories").waitToAppear()

        try app.openLink("macrotrack://quickadd")
        let kcal = app.element("quickAdd.kcal").waitToAppear()
        kcal.type("250")
        app.element("quickAdd.add").waitToAppear().tap()
        kcal.waitToDisappear()

        try app.openLink("macrotrack://quickadd")
        kcal.waitToAppear()
    }

    @MainActor
    func testAWidgetLinkClosesASheetTheLogOpened() throws {
        try XCTSkipIf(XCUIApplication.isPad, "An iPad edits an entry in a pane, which a sheet leaves where it is")
        continueAfterFailure = false
        // The supplement sample logs this morning's coffee, so the Log tab has an entry to open.
        let app = XCUIApplication.launched(["-seedSampleData", "-seedSupplements", "-tab", "log"])
        app.scrollTo(app.element("log.entry")).waitToAppear().tap()
        let save = app.element("entryEditor.save").waitToAppear()

        // The Log tab's own sheet, not one of the root's: the link still lands on its step, in its
        // place rather than over it, so closing the weigh-in goes back to the log.
        try app.openLink("macrotrack://weigh")
        app.textFields["weighIn.value"].waitToAppear()
        save.waitToDisappear()
        app.element("weighIn.cancel").tap()
        app.textFields["weighIn.value"].waitToDisappear()
        // The log as it was left, scrolled to the entry: the link was opened in the running app.
        XCTAssertTrue(app.element("log.entry").waitToAppear().isHittable, "the log, not the editor the link replaced")
        XCTAssertFalse(save.exists)
    }
}
