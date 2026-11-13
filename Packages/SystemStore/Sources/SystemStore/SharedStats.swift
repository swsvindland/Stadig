import Foundation
import SystemCore

extension StatsBoard {
    /// The fitness stats as either app shows them: its own, and the other app's once that one is set
    /// up too, each saying which app it comes from (`StatLine.apps`, with each app's own number in
    /// `sources`). Read from what both publish to the shared container, so Stadig Lift and Stadig
    /// Macro give the same answer on every device.
    /// Each line says how far it moved this month, from the score histories both record.
    public static func lines(shared: SharedContainer, today: Day, timeZone: TimeZone = .current) -> [StatLine] {
        lines(
            lift: shared.read(.summary(.liftTrack)), macro: shared.read(.summary(.macroTrack)),
            histories: [shared.read(.scores(.liftTrack)), shared.read(.scores(.macroTrack))].compactMap(\.self), today: today, timeZone: timeZone)
    }

    /// Whether both apps are publishing, from the shared container.
    public static func bothApps(shared: SharedContainer, today: Day, timeZone: TimeZone = .current) -> Bool {
        bothApps(lift: shared.read(.summary(.liftTrack)), macro: shared.read(.summary(.macroTrack)), today: today, timeZone: timeZone)
    }
}

extension SharedContainer {
    /// Adds the day's readings to the app's score history in the container, which is how it's kept:
    /// the file as it is (another device's copy, if that's what iCloud last brought) merged with
    /// `kept`, the history the app last had, so days recorded on a device whose copy lost the race
    /// come back; then the day's readings in and the old thinned (`ScoreHistory.recording`). Written
    /// only when that changes the file. Returns the history, for the app to keep.
    @discardableResult
    public func recordScores(_ readings: [StatReading], by app: AppID, on day: Day, kept: ScoreHistory? = nil) throws -> ScoreHistory {
        let file = read(.scores(app))
        var history = ScoreHistory(app: app)
        if let kept { history = history.merged(with: kept) }
        if let file { history = history.merged(with: file) }
        history = history.recording(readings, on: day)
        if history != file { try write(history, to: .scores(app), by: app) }
        return history
    }
}
