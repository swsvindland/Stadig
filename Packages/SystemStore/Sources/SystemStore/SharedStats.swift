import Foundation
import SystemCore

extension StatsBoard {
    /// The fitness stats as either app shows them: its own, and the other app's once that one is set
    /// up too, each saying which app it comes from (`StatLine.apps`, with each app's own number in
    /// `sources`). Read from what both publish to the shared container, so Stadig Lift and Stadig
    /// Macro give the same answer on every device.
    public static func lines(shared: SharedContainer, today: Day, timeZone: TimeZone = .current) -> [StatLine] {
        lines(lift: shared.read(.summary(.liftTrack)), macro: shared.read(.summary(.macroTrack)), today: today, timeZone: timeZone)
    }

    /// Whether both apps are publishing, from the shared container.
    public static func bothApps(shared: SharedContainer, today: Day, timeZone: TimeZone = .current) -> Bool {
        bothApps(lift: shared.read(.summary(.liftTrack)), macro: shared.read(.summary(.macroTrack)), today: today, timeZone: timeZone)
    }
}
