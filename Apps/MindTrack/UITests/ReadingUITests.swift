import XCTest

/// Reading and the real-world checks: the shelf's book finder, and an episode logged from Progress.
nonisolated final class ReadingUITests: XCTestCase {
    @MainActor
    func testABookFoundOnTheLadderGoesOnTheShelf() {
        // -findBook opens the finder already searching; the ladder answers offline.
        let app = XCUIApplication.launched(["-seedSampleData", "-showShelf", "-findBook", "Dune"])
        let result = app.element(startingWith: "bookFinder.ladder.").waitToAppear()
        XCTAssertTrue(result.label.contains("Dune"), result.label)
        result.tap()

        let save = app.buttons["bookEditor.save"].waitToAppear(timeout: 10)
        XCTAssertEqual((app.textFields["bookEditor.title"].value as? String), "Dune")
        save.tap()

        let current = app.element("shelf.current").waitToAppear(timeout: 10)
        XCTAssertEqual(current.label, "Dune", "the book found is the one being read now")
        app.buttons["shelf.done"].tap()
        app.element("today.settings").waitToAppear(timeout: 10)
    }

    @MainActor
    func testLoggingAnEpisodeShowsItOnProgress() {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "progress"])
        app.element("progress.stat.intelligence").waitToAppear()
        app.scroll(to: app.buttons["progress.logEpisode.japanese"]).tap()

        let save = app.buttons["episode.save"].waitToAppear(timeout: 10)
        app.segmentedControls["episode.kind"].buttons["A conversation"].tap()
        let title = app.textFields["episode.title"]
        title.tap()
        title.typeText("Ramen shop")
        app.buttons["Followed most of it"].tap()
        save.tap()
        save.waitToDisappear()

        // The newest log heads the list, dated today.
        let today = Date().formatted(.dateTime.day().month(.abbreviated).year())
        app.scroll(to: app.staticTexts[today].firstMatch)
    }
}
