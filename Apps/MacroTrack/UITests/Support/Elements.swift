import XCTest

extension XCUIApplication {
    /// Any element with this accessibility identifier, whatever kind it is.
    @MainActor
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The first element with this identifier whose label contains `text` (case-insensitive).
    @MainActor
    func element(_ identifier: String, labelContaining text: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// An entry in Today's log whose text contains `text`: a row of the iPhone's list, or of an
    /// iPad's table, whose row has no label of its own, only its columns' texts.
    @MainActor
    func todayEntry(containing text: String) -> XCUIElement {
        guard Self.isPad else { return element("today.entry", labelContaining: text) }
        return element("today.log").cells.containing(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// The button that opens a way to log: the iPhone's quick-log bar above the tabs, or Today's
    /// toolbar on an iPad ("search", "weighIn", "quickAdd").
    @MainActor
    func logButton(_ way: String) -> XCUIElement {
        guard Self.isPad else { return element("quickLog.\(way)") }
        return element(way == "search" ? "toolbar.logFood" : "toolbar.\(way)")
    }

    /// The food search's field. In portrait an iPad's Foods has no room for it beside the tab bar
    /// along the top, so the toolbar keeps it behind its search button, which opens it.
    @MainActor
    func foodSearchField(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let field = searchFields.firstMatch
        if Self.isPad, !field.waitForExistence(timeout: 5) {
            buttons["Search"].firstMatch.waitToAppear(file: file, line: line).tap()
        }
        return field.waitToAppear(file: file, line: line)
    }

    /// Closes an iPad's number pad, which iPadOS shows in a popover beside a number field: a tap
    /// anywhere else only closes the popover, so the tap meant for the next button would do
    /// nothing. The tap lands on the frontmost navigation bar's middle, where there's nothing else.
    @MainActor
    func closeNumberPad() {
        guard Self.isPad, keyboards.firstMatch.exists else { return }
        navigationBars.allElementsBoundByIndex.last?.tap()
    }

    /// Scrolls until the element is on screen and can be tapped, or gives up after a few drags.
    /// Each drag holds at its end, so the list stops where it's let go (a tap on a list that's still
    /// gliding only stops it), and a row left above the middle is dragged back down: a list drops
    /// the rows it has scrolled well past. The drags run down the middle of the screen, or of the
    /// column `beside` is in (an iPad's Today has its summary in a column beside the log).
    @MainActor
    @discardableResult
    func scrollTo(_ element: XCUIElement, drags: Int = 15, beside: XCUIElement? = nil) -> XCUIElement {
        var left = drags
        let x = beside.map { $0.waitToAppear().frame.midX / frame.width } ?? 0.5
        while !(element.exists && element.isHittable), left > 0 {
            let back = element.exists && element.frame.maxY < frame.midY
            let start = coordinate(withNormalizedOffset: CGVector(dx: x, dy: back ? 0.35 : 0.7))
            let end = coordinate(withNormalizedOffset: CGVector(dx: x, dy: back ? 0.7 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            left -= 1
        }
        return element
    }
}

extension XCUIElement {
    /// Taps a text field and types into it.
    @MainActor
    func type(_ text: String) {
        tap()
        typeText(text)
    }

    /// Waits for the label to stop being `old`, as when a number on screen updates.
    @MainActor
    func waitForLabel(toChangeFrom old: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let changed = NSPredicate(format: "label != %@", old)
        let expectation = XCTNSPredicateExpectation(predicate: changed, object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(self) still reads \(old)", file: file, line: line)
    }

    /// Waits for the element to go away, as a sheet does once it's dismissed.
    @MainActor
    func waitToDisappear(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\(self) is still there", file: file, line: line)
    }
}
