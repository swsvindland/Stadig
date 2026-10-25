import ExerciseLibrary
import Foundation
import SystemCore

/// One row of the History table: a Stadig Lift session or an outside activity, with plain sort keys
/// for every column (a missing value sorts as the least).
public struct HistoryRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case session
        case activity(ActivityType)
    }

    /// A session's heaviest work, by estimated one-rep max.
    public struct TopSet: Hashable, Sendable {
        public var set: LoggedSet
        public var e1rm: Double
    }

    public var id: UUID
    public var kind: Kind
    public var date: Date
    /// The session's title, or the activity's type.
    public var name: String
    public var minutes: Int
    /// Work sets logged; 0 for an outside activity.
    public var workSets: Int
    public var topSet: TopSet?
    /// Where it was recorded: the device a session ran on, or where an activity came from ("Health ·
    /// Strava", "Logged by hand", "Declared").
    public var source: String
    /// An outside activity's effort, 1–10.
    public var effort: Int?
    /// Lowercased name and exercise names, for the search field.
    public var searchText: String

    public var isSession: Bool { kind == .session }
    /// Sort key for the top-set column.
    public var topSetE1RM: Double { topSet?.e1rm ?? 0 }

    /// Every session and outside activity, newest first. The top set is read by each exercise's own
    /// load basis and the person's trust, as the analysis reads it.
    public static func rows(sessions: [SessionRecord], activities: [ActivityLog], catalog: ExerciseCatalog, trust: TrustState) -> [HistoryRow] {
        let sessionRows = sessions.map { session -> HistoryRow in
            var top: TopSet?
            var names: [String] = []
            for log in session.exercises {
                for set in log.sets where set.kind.countsAsWork {
                    let exercise = catalog.resolve(set.exerciseID)
                    if let e1rm = StrengthEstimator.estimate(set, basis: exercise.loadBasis, trust: trust), e1rm > (top?.e1rm ?? 0) {
                        top = TopSet(set: set, e1rm: e1rm)
                    }
                }
                names.append(catalog.resolve(log.exerciseID).name)
            }
            return HistoryRow(
                id: session.id, kind: .session, date: session.start, name: session.title, minutes: session.minutes,
                workSets: session.workSets.count, topSet: top, source: session.device, effort: nil,
                searchText: ([session.title] + names).joined(separator: " ").lowercased())
        }
        let activityRows = activities.map { log -> HistoryRow in
            let source: String =
                switch log.source {
                case .health(_, let name): "Health · \(name)"
                case .manual: "Logged by hand"
                case .declared: "Declared"
                }
            return HistoryRow(
                id: log.id, kind: .activity(log.type), date: log.start, name: log.type.label, minutes: log.minutes, workSets: 0, topSet: nil,
                source: source, effort: log.intensity, searchText: "\(log.type.label) \(log.note)".lowercased())
        }
        return (sessionRows + activityRows).sorted { $0.date > $1.date }
    }

    /// Whether every word of a search appears in the row's name or its exercises.
    public func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { searchText.contains($0) }
    }
}
