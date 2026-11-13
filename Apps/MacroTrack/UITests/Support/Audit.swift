import XCTest

/// Running Apple's accessibility audit on a screen, less what it can't judge in these apps.
extension XCUIApplication {
    /// Audits what's on screen now. `page` is how many screens down it's scrolled, `place` names it in
    /// what's printed for each issue, and `contrast` adds the contrast check (see `auditTypes`).
    @MainActor
    func auditScreen(_ place: String, page: Int, contrast: Bool) throws {
        try performAccessibilityAudit(for: Self.auditTypes(contrast: contrast)) { issue in
            let ignored = self.isFalsePositive(issue, page: page)
            let element = issue.element
            // One line an issue, ignored or not, for the run's log.
            print(
                "AUDIT|\(place)#\(page)|\(issue.auditType.name)|\(issue.compactDescription)|\(ignored ? "ignored" : "ISSUE")"
                    + "|\(element?.identifier ?? "")|\(element?.label ?? "")|\(element?.frame ?? .zero)")
            return ignored
        }
    }

    /// Hit regions, descriptions, traits and text without an element. Not Dynamic Type or clipped
    /// text, which the large sizes' screenshots check instead (docs/testing.md): here the audit flags
    /// every caption2 (whose smallest size is its default one), the numerals' deliberate caps,
    /// Settings' system rows and, now and then, words under a sheet's foot, and it only predicts
    /// clipping for every label held to a line, those that shrink to fit or stack included, while
    /// it passes text that grows but breaks its row. Contrast only when asked, on a simulator with
    /// Increase Contrast on: at the default contrast its reading of small type fails greys that pass
    /// 4.5:1 by their colours, and a few of the light theme's tints sit just under it (docs/design.md).
    static func auditTypes(contrast: Bool) -> XCUIAccessibilityAuditType {
        var types = XCUIAccessibilityAuditType.all.subtracting([.textClipped, .dynamicType])
        if !contrast { types.remove(.contrast) }
        return types
    }

    /// Whether the audit can't judge this issue here, and why.
    @MainActor
    private func isFalsePositive(_ issue: XCUIAccessibilityAuditIssue, page: Int) -> Bool {
        // The keyboard's suggestions are the system's, not the app's.
        if issue.detailedDescription.contains("TUIPrediction") { return true }
        // A food's marker, an emoji in its square, or the dot between two numbers: decoration hidden
        // from VoiceOver (Stadig Macro's FoodTile, the Log tab's day line), which the audit reads all
        // the same.
        if let label = issue.element?.label, !label.isEmpty, label.allSatisfy({ $0.isEmojiMarker || $0 == "·" }) { return true }
        switch issue.auditType {
        case .elementDetection:
            // Text drawn without an element of its own, and nothing to point at: a chart's axis and the
            // scale under a ruler, which the chart or its card says in words, and Your shape's corners,
            // whose figure reads every score.
            return issue.element == nil
        case .hitRegion:
            // Only a control needs a fingertip's room: a slim ruler or a legend that VoiceOver can read
            // isn't one.
            guard let element = issue.element else { return false }
            return !Self.controls.contains(element.elementType)
        case .contrast:
            // Words passing under the tab bar, a floating foot or the soft edges a scrolled page fades
            // into under the status bar: measured against what half hides them.
            guard let frame = issue.element?.frame, !frame.isEmpty else { return false }
            let screen = windows.firstMatch.frame
            return frame.maxY > screen.maxY - 190 || (page > 0 && frame.minY < screen.minY + 120)
        default:
            return false
        }
    }

    private static let controls: Set<XCUIElement.ElementType> = [
        .button, .link, .cell, .switch, .toggle, .slider, .stepper, .textField, .searchField, .segmentedControl, .menuButton,
        .popUpButton, .picker,
    ]
}

extension Character {
    /// An emoji drawn as a picture ("🍌"), not a digit or a symbol that happens to have an emoji form.
    fileprivate var isEmojiMarker: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (unicodeScalars.count > 1 && first.properties.isEmoji && !first.isASCII)
    }
}

extension XCUIAccessibilityAuditType {
    fileprivate var name: String {
        switch self {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "description"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "\(rawValue)"
        }
    }
}
