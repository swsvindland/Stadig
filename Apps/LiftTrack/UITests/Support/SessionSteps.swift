import XCTest

extension XCUIApplication {
    /// Works through the session's sets from the bottom panel (drills and warm-ups with Done, rests
    /// skipped) until one work set has been rated Just right.
    @MainActor
    func logOneRatedSet(file: StaticString = #filePath, line: UInt = #line) {
        let rate = buttons["logger.ratingOrange"]
        let done = buttons["logger.done"]
        let skipRest = buttons["rest.skip"]
        for _ in 0..<40 {
            if rate.exists {
                rate.tap()
                return
            }
            if skipRest.exists {
                skipRest.tap()
            } else if done.exists {
                done.tap()
            } else {
                // The panel is between states: wait for whichever comes.
                _ = rate.waitForExistence(timeout: 2) || done.waitForExistence(timeout: 2) || skipRest.waitForExistence(timeout: 2)
            }
        }
        XCTFail("Never reached a set to rate", file: file, line: line)
    }
}
