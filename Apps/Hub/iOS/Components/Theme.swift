import HubEngine
import SwiftUI
import SystemCore

// Liquid Glass belongs to the controls that float over content. Content sits on quiet grouped
// surfaces, as in the other apps.

extension ShapeStyle where Self == Color {
    static var pageBackground: Color { .groupedBackground }
    static var cardBackground: Color { .secondaryGroupedBackground }
    static var insetBackground: Color { .tertiaryGroupedBackground }
}

extension Color {
    /// The surface that stands out most, for what's next and what's selected: ink in light mode and
    /// paper in dark. The colour rather than the `.primary` style, which would follow whatever
    /// foreground is set on it. Vision Pro's glass has no dark or light of its own to invert, and
    /// there `.background` is as pale as `.primary`, so it's spelled out.
    static var strongFill: Color { Platform.isVision ? .white : .primary }
    /// What reads on `strongFill`.
    static var onStrongFill: Color { Platform.isVision ? .black : .groupedBackground }
}

extension HubItem.Kind {
    /// One colour per kind, used everywhere it appears.
    var color: Color {
        switch self {
        case .lift: .red
        case .activity: .orange
        case .meal: .green
        case .study: .indigo
        case .work: .gray.mix(with: .blue, by: 0.25)
        case .commute: .gray.opacity(0.6)
        }
    }

    var label: String {
        switch self {
        case .lift: "Gym"
        case .activity: "Classes"
        case .meal: "Meals"
        case .study: "Study"
        case .work: "Work or school"
        case .commute: "Commute"
        }
    }
}

extension View {
    /// A content card: grouped surface, continuous corners.
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cardBackground, in: .rect(cornerRadius: radius))
    }

    /// The one action that matters on a screen.
    func primaryAction() -> some View { self.prominentGlassButtonStyle().buttonBorderShape(.capsule) }

    func secondaryAction() -> some View { self.glassButtonStyle().buttonBorderShape(.capsule) }

    /// Readable line length in a wide window.
    func readableWidth(_ width: CGFloat = 720) -> some View { frame(maxWidth: width).frame(maxWidth: .infinity) }

    /// The width a tab's page reads at: a column on iPhone, most of a wide window elsewhere.
    func pageWidth(_ sizeClass: UserInterfaceSizeClass?) -> some View { readableWidth(sizeClass == .regular ? 1000 : 720) }
}

/// Cards one under another in a narrow window, and in columns in a wide one, so a day fills a Mac or
/// iPad window rather than running down one long column.
struct CardColumns<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        if sizeClass == .regular {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: spacing, alignment: .top)], alignment: .leading, spacing: spacing) {
                content
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) { content }
        }
    }
}

/// A small heading inside a card.
struct CardHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Opens one of the other apps. The hub logs nothing, so this is all a button here ever does.
struct OpenAppButton<Label: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let app: AppID
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            guard let url = HubLink.url(for: app) else { return }
            openURL(url) { accepted in
                if !accepted { model.missingApp = app }
            }
        } label: {
            label
        }
    }
}

/// Minutes from midnight as a time to pick. Ends past midnight come back within the day: whoever
/// holds the value decides what that means.
struct ClockField: View {
    /// A day with no clock change anywhere, so every time exists on it.
    private static let reference = Date(timeIntervalSinceReferenceDate: 14 * 86_400)

    let title: LocalizedStringKey
    @Binding var minutes: Int

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: {
                    let total = minutes % 1440
                    return Calendar.current.date(bySettingHour: total / 60, minute: total % 60, second: 0, of: Self.reference) ?? Self.reference
                },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }), displayedComponents: .hourAndMinute)
    }
}
