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

    /// A food on the Log tab whose text contains `text`.
    @MainActor
    func logEntry(containing text: String) -> XCUIElement { element("log.entry", labelContaining: text) }

    /// The button that opens a way to log: the iPhone's quick-log bar above the tabs, or Today's
    /// toolbar on an iPad ("search", "weighIn", "quickAdd").
    @MainActor
    func logButton(_ way: String) -> XCUIElement {
        guard Self.isPad else { return element("quickLog.\(way)") }
        let titles = ["search": "Log Food", "weighIn": "Weigh In", "quickAdd": "Quick Add"]
        return toolbarItem(way == "search" ? "toolbar.logFood" : "toolbar.\(way)", title: titles[way] ?? way)
    }

    /// A button of the toolbar. With the tab bar along the top an iPad's toolbar has room for a few,
    /// and folds the rest into its overflow menu, where they go by their titles rather than their
    /// identifiers, so that's where `title` finds them.
    @MainActor
    func toolbarItem(_ identifier: String, title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let item = element(identifier)
        if item.waitForExistence(timeout: 3) { return item }
        buttons["More"].firstMatch.waitToAppear(file: file, line: line).tap()
        return buttons[title].firstMatch.waitToAppear(file: file, line: line)
    }

    /// The food search's field. In portrait an iPad's Foods has no room for it beside the tab bar
    /// along the top, so the toolbar keeps it behind its search button, which opens it.
    @MainActor
    func foodSearchField(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        // The pane beside the log has a field of its own.
        let pane = element("logger.search")
        if pane.waitForExistence(timeout: 2) { return pane }
        let field = searchFields.firstMatch
        if Self.isPad, !field.waitForExistence(timeout: 5) {
            buttons["Search"].firstMatch.waitToAppear(file: file, line: line).tap()
        }
        return field.waitToAppear(file: file, line: line)
    }

    /// Closes an iPad's number pad, which iPadOS shows in a popover beside a number field a moment
    /// after typing starts: a tap anywhere else only closes the popover, so the tap meant for the
    /// next field or button would do nothing. With no pad (a keyboard docked along the bottom leaves
    /// other taps alone) there's nothing to close. The tap lands on the navigation bar over the field
    /// typed in, the lowest of those above it: under a sheet the bars behind it are higher up, and a
    /// tap on one of them lands outside the sheet. (With the pad up nothing behind it is hittable,
    /// so that can't tell them apart.) It lands at the spot nearest the bar's middle that's clear of
    /// its buttons and the pad: a sheet's bar can have a menu where the title goes, as the logger's
    /// time does.
    @MainActor
    func closeNumberPad(file: StaticString = #filePath, line: UInt = #line) {
        let pad = popovers.containing(.key, identifier: nil).firstMatch
        guard Self.isPad, pad.waitForExistence(timeout: 3) else { return }
        let field = descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch.frame
        let bars = navigationBars.allElementsBoundByIndex.map { ($0, $0.frame) }.filter { _, frame in
            frame.minX <= field.midX && field.midX <= frame.maxX && frame.maxY <= field.minY
        }
        guard let (bar, frame) = bars.max(by: { $0.1.maxY < $1.1.maxY }) else {
            return XCTFail("No navigation bar above the field being typed in, to close the number pad", file: file, line: line)
        }
        let taken = bar.buttons.allElementsBoundByIndex.map { $0.frame.insetBy(dx: -8, dy: 0) } + [pad.frame]
        // From the middle out, a twentieth of the bar at a time: 0.5, 0.45, 0.55, … 0.1, 0.9.
        let spots: [CGFloat] =
            [0.5]
            + (1...8).flatMap { (step: Int) -> [CGFloat] in
                let offset = 0.05 * CGFloat(step)
                return [0.5 - offset, 0.5 + offset]
            }
        let clear = spots.first { dx in
            let spot = CGPoint(x: frame.minX + frame.width * dx, y: frame.midY)
            return !taken.contains { $0.contains(spot) }
        }
        guard let clear else { return XCTFail("No spot on \(bar) clear of its buttons and the number pad", file: file, line: line) }
        bar.coordinate(withNormalizedOffset: CGVector(dx: clear, dy: 0.5)).tap()
        pad.waitToDisappear(timeout: 5, file: file, line: line)
    }

    /// Scrolls until the element is on screen and can be tapped, or gives up after a few drags.
    /// Each drag holds at its end, so the list stops where it's let go (a tap on a list that's still
    /// gliding only stops it), and a row left above the middle is dragged back down: a list drops
    /// the rows it has scrolled well past. The drags run down the middle of the screen, or of the
    /// column `beside` is in (an iPad's Today has its summary in a column beside the log). A row
    /// behind the Log tab's pinned week and line counts as out of reach: XCUITest calls it hittable,
    /// and the tap lands on them.
    @MainActor
    @discardableResult
    func scrollTo(_ element: XCUIElement, drags: Int = 15, beside: XCUIElement? = nil) -> XCUIElement {
        var left = drags
        let x = beside.map { $0.waitToAppear().frame.midX / frame.width } ?? 0.5
        let pinned = self.element("log.header")
        func reachable() -> Bool { element.exists && element.isHittable && !(pinned.exists && element.frame.midY < pinned.frame.maxY) }
        while !reachable(), left > 0 {
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

    @MainActor
    func waitForLabel(toEqual label: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let same = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [same], timeout: timeout), .completed, "\(self) never read \(label)", file: file, line: line)
    }

    /// Waits for the element to go away, as a sheet does once it's dismissed.
    @MainActor
    func waitToDisappear(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\(self) is still there", file: file, line: line)
    }
}
