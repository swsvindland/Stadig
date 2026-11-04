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
