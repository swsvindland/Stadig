import Foundation
import SystemStore

/// What the App Store says has been paid for. Only ever its word, never anything the app keeps.
public struct Ownership: Equatable, Sendable {
    /// The one-time purchase.
    public var lifetime: Bool
    /// The monthly subscription, while it's running.
    public var subscribed: Bool

    public init(lifetime: Bool = false, subscribed: Bool = false) {
        self.lifetime = lifetime
        self.subscribed = subscribed
    }
}

/// Someone's free days, kept in the app's own synced store: their other devices agree, and a
/// reinstall on the same iCloud account carries on where it was. Nobody signs up for anything. It
/// isn't protected against someone resetting it, and needn't be: one more day never runs out, so the
/// most a reset buys is not being asked for a while.
public struct AccessRecord: StoredRecord, Equatable {
    public static let kind = "access"
    public static let schemaVersion = 1
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000AC55")!

    public var id: UUID = Self.singletonID
    /// When "Free for 21 days" was chosen.
    public var freeSince: Date?
    /// How long the last "one more day" holds the offer back.
    public var extendedUntil: Date?
    public var updatedAt: Date

    public init(freeSince: Date? = nil, extendedUntil: Date? = nil, updatedAt: Date) {
        self.freeSince = freeSince
        self.extendedUntil = extendedUntil
        self.updatedAt = updatedAt
    }
}

/// Where someone stands with an app.
public enum Standing: Equatable, Sendable {
    /// The App Store hasn't answered yet. Treated as paid for: a buyer mustn't meet the paywall in
    /// the moment before it does, and nobody loses anything if a non-buyer gets a moment's grace.
    case checking
    /// Bought outright.
    case bought
    case subscribed
    /// Hasn't chosen yet: the offer that ends onboarding is still to be answered.
    case undecided
    case free(daysLeft: Int)
    /// The free days are over and a "one more day" is running.
    case extended(until: Date)
    /// The free days are over and nothing is holding the offer back.
    case lapsed
}

/// The rules, the same in every app.
public enum Access {
    public static let freeDays = 21

    public static func standing(owned: Ownership?, record: AccessRecord?, now: Date, calendar: Calendar) -> Standing {
        guard let owned else { return .checking }
        if owned.lifetime { return .bought }
        if owned.subscribed { return .subscribed }
        guard let record, let start = record.freeSince else { return .undecided }
        if let end = calendar.date(byAdding: .day, value: freeDays, to: start), now < end {
            return .free(daysLeft: daysLeft(until: end, now: now, calendar: calendar))
        }
        if let until = record.extendedUntil, now < until { return .extended(until: until) }
        return .lapsed
    }

    /// Whole days to the end, rounded up, so the last hours still read "1 day" and never "0". Never
    /// more than the whole allowance, whatever a clock set back says.
    static func daysLeft(until end: Date, now: Date, calendar: Calendar) -> Int {
        let whole = calendar.dateComponents([.day], from: now, to: end).day ?? 0
        let partDay = calendar.date(byAdding: .day, value: whole, to: now).map { $0 < end } ?? false
        return min(freeDays, max(1, whole + (partDay ? 1 : 0)))
    }

    /// When a "one more day" chosen now runs out. A calendar day, so a clock change never shortens it.
    public static func extended(from now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
    }
}

extension Standing {
    /// May someone use what's paid for? The free parts of each app never ask.
    public var unlocked: Bool {
        switch self {
        case .checking, .bought, .subscribed, .free, .extended: true
        case .undecided, .lapsed: false
        }
    }
}
