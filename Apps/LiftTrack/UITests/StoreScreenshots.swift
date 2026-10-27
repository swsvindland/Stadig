import XCTest

/// The App Store screenshots, not a test of anything: `Scripts/store-screenshots.sh` runs these on
/// its own iPhone and iPad simulators with STORE_SCREENSHOTS naming a folder, and each saves its
/// screen there for `storeassets` to frame. Skipped in every other run.
nonisolated final class StoreScreenshots: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(ProcessInfo.processInfo.environment["STORE_SCREENSHOTS"] == nil, "Only Scripts/store-screenshots.sh takes the screenshots")
    }

    /// Saves the screen as `phone/<name>.png` or `tablet/<name>.png` (the iPhone and iPad run at
    /// once), once what's on it has stopped moving: scroll indicators fading, a chart's first layout.
    @MainActor
    func save(_ name: String) throws {
        let folder = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["STORE_SCREENSHOTS"]))
            .appendingPathComponent(XCUIApplication.isPad ? "tablet" : "phone")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Thread.sleep(forTimeInterval: 2)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// A work set waiting for its rating, with the set before it logged and rated Just right.
    @MainActor
    func testSession() throws {
        let app = XCUIApplication.launched(["-seedSampleData", "-startSession"])
        app.element("session.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        app.logOneRatedSet()
        app.buttons["rest.skip"].waitToAppear().tap()
        app.buttons["logger.ratingOrange"].waitToAppear()
        try save("session")
    }

    @MainActor
    func testToday() throws {
        let app = XCUIApplication.launched(["-seedSampleData"])
        app.element("today.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        try save("today")
    }

    /// The iPhone's Plan; on the iPad, the Program table with a main lift explained in the inspector.
    @MainActor
    func testPlan() throws {
        if XCUIApplication.isPad {
            let app = XCUIApplication.launched(["-seedSampleData", "-tab", "program"])
            app.element("program.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
            app.staticTexts["Barbell Bench Press"].firstMatch.waitToAppear().tap()
            app.element("program.inspector").waitToAppear()
        } else {
            let app = XCUIApplication.launched(["-seedSampleData", "-tab", "plan"])
            app.element("plan.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        }
        try save("plan")
    }

    @MainActor
    func testProgress() throws {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "progress"])
        app.element("progress.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        try save("progress")
    }

    @MainActor
    func testBody() throws {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "body"])
        app.element("body.screen").waitToAppear(timeout: XCUIApplication.firstScreenTimeout)
        try save("body")
    }
}
