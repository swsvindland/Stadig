import SwiftUI
import SystemStore

/// A launch that finds Stadig not set up while the person's iCloud has their rhythm (a second device,
/// a reinstall): the wait for it, rather than setup over it. The rhythm arriving takes the app straight
/// to Today; iCloud turning out to hold nothing, to setup.
struct ICloudWaitView: View {
    let arrival: ICloudArrival
    /// Only after a moment: iCloud usually says there's nothing within a second, and onboarding
    /// should follow a blank moment rather than a flash of this.
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            // Scrolls only when it must (the largest text sizes), and sits in the middle otherwise.
            ScrollView {
                if shown || arrival.phase == .arriving {
                    VStack(spacing: 18) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 52))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(arrival.phase == .arriving ? "Bringing your rhythm from iCloud" : "Looking for your rhythm in iCloud")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("icloud.waiting")
                        if arrival.phase == .arriving {
                            Text("Your week is on its way. The first time can take a minute.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView()
                        if let problem = arrival.problem {
                            Label(problem, systemImage: "exclamationmark.icloud")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("icloud.problem")
                        }
                    }
                    .padding(24)
                    .readableWidth(560)
                }
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .scrollBounceBehavior(.basedOnSize)
            // From the moment anything shows: iCloud can take its full 10 seconds to answer.
            if shown || arrival.phase == .arriving {
                Button("Set up as new") { arrival.setUpAsNew() }
                    .secondaryAction()
                    .accessibilityHint("Starts setup on this device without waiting")
                    .accessibilityIdentifier("icloud.setUpAsNew")
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.pageBackground)
        .animation(.default, value: shown)
        .animation(.default, value: arrival.phase)
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            shown = true
        }
    }
}
