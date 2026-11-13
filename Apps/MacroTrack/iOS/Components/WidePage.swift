import SwiftUI

// A wide screen's page furniture (iPad, the Mac, Vision Pro), in the phone's voice: the page's own
// header (an eyebrow over the 32-point title, its round buttons beside them) in place of the
// system's navigation title, on the ink ground. Controls a bar is the place for (a search field, a
// table's columns) stay in it: an iPad's sit in the tab bar's row, the Mac's in the window's toolbar.

/// A wide page's header: `PageHeader` at a wide page's margins.
struct WideHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    @ViewBuilder let trailing: Trailing

    init(eyebrow: String?, title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        PageHeader(eyebrow: eyebrow, title: title) { trailing }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
}

extension View {
    /// A wide page whose header is its own (`WideHeader`): the bar keeps its controls but not the
    /// title, which the header says, and the Mac's window doesn't say it again either. A phone's
    /// page (`wide` false) is left as it is.
    func widePage(_ wide: Bool = true) -> some View {
        toolbar(removing: wide ? .title : nil)
    }

    /// A round button's face as a menu's label: the menu opens from it with no arrow beside it.
    func circleMenuStyle() -> some View {
        menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}
