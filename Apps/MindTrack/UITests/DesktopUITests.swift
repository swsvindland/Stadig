import XCTest

/// An iPad at full width, as the Mac and Vision Pro lay it out: the sidebar's own destinations
/// (Shelf, Writing, Courses), reached from the Go menu's shortcuts, and a session driven from the
/// keyboard. These run only on an iPad; an iPhone keeps its three tabs.
nonisolated final class DesktopUITests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the wide layout is an iPad's (and the Mac's)")
    }

    @MainActor
    func testTheGoShortcutsOpenTheLibraryDestinations() {
        let app = XCUIApplication.launched(["-seedSampleData", "-tab", "shelf"])
        // The shelf: the book on the go in the list, and selected beside it.
        let current = app.element("shelfList.current").waitToAppear()
        XCTAssertTrue(current.label.contains("Babel-17"), current.label)
        XCTAssertEqual(app.element("bookDetail.title").waitToAppear(timeout: 10).label, "Babel-17")
        XCTAssertFalse(app.buttons["shelf.done"].exists, "a destination, not a sheet")

        // ⌘5: Writing, with the newest piece open beside the list.
        app.typeKey("5", modifierFlags: .command)
        app.element("writingList.piece").waitToAppear(timeout: 10)
        app.buttons["writingList.writeNow"].waitToAppear(timeout: 5)

        // ⌘6: Courses, a language's words by where each memory stands.
        app.typeKey("6", modifierFlags: .command)
        let mastered = app.buttons["courses.filter.mastered"].waitToAppear(timeout: 10)
        XCTAssertTrue(mastered.label.hasPrefix("Mastered"), mastered.label)

        // ⌘1: back to Today.
        app.typeKey("1", modifierFlags: .command)
        app.element("today.settings").waitToAppear(timeout: 10)
    }

    @MainActor
    func testTheShelfOpensInTheSidebarRatherThanASheet() {
        let app = XCUIApplication.launched(["-seedSampleData", "-showShelf"])
        app.element("shelfList.current").waitToAppear()
        XCTAssertFalse(app.buttons["shelf.done"].exists)
        // A suggestion, selected, can be started from beside the list.
        app.element(startingWith: "shelfList.suggestion.").waitToAppear(timeout: 10).tap()
        app.buttons["suggestion.start"].waitToAppear(timeout: 10).tap()
        let title = app.element("bookDetail.title").waitToAppear(timeout: 10)
        XCTAssertNotEqual(title.label, "Babel-17", "the book started is the one on the go now")
    }

    @MainActor
    func testASessionAnswersFromTheKeyboard() {
        // Japanese warm-up reviews: "What does it mean?" with four choices.
        let app = XCUIApplication.launched(["-seedSampleData", "-study", "japanese"])
        app.buttons["session.end"].waitToAppear()
        let choice = app.buttons["question.choice.0"].waitToAppear(timeout: 20)
        XCTAssertTrue(choice.isEnabled)

        // 1 picks the first choice; the verdict shows.
        app.typeKey("1", modifierFlags: [])
        app.element("question.verdict").waitToAppear(timeout: 10)
        XCTAssertFalse(choice.isEnabled, "answered")

        // Return moves on, to a fresh step.
        app.typeKey(.return, modifierFlags: [])
        app.element("question.verdict").waitToDisappear(timeout: 10)

        // Escape asks before ending, as End does.
        app.typeKey(.escape, modifierFlags: [])
        app.menuButton("session.endConfirm", title: "End session").waitToAppear(timeout: 5).tap()
        app.buttons["session.end"].waitToDisappear()
        app.element("today.settings").waitToAppear(timeout: 10)
    }
}
