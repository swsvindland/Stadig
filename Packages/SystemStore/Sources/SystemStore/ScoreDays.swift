import CryptoKit
import Foundation
import SystemCore

/// One day's scores as an app keeps them in its own store, a record a day. The store syncs them to
/// the person's other devices one by one, so what two devices recorded adds up, where a whole file
/// carried between them would have the newer copy replace the other (a reinstall's first day over
/// a year of them). The history the shared container carries for the other app is drawn from
/// these (`RecordStore.recordScores`).
public struct ScoreDayRecord: StoredRecord, Equatable {
    public static let kind = "score-day"
    public static let schemaVersion = 1

    public var id: UUID
    public var day: Day
    /// The day's last reading of each stat, to a tenth.
    public var scores: [StatKind: Double]
    public var updatedAt: Date

    public init(day: Day, scores: [StatKind: Double], updatedAt: Date) {
        id = Self.id(for: day)
        self.day = day
        self.scores = scores
        self.updatedAt = updatedAt
    }

    /// Every device saves a day under the same id, so the day's newest reading wins everywhere.
    static func id(for day: Day) -> UUID {
        let digest = Array(SHA256.hash(data: Data("score-day:\(day.iso)".utf8)))
        var bytes = (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9],
            digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        )
        // A version 5 (name-based) UUID, RFC 4122 variant.
        bytes.6 = (bytes.6 & 0x0F) | 0x50
        bytes.8 = (bytes.8 & 0x3F) | 0x80
        return UUID(uuid: bytes)
    }
}

extension ScoreHistory {
    /// The history an app's day records make, thinned for `today`.
    public init(app: AppID, days: [ScoreDayRecord], today: Day) {
        var stats: [StatKind: [ScorePoint]] = [:]
        for record in days.sorted(by: { $0.day < $1.day }) {
            for (stat, score) in record.scores { stats[stat, default: []].append(ScorePoint(day: record.day, score: score)) }
        }
        self = ScoreHistory(app: app, stats: stats).thinned(today: today)
    }
}

extension RecordStore {
    /// The day's readings into the app's own store, as the day's record (saved only when they change
    /// it), and the history all its days make, thinned for the day, for the app to publish
    /// (`SharedKey.scores`) and measure from. The records themselves are all kept: a few dozen bytes
    /// a day.
    @discardableResult
    public func recordScores(_ readings: [StatReading], app: AppID, on day: Day, now: Date) -> ScoreHistory {
        let days = all(ScoreDayRecord.self)
        let history = ScoreHistory(app: app, days: days, today: day).recording(readings, on: day)
        let scores = history.scores(on: day)
        if !scores.isEmpty, days.first(where: { $0.day == day })?.scores != scores {
            save(ScoreDayRecord(day: day, scores: scores, updatedAt: now))
        }
        return history
    }
}
