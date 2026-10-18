import XCTest

/// Settings, life modes and measurements: the sheets around the plan.
nonisolated final class ScreensUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOpeningSettingsExportingAndClosingIt() {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.buttons["today.settings"].waitToAppear(timeout: XCUIApplication.firstScreenTimeout).tap()
        let settings = app.element("settings.screen").waitToAppear()

        app.buttons["settings.exportCSV"].scrolledTo(in: settings).tap()
        XCTAssertTrue(app.element("settings.shareCSV").waitForExistence(timeout: 10), "The CSV files are ready to share")

        app.buttons["settings.done"].tap()
        app.element("settings.screen").waitToDisappear()
        app.element("today.screen").waitToAppear()
    }

    @MainActor
    func testAddingAndDeletingAVacation() {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "plan"])
        app.element("plan.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        XCTAssertFalse(app.element("plan.lifeMode").exists)

        app.buttons["plan.addVacation"].waitToAppear().tap()
        app.buttons["lifeMode.save"].waitToAppear().tap()
        let row = app.element("plan.lifeMode").waitToAppear()
        XCTAssertTrue(row.label.contains("Vacation"))

        row.tap()
        app.buttons["lifeMode.delete"].waitToAppear().tap()
        app.element("plan.lifeMode").waitToDisappear()
    }

    @MainActor
    func testAddingMeasurementsListsThem() {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "body"])
        app.element("body.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        let rows = app.descendants(matching: .any).matching(identifier: "body.measurement")
        rows.firstMatch.waitToAppear()
        let before = rows.count

        app.buttons["body.addMeasurements"].tap()
        let save = app.buttons["measurements.save"].waitToAppear()
        XCTAssertFalse(save.isEnabled, "Nothing to save yet")
        let waist = app.textFields["measurements.waist"].waitToAppear()
        waist.tap()
        waist.typeText("84")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        save.waitToDisappear()
        XCTAssertEqual(rows.count, before + 1)
    }
}
