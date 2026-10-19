import SwiftUI

/// How large the live session draws. The phone keeps its sizes; a wide screen (an iPad propped up in
/// the gym, the Mac's session window) gets bigger targets and numbers, and the hardware keyboard's
/// shortcuts: 1, 2 and 3 rate a set, Return logs one with nothing to rate, ↑ and ↓ move the weight,
/// + and − the reps, Space ends a rest.
enum SessionScale {
    case compact, large

    var isLarge: Bool { self == .large }

    /// The − and + buttons: a fingertip on the iPad, a click on the Mac.
    var stepButton: CGFloat { isLarge ? (Platform.isMac ? 40 : 56) : 36 }
    var ratingHeight: CGFloat { isLarge ? (Platform.isMac ? 96 : 120) : 84 }
    /// The rest countdown.
    var restSize: CGFloat { isLarge ? 96 : 44 }
    /// A timed set's countdown and the conditioning clock.
    var clockSize: CGFloat { isLarge ? 72 : 40 }
    var valueFont: Font { isLarge ? .largeTitle.weight(.semibold).monospacedDigit() : .title3.weight(.semibold).monospacedDigit() }
    var titleFont: Font { isLarge ? .title.bold() : .title3.bold() }

    /// A key for a control, in the large layout only: the phone's session is unchanged.
    func shortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> KeyboardShortcut? {
        isLarge ? KeyboardShortcut(key, modifiers: modifiers) : nil
    }
}

extension EnvironmentValues {
    @Entry var sessionScale: SessionScale = .compact
}
