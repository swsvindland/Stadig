import XCTest

/// Settings that change what Today shows: a life mode, started and deleted.
nonisolated final class SettingsUITests: XCTestCase {
    @MainActor
    func testAVacationPausesTodayUntilItsDeleted() {
        let app = XCUIApplication.launched(["-seedSampleData", "-showSettings"])
        app.buttons["settings.done"].waitToAppear()

        app.scroll(to: app.buttons["settings.startLifeMode"]).tap()
        app.menuButton("settings.startVacation", title: "Vacation").waitToAppear(timeout: 5).tap()
        let save = app.buttons["lifeMode.save"].waitToAppear(timeout: 10)
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.switches["lifeMode.openEnded"].exists, "a trip has an end")
        save.tap()
        save.waitToDisappear()

        let row = app.button(startingWith: "settings.lifeMode.vacation.")
        app.scroll(to: row)
        XCTAssertTrue(row.spoken.contains("until"), row.spoken)
        app.buttons["settings.done"].tap()
        app.element("today.paused").waitToAppear(timeout: 10)

        // Deleted, it's gone from here and from every app that shares it.
        app.element("today.settings").tap()
        app.scroll(to: row).tap()
        app.buttons["lifeMode.endToday"].waitToAppear(timeout: 5)
        app.buttons["lifeMode.delete"].waitToAppear(timeout: 5).tap()
        row.waitToDisappear()
        app.buttons["settings.done"].tap()
        app.element("today.paused").waitToDisappear()
        app.element("today.settings").waitToAppear(timeout: 10)
    }

    @MainActor
    func testIllnessCanRunUntilItsBetter() {
        let app = XCUIApplication.launched(["-seedSampleData", "-showSettings"])
        app.buttons["settings.done"].waitToAppear()
        // The whole row opens the menu, not just its words: tapped near the trailing edge.
        let start = app.scroll(to: app.buttons["settings.startLifeMode"])
        XCTAssertGreaterThan(start.frame.width, app.frame.width * 0.6, "the menu's label fills the row")
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.menuButton("settings.startIllness", title: "Ill").waitToAppear(timeout: 5).tap()
        let openEnded = app.switches["lifeMode.openEnded"].waitToAppear(timeout: 10)
        XCTAssertEqual(openEnded.value as? String, "1", "an illness starts open-ended")
        app.buttons["lifeMode.save"].tap()
        let row = app.scroll(to: app.button(startingWith: "settings.lifeMode.illness."))
        XCTAssertTrue(row.spoken.contains("ongoing"), row.spoken)
    }
}
