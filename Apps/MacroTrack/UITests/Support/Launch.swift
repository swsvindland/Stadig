import XCTest

extension XCUIApplication {
    /// Launches the app for a UI test: `-uiTesting` (an in-memory store, no permission prompts, no
    /// animations) plus the DEBUG launch arguments that set up the screen under test.
    @MainActor
    static func launched(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
    }

    /// Opens a link in the running app, as a widget or a control does. `XCUIApplication.open(_:)`
    /// relaunches the app with the link instead, which tests nothing about what was on screen.
    @MainActor
    func openLink(_ link: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: link), file: file, line: line))
    }
}

extension XCUIElement {
    /// Waits for the element, failing the test with a useful message if it never appears.
    @MainActor
    @discardableResult
    func waitToAppear(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(self) never appeared", file: file, line: line)
        return self
    }
}
