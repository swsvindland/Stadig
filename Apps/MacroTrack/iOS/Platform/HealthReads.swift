import Foundation

/// When Health is read: when asked (Connect Apple Health, pull to refresh), on each change its
/// observer reports, and on a return to the app unless it was read in the last few minutes, since
/// the observer hears nothing while the app is suspended. An observer query calls its handler once
/// as it starts, which reports no change: that call counts as a return, so a launch (the launch
/// read, the scene becoming active, the observer starting) reads Health once. Weigh-ins are read
/// from where the last read left off, and their whole window only when the anchor may have passed
/// some by (`readsWholeWindow`).
struct HealthReads {
    enum Reason { case asked, changed, returned }

    /// A read this recent makes a return's read unnecessary.
    static let fresh: TimeInterval = 5 * 60
    /// How soon after the observer starts its own first call comes. A call later than this is a
    /// change: the first call may not have come at all.
    static let observerStartCall: TimeInterval = 10

    private(set) var last: Date?
    /// When the observer started, until its first call.
    private var observerStart: Date?
    /// The earliest moment this run has read Health's weigh-ins whole from, rather than by the anchor.
    private(set) var windowReadFrom: Date?

    mutating func observerStarted(at now: Date) { observerStart = now }

    /// Whether a read by anchor needs the whole window (weigh-ins from `since` on) read beside it.
    /// The anchor moves past samples Health hid (no permission yet, or given since in the Settings
    /// app) and those before the window, so the window is read whole once a run, after "Connect
    /// Apple Health" (`permissionAsked`), and when it reaches further back. A first read, with no
    /// anchor, is whole already.
    func readsWholeWindow(since: Date, anchored: Bool) -> Bool {
        anchored && (windowReadFrom.map { since < $0 } ?? true)
    }

    /// Notes that the weigh-ins from `since` on have been read, by anchor or whole.
    mutating func windowRead(since: Date) { windowReadFrom = min(since, windowReadFrom ?? since) }

    /// What Health hid before reading was allowed is there now, behind the anchor.
    mutating func permissionAsked() { windowReadFrom = nil }

    /// Whether to read Health for this reason now, noting the read when it is one.
    mutating func shouldRead(_ reason: Reason, now: Date) -> Bool {
        var reason = reason
        if reason == .changed, let start = observerStart {
            observerStart = nil
            if now.timeIntervalSince(start) < Self.observerStartCall { reason = .returned }
        }
        if reason == .returned, let last, now.timeIntervalSince(last) < Self.fresh { return false }
        last = now
        return true
    }
}

/// What to say where there's no Apple Health (the Mac), honestly: only what Macro Track keeps in its
/// own synced records reaches it.
enum HealthWords {
    static let notOnThisDevice =
        "Apple Health lives on iPhone, iPad, Apple Watch and Apple Vision Pro. Weigh-ins Macro Track reads from Health there reach this Mac with the rest of your log. Food you log here is saved to Health only from a device that has it: it stays in Macro Track and syncs to your other devices."
}
