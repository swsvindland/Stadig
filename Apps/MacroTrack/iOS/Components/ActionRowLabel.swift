import SwiftUI

/// A form row's action in the ink's voice rather than the accent's: the symbol grey in a column of
/// its own, the words in the text colour, as the design's rows that open something are. The accent
/// is kept for a screen's one action.
struct ActionRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon.foregroundStyle(Ink.text2).frame(width: 24)
            configuration.title.foregroundStyle(Ink.text)
        }
    }
}

extension LabelStyle where Self == ActionRowLabelStyle {
    /// A form row's action: grey symbol, words in the text colour.
    static var actionRow: ActionRowLabelStyle { ActionRowLabelStyle() }
}

extension View {
    /// The labels of a form's rows as `.actionRow`. On the Mac a form's buttons are buttons, not
    /// rows, and keep the system's look.
    func actionRows() -> some View {
        #if os(macOS)
        self
        #else
        labelStyle(.actionRow)
        #endif
    }
}
