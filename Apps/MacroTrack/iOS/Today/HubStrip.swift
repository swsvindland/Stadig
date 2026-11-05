import SwiftUI

/// What's left of your day, from the hub. It's only here for someone who uses the hub, and it's one
/// line, because this app has its own screen to fill.
struct HubStrip: View {
    @Environment(\.openURL) private var openURL
    let line: String

    var body: some View {
        Button {
            if let url = URL(string: "stadig://today") { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.day.timeline.left").foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your day").font(.footnote).foregroundStyle(.secondary)
                    Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Stadig")
        .accessibilityIdentifier("today.hubStrip")
    }
}
