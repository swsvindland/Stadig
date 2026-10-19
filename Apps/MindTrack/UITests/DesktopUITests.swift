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
        // The shelf: every book in a list, and the one selected beside it. (Whether the sample has
        // a book on the go depends on the day, so a finished one.)
        let book = app.element("shelfList.book").waitToAppear()
        XCTAssertFalse(app.buttons["shelf.done"].exists, "a destination, not a sheet")
        book.tap()
        let title = app.element("bookDetail.title").waitToAppear(timeout: 10).label
        XCTAssertTrue(book.label.hasPrefix(title + ","), "\(title) is the book selected: \(book.label)")

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
        let suggestion = app.element(startingWith: "shelfList.suggestion.").waitToAppear()
        XCTAssertFalse(app.buttons["shelf.done"].exists)
        // A suggestion, selected, can be started from beside the list ("Babel-17, Samuel R. Delany · tier 5").
        let suggested = suggestion.label
        suggestion.tap()
        app.buttons["suggestion.start"].waitToAppear(timeout: 10).tap()
        // The book started is the one on the go now, selected.
        let title = app.element("bookDetail.title").waitToAppear(timeout: 10).label
        XCTAssertTrue(suggested.hasPrefix(title + ","), "\(title) is the book started: \(suggested)")
        let current = app.element("shelfList.current").waitToAppear(timeout: 10)
        XCTAssertTrue(current.label.hasPrefix(title), current.label)
    }

    @MainActor
    func testASessionAnswersFromTheKeyboard() {
        let app = XCUIApplication.launched(["-seedSampleData", "-study", "japanese"])
        app.buttons["session.end"].waitToAppear()
        // Japanese words are asked with four choices ("What does it mean?"), but the warm-up's
        // reviews of whatever is due come first: on some days a typed maths answer or a lesson.
        let choice = app.buttons["question.choice.0"]
        for _ in 0..<15 where !(choice.waitForExistence(timeout: 3) && choice.isEnabled) {
            app.answerStep()
        }
        XCTAssertTrue(choice.exists && choice.isEnabled, "never reached a question with choices")

        // 1 picks the first choice; the verdict shows.
        app.typeKey("1", modifierFlags: [])
        app.element("question.verdict").waitToAppear(timeout: 10)
        XCTAssertFalse(choice.isEnabled, "answered")

        // Return moves on and Escape asks before ending, but XCUITest on the iPad simulator delivers
        // neither (not even Return to a search field that has the cursor, where it's the system's
        // own), so here the step's buttons do what those keys do: Continue, to a fresh step...
        app.buttons["question.continue"].waitToAppear(timeout: 5).tap()
        app.element("question.verdict").waitToDisappear(timeout: 10)

        // ...and End, which asks first.
        app.buttons["session.end"].tap()
        app.menuButton("session.endConfirm", title: "End session").waitToAppear(timeout: 5).tap()
        app.buttons["session.end"].waitToDisappear()
        app.element("today.settings").waitToAppear(timeout: 10)
    }
}
