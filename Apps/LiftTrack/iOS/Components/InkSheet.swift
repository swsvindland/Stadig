import SwiftUI

// Sheets and settings on the boards' terms rather than the system's: no bar of glass capsules over a
// small title, but the page's own furniture. A round close at the top left (as the session's bar and
// the exercise page have their round buttons), the title set large in the content (`DetailHeader`),
// and the one action full width at the foot (as onboarding's Continue and the summary's Done). A sheet
// still swipes down to close.

/// A sheet's top: the round close at the left and, at the right, a round button or a small action.
/// What scrolls passes under it.
struct SheetBar<Trailing: View>: View {
    let symbol: String
    let label: String
    let identifier: String
    let close: () -> Void
    let trailing: Trailing

    init(
        symbol: String = "xmark", label: String = "Close", identifier: String, close: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.symbol = symbol
        self.label = label
        self.identifier = identifier
        self.close = close
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            CircleIconButton(symbol: symbol, label: label, identifier: identifier, action: close)
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(Color.pageBackground)
    }
}

/// A sheet's one action (and a quiet one beside it, if any), full width at the foot on the ground,
/// what scrolls fading under it.
struct SheetFoot<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) { content }
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .readableWidth(620)
            .background(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.pageBackground.opacity(0), Color.pageBackground], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)
                )
                .padding(.top, -20)
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

extension View {
    /// A sheet that draws its own bar (`SheetBar`) and foot (`SheetFoot`) in place of the system's
    /// navigation bar, on the ink ground.
    func inkSheet<Bar: View, Foot: View>(@ViewBuilder bar: () -> Bar, @ViewBuilder foot: () -> Foot) -> some View {
        // Grouped on the Mac too, where a sheet's form would otherwise set its rows in columns.
        formStyle(.grouped)
            .hidesNavigationBar()
            .safeAreaInset(edge: .top, spacing: 0) { bar() }
            .safeAreaInset(edge: .bottom, spacing: 0) { foot() }
            .background(.pageBackground)
    }

    /// A sheet with its own bar and nothing at the foot: one that closes, or acts from its rows.
    func inkSheet<Bar: View>(@ViewBuilder bar: () -> Bar) -> some View {
        // No inset at the foot at all: an empty one there leaves the content nothing to show in.
        formStyle(.grouped)
            .hidesNavigationBar()
            .safeAreaInset(edge: .top, spacing: 0) { bar() }
            .background(.pageBackground)
    }

    /// A row of a form that sits on the ground rather than on a card: its heading, its buttons.
    func groundRow() -> some View {
        listRowBackground(Color.clear).listRowInsets(EdgeInsets())
    }
}

/// A form's title, set large at its top as a pushed page's is (`DetailHeader`): where it was opened
/// from as an eyebrow, the title, and what it's for. On the ground, not in a row.
struct FormHeading: View {
    var eyebrow: String?
    let title: String
    var detail: String?

    var body: some View {
        // The section's header rather than a row: a row's small text at its leading edge loses the
        // left of its first letter.
        Section {
        } header: {
            SheetHeading(eyebrow: eyebrow, title: title, detail: detail)
                .textCase(nil)
                .padding(.bottom, 4)
                .listRowInsets(EdgeInsets())
        }
    }
}

/// A sheet's title in a scrolling page: `DetailHeader`, and what it's for under it.
struct SheetHeading: View {
    var eyebrow: String?
    let title: String
    var detail: String?

    var body: some View {
        // `DetailHeader`'s eyebrow and title, spelled out: in a form's row its tracked eyebrow is
        // measured narrower than it's drawn, and its first letter spills past the row's edge.
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow.uppercased()).eyebrow().lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            PageTitle(title)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Search in a sheet's content, on the raised grey, rather than the system's field in its bar.
struct InkSearchField: View {
    @Binding var text: String
    let prompt: String
    let identifier: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Ink.text3).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .font(.callout)
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Ink.raised, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// One of several things that can each be on (the joints that hurt), as the weekday chips are: the
/// accent when on, the raised grey when off.
struct ChoiceChip: View {
    let title: String
    let isOn: Bool
    let identifier: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? Color.accentColor : Ink.raised, in: .rect(cornerRadius: 12, style: .continuous))
                .foregroundStyle(isOn ? Ink.onAccent : Ink.text)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// A label over a value in a card's row: "From", "Nov 20".
struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(Ink.text2)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Ink.text).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A page pushed inside a sheet or Settings that sets its own title large (`FormHeading`): the
    /// bar keeps only its round back button. The Mac's panes keep their window title, and no heading.
    func formPage(_ title: String) -> some View {
        detailPage(title: title, wide: false)
    }
}

/// A form's quiet action on the ground under its cards: Delete, Remove, End it now. Destructive ones
/// say so in red.
struct FormActionRow: View {
    let title: String
    var destructive = false
    let identifier: String?
    let action: () -> Void

    init(_ title: String, destructive: Bool = false, identifier: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.destructive = destructive
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).foregroundStyle(destructive ? Ink.bad : Ink.text).frame(maxWidth: .infinity)
        }
        .buttonStyle(.ghost)
        .controlSize(.large)
        .accessibilityIdentifier(identifier ?? "")
        .groundRow()
    }
}
