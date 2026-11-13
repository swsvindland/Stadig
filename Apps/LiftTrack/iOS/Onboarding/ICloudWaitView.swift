import SwiftUI
import SystemStore

/// A launch that finds Stadig Lift not set up while the person's iCloud has their training (a second
/// device, a reinstall): the wait for it, rather than onboarding over it. The data arriving takes the
/// app straight to Today; iCloud turning out to hold nothing, to onboarding.
struct ICloudWaitView: View {
    let arrival: ICloudArrival
    /// Only after a moment: iCloud usually says there's nothing within a second, and onboarding
    /// should follow a blank moment rather than a flash of this.
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            // Scrolls only when it must (the largest text sizes).
            ScrollView {
                if shown || arrival.phase == .arriving {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            PageTitle(
                                arrival.phase == .arriving ? "Bringing your training from iCloud" : "Looking for your training in iCloud", size: 36
                            )
                            .accessibilityIdentifier("icloud.waiting")
                            Text(
                                arrival.phase == .arriving
                                    ? "Your program and history are on their way. The first time can take a minute."
                                    : "Set up on another device? What you've trained comes here rather than starting again."
                            )
                            .font(.subheadline).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                        }
                        RowCard {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Program, sessions and settings").font(.callout.weight(.semibold)).foregroundStyle(Ink.text)
                                    Text(arrival.phase == .arriving ? "On their way" : "Asking iCloud").font(.caption).foregroundStyle(Ink.text3)
                                }
                                Spacer(minLength: 8)
                                ProgressView().controlSize(.small).tint(Ink.text3)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if let problem = arrival.problem {
                            Label(problem, systemImage: "exclamationmark.icloud")
                                .font(.footnote)
                                .foregroundStyle(Ink.text2)
                                .padding(.horizontal, 4)
                                .accessibilityIdentifier("icloud.problem")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 56)
                    .readableWidth(560)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // From the moment anything shows: iCloud can take its full 10 seconds to answer.
            if shown || arrival.phase == .arriving {
                Button {
                    arrival.setUpAsNew()
                } label: {
                    Text("Set up as new").frame(maxWidth: .infinity)
                }
                .secondaryAction()
                .controlSize(.large)
                .accessibilityHint("Starts setup on this device without waiting")
                .accessibilityIdentifier("icloud.setUpAsNew")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .readableWidth(560)
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
