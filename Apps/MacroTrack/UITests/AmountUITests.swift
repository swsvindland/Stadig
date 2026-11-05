import XCTest

/// The amount panel: what it says about a food, whether what it says is what Save does, and the
/// places it opens from.
nonisolated final class AmountUITests: XCTestCase {
    /// Searches the open logger for a banana and opens its amount.
    @MainActor
    func openABanana(_ app: XCUIApplication) {
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.food").waitToAppear().tap()
        app.element("amount.panel").waitToAppear()
    }

    /// Adds a banana with its + and leaves the logger, where it covers the log.
    @MainActor
    func logABanana(_ app: XCUIApplication) {
        let search = app.foodSearchField()
        search.tap()
        search.typeText("banana")
        app.element("logger.addFood").waitToAppear().tap()
        app.element("toast.message", labelContaining: "Logged").waitToAppear()
        if !XCUIApplication.isPad { app.element("logger.done").waitToAppear().tap() }
    }

    /// The pencil on the open amount: its calories typed over with `kcal`.
    @MainActor
    func correct(to kcal: String, in app: XCUIApplication) {
        app.element("portion.editFood").waitToAppear().tap()
        let field = app.element("foodEditor.kcal").waitToAppear()
        // The number sits at the field's right edge, so a tap there leaves the cursor after it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + kcal)
        app.closeNumberPad()
        let save = app.element("foodEditor.save").waitToAppear()
        save.tap()
        save.waitToDisappear()
    }

    /// The chip for a unit, by its exact name: "g" alone would also find "cup, sliced".
    @MainActor
    func unit(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "portion.unit").matching(NSPredicate(format: "label == %@", label)).firstMatch.waitToAppear()
    }

    /// The number on the panel, without its unit.
    @MainActor
    func quantity(_ app: XCUIApplication) -> String {
        let quantity = app.element("amount.quantity").waitToAppear()
        return ((quantity.value as? String) ?? "").split(separator: " ").first.map(String.init) ?? ""
    }

    /// Foods already logged keep their numbers, so a correction made from one leaves Save saying
    /// the numbers it's going to keep.
    @MainActor
    func testSaveSaysTheNumbersAnEntryKeepsAfterACorrection() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "log", "-log", "search"])
        logABanana(app)

        app.scrollTo(app.logEntry(containing: "banana")).waitToAppear().tap()
        let save = app.element("entryEditor.save").waitToAppear()
        let logged = save.label
        correct(to: "900", in: app)
        XCTAssertEqual(save.waitToAppear().label, logged, "it says what it will keep")
    }

    /// The chips hold a food's units, and calories are one its numbers change. Counted in the old
    /// ones, the amount and the total disagree.
    @MainActor
    func testTheCalorieChipFollowsACorrection() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "search"])
        openABanana(app)
        // An amount offered, which a chip converts. A typed one stays the number it is.
        unit("g", in: app).tap()
        correct(to: "150", in: app)

        unit("kcal", in: app).tap()
        XCTAssertEqual(quantity(app), "150", "the same grams at the corrected numbers")
        XCTAssertEqual(app.element("portion.add").label, "Add · 150 kcal")
    }

    /// Half a pound is how a pound is measured. Half a gram isn't.
    @MainActor
    func testOuncesAndPoundsTakeFractions() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launched(["-seedSampleData", "-log", "search"])
        openABanana(app)
        let half = app.element("amount.key.½").waitToAppear()

        unit("g", in: app).tap()
        XCTAssertFalse(half.isEnabled, "grams are too small to halve")

        unit("lb", in: app).tap()
        XCTAssertTrue(half.isEnabled, "pounds aren't")
        app.element("amount.key.1").tap()
        half.tap()
        XCTAssertEqual(quantity(app), "1½")
    }
}
