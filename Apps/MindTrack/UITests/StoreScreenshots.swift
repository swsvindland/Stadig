import XCTest

/// The App Store screenshots, not a test of anything: `Scripts/store-screenshots.sh` runs these on
/// its own iPhone and iPad simulators with STORE_SCREENSHOTS naming a folder, and each saves its
/// screen there for `storeassets` to frame. Skipped in every other run. Today isn't among them:
/// what it shows depends on the weekday the screenshots are taken.
nonisolated final class StoreScreenshots: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["STORE_SCREENSHOTS"] == nil, "Only Scripts/store-screenshots.sh takes the screenshots")
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

    @MainActor
    func testPlan() throws {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "plan"])
        app.element("plan.phase").waitToAppear(timeout: 30)
        try save("plan")
    }

    /// A new Japanese word as it's taught: reading, meaning, its kanji and a sentence at the
    /// student's level (the sample's fifth step).
    @MainActor
    func testJapanese() throws {
        let app = XCUIApplication.launched(["-seedSampleData", "-study", "japanese", "-steps", "4"])
        app.element("session.part").waitToAppear(timeout: 30)
        try save("japanese")
    }

    /// A maths topic's lesson with its worked example, before the practice.
    @MainActor
    func testMaths() throws {
        let app = XCUIApplication.launched(["-seedSampleData", "-study", "maths", "-skipParts", "1"])
        app.buttons["lesson.continue"].waitToAppear(timeout: 30)
        try save("maths")
    }

    @MainActor
    func testProgress() throws {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "progress"])
        app.element("progress.stat.intelligence").waitToAppear(timeout: 30)
        try save("progress")
    }

    /// The iPhone's shelf; on the iPad, the shelf's list with a book open beside it (the one being
    /// read when the sample has one on the go that day).
    @MainActor
    func testShelf() throws {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "shelf"])
        if XCUIApplication.isPad {
            let book = app.element("shelfList.book").waitToAppear(timeout: 30)
            let current = app.element("shelfList.current")
            (current.exists ? current : book).tap()
            app.element("bookDetail.title").waitToAppear()
        } else {
            // Not the book being read: whether the sample has one on the go depends on the day.
            app.buttons["shelf.done"].waitToAppear(timeout: 30)
        }
        try save("shelf")
    }
}
