import XCTest

extension XCUIApplication {
    /// The element with an accessibility identifier, whatever kind of element it is.
    @MainActor
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The first element whose identifier starts with a prefix ("bookFinder.ladder.").
    @MainActor
    func element(startingWith prefix: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// The first button whose identifier starts with a prefix: a row named for its record as well as
    /// its kind ("settings.lifeMode.vacation.").
    @MainActor
    func button(startingWith prefix: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// Swipes through a long page, list or form until the element is on screen: down the page
    /// unless the element is already above it.
    @MainActor
    @discardableResult
    func scroll(to element: XCUIElement, maxSwipes: Int = 20, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            // Slowly, so the page has stopped by the time the element is tapped: a tap on a page
            // still gliding stops it instead of reaching the element.
            if element.exists && element.frame.maxY < frame.midY { swipeDown(velocity: .slow) } else { swipeUp(velocity: .slow) }
            swipes += 1
        }
        XCTAssertTrue(element.exists, "\(element) not found after \(swipes) swipes", file: file, line: line)
        return element
    }

    /// A button in a menu or dialog: by identifier, or by its title where the system draws the menu
    /// itself and drops identifiers.
    @MainActor
    func menuButton(_ identifier: String, title: String) -> XCUIElement {
        // iOS draws a dialog's button inside another with the same identifier: the outer one is it.
        let byID = buttons[identifier].firstMatch
        return byID.waitForExistence(timeout: 2) ? byID : buttons[title].firstMatch
    }
}

extension XCUIElement {
    /// What VoiceOver reads: the label, then the value (a LabeledContent row puts its detail there).
    @MainActor
    var spoken: String { [label, value as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }

    /// Waits for the element to go, failing the test if it stays.
    @MainActor
    func waitToDisappear(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, "\(self) is still there", file: file, line: line)
    }
}
