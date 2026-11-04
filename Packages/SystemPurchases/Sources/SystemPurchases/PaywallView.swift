import StoreKit
import SwiftUI

/// Apple's terms and our privacy page, which it wants within reach of any subscribe button.
private enum LegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://stadig.dev/privacy")!
    static let subscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

/// The offer, whichever way it's reached: the page that ends onboarding, the prompt on opening the
/// app once the free days are over, and the gates and Settings. It reads what to say from where the
/// person stands, so every route says the same thing.
public struct PaywallView: View {
    /// The Mac's window for it, where an app opens it as one (a sheet elsewhere).
    public static let windowID = "unlock"

    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase

    public init() {}

    private var appName: String { purchases.configuration.appName }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title).font(.largeTitle.bold()).accessibilityIdentifier("paywall.title")
                    Text(detail).foregroundStyle(.secondary)
                    if purchases.stillSubscribed {
                        cancelSubscription
                    } else {
                        benefits
                        choices
                        finePrint
                    }
                }
                .padding(24)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .toolbar {
                if purchases.canPutOff {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(purchases.stillSubscribed ? "Done" : "Not now") { dismiss() }.accessibilityIdentifier("paywall.notNow")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 560, idealHeight: 720)
        #endif
        .interactiveDismissDisabled(!purchases.canPutOff)
        .task { await purchases.loadProducts() }
        // Answered, however it was: a purchase, one more day, or one confirmed late (Ask to Buy, the
        // App Store answering at launch). Someone who has just bought over a subscription stays to
        // hear that it's still running.
        .onChange(of: purchases.standing) { _, _ in
            if !purchases.stillSubscribed { dismiss() }
        }
    }

    private var title: String {
        switch purchases.standing {
        case .undecided: "Try \(appName) free"
        case .lapsed: "Your \(Access.freeDays) free days are up"
        case .bought: "It's yours"
        default: "\(appName), for good"
        }
    }

    private var detail: String {
        let prices: String? =
            if let once = purchases.price(.oneTime), let monthly = purchases.price(.monthly) { "\(once) once or \(monthly) a month" } else { nil }
        return switch purchases.standing {
        case .undecided:
            prices.map { "Use all of it for \(Access.freeDays) days, with no account and no card. After that it's \($0)." }
                ?? "Use all of it for \(Access.freeDays) days, with no account and no card."
        case .free(let daysLeft):
            "\(daysLeft == 1 ? "1 free day" : "\(daysLeft) free days") left. \(pitch)"
        case .lapsed:
            "If \(appName) has earned its place, buy it or subscribe. Not sure yet? Take another day."
        case .subscribed:
            "You're subscribed. Buy it once and you can cancel the subscription."
        case .bought:
            "You own \(appName) now, but your subscription is still running. Cancel it so it doesn't renew."
        case .checking, .extended:
            pitch
        }
    }

    private var pitch: String { "Buy it once, or subscribe if you'd rather pay as you go." }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(purchases.configuration.benefits, id: \.self) { benefit in
                Label(benefit.text, systemImage: benefit.symbol)
            }
            Label("One price for all your devices", systemImage: "macbook.and.iphone")
        }
    }

    private var choices: some View {
        VStack(spacing: 12) {
            buyButton(.oneTime, label: purchases.price(.oneTime).map { "Buy for \($0)" } ?? "Buy once", identifier: "paywall.buy")
                .prominentAction()
            if purchases.standing != .subscribed {
                buyButton(.monthly, label: purchases.price(.monthly).map { "\($0) a month" } ?? "Subscribe monthly", identifier: "paywall.subscribe")
                    .quietAction()
            }
            if purchases.loadingProducts {
                ProgressView().controlSize(.small).accessibilityIdentifier("paywall.loading")
            } else if purchases.pricesUnavailable {
                pricesProblem
            }
            switch purchases.standing {
            case .undecided:
                Button {
                    purchases.startFreeDays()
                } label: {
                    wide("Free for \(Access.freeDays) days")
                }
                .quietAction()
                .accessibilityIdentifier("paywall.free")
            case .lapsed:
                Button {
                    purchases.oneMoreDay()
                } label: {
                    wide("Just one more day")
                }
                .quietAction()
                .accessibilityIdentifier("paywall.oneMoreDay")
            default:
                EmptyView()
            }
            Button("Restore purchase") { Task { await purchases.restore() } }
                .accessibilityIdentifier("paywall.restore")
            if let message = purchases.message {
                Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("paywall.message")
            }
        }
        .controlSize(.large)
    }

    private func buyButton(_ plan: Plan, label: String, identifier: String) -> some View {
        Button {
            Task { await purchases.buy(plan) { try await purchase($0) } }
        } label: {
            wide(label)
        }
        .disabled(purchases.price(plan) == nil || purchases.purchasing)
        .accessibilityIdentifier(identifier)
    }

    private func wide(_ label: String) -> some View {
        Text(label).font(.headline).frame(maxWidth: .infinity)
    }

    /// Never just a greyed-out button: a purchase that can't start says so, and can be tried again.
    private var pricesProblem: some View {
        HStack {
            Text("The App Store didn't answer, so these can't be bought just now.").font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("Try again") { Task { await purchases.loadProducts() } }.accessibilityIdentifier("paywall.retry")
        }
    }

    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(terms).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: LegalLinks.terms).accessibilityIdentifier("paywall.terms")
                Link("Privacy Policy", destination: LegalLinks.privacy).accessibilityIdentifier("paywall.privacy")
            }
            .font(.footnote)
        }
    }

    private var terms: String {
        let renewal = purchases.price(.monthly).map { "every month at \($0)" } ?? "every month"
        return
            "The subscription renews \(renewal) until you cancel, at least 24 hours before it renews, in your Apple Account's subscription settings. Your Apple Account is charged when you confirm and at each renewal."
    }

    private var cancelSubscription: some View {
        Link(destination: LegalLinks.subscriptions) { wide("Manage subscription") }
            .prominentAction()
            .controlSize(.large)
            .accessibilityIdentifier("paywall.manage")
    }
}

/// What Settings shows: where someone stands, and the way to the offer. `showOffer` opens the
/// paywall however the app does from there (a sheet from the form, a window on the Mac).
public struct PurchaseSection: View {
    @Environment(Purchases.self) private var purchases
    private let showOffer: () -> Void

    public init(showOffer: @escaping () -> Void) { self.showOffer = showOffer }

    public var body: some View {
        if purchases.configuration.enabled {
            Section(purchases.configuration.appName) {
                switch purchases.standing {
                case .bought:
                    Label("Yours for good. Thank you.", systemImage: "checkmark.seal.fill")
                    if purchases.stillSubscribed {
                        Text("Your subscription is still running. Cancel it so it doesn't renew.").font(.footnote).foregroundStyle(.secondary)
                        manage
                    }
                case .subscribed:
                    Label("Subscribed. Thank you.", systemImage: "checkmark.seal.fill")
                    manage
                    offer("Buy it for good")
                case .free(let daysLeft):
                    Label(daysLeft == 1 ? "1 free day left" : "\(daysLeft) free days left", systemImage: "calendar")
                    offer("Buy or subscribe")
                    restore
                default:
                    offer("Buy or subscribe")
                    restore
                }
                if let message = purchases.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func offer(_ title: String) -> some View {
        Button(title, systemImage: "lock.open", action: showOffer).accessibilityIdentifier("settings.unlock")
    }

    private var restore: some View {
        Button("Restore purchase") { Task { await purchases.restore() } }.accessibilityIdentifier("settings.restorePurchase")
    }

    private var manage: some View {
        Link("Manage subscription", destination: LegalLinks.subscriptions).accessibilityIdentifier("settings.manageSubscription")
    }
}

extension View {
    /// The apps' main action: glass, or Vision Pro's bordered prominent style (its SDK has no glass).
    fileprivate func prominentAction() -> some View {
        #if os(visionOS)
        buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        #else
        buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        #endif
    }

    /// The apps' other actions, the same way.
    fileprivate func quietAction() -> some View {
        #if os(visionOS)
        buttonStyle(.bordered).buttonBorderShape(.capsule)
        #else
        buttonStyle(.glass).buttonBorderShape(.capsule)
        #endif
    }
}
