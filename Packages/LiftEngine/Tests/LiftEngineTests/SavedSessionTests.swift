import ExerciseLibrary
import Foundation
import SystemCore
import Testing

@testable import LiftEngine

/// JSON the way the apps save it (SystemJSON on the phone, WatchJSON on the Watch): dates as whole
/// milliseconds since 1970, keys sorted.
enum SavedJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSince1970: try container.decode(Double.self) / 1000)
        }
        return decoder
    }

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func object(_ data: Data) throws -> Any { try JSONSerialization.jsonObject(with: data) }

    /// Every key and value in `saved` is in `reread` too: what was saved comes back. Fields added
    /// since may appear in `reread` alone.
    static func missing(from reread: Any, saved: Any, at path: String = "") -> [String] {
        switch (saved, reread) {
        case (let saved as [String: Any], let reread as [String: Any]):
            return saved.keys.sorted().flatMap { key in
                guard let value = reread[key] else { return ["\(path).\(key) is gone"] }
                return missing(from: value, saved: saved[key] as Any, at: "\(path).\(key)")
            }
        case (let saved as [Any], let reread as [Any]):
            guard saved.count == reread.count else { return ["\(path) has \(reread.count) entries, not \(saved.count)"] }
            return zip(saved, reread).enumerated().flatMap { index, pair in missing(from: pair.1, saved: pair.0, at: "\(path)[\(index)]") }
        case (let saved as NSObject, let reread as NSObject):
            return saved == reread ? [] : ["\(path) is \(reread), not \(saved)"]
        default:
            return ["\(path) changed shape"]
        }
    }
}

/// A session in progress and two finished ones, as the October 2026 version saves them. Frozen as
/// JSON in Fixtures (written once from these with `SavedJSON.encoder()`, never regenerated), so a
/// change that stops them decoding fails here rather than stranding someone's session mid-workout
/// or the Watch's outbox. A shape that changes gets a fixture of its own; the old ones stay.
enum SavedFixture {
    /// Monday 19 October 2026, 17:00 UTC.
    static let start = Date(timeIntervalSince1970: 1_792_429_200)
    static let day = Day(year: 2026, month: 10, day: 19)

    static func id(_ n: Int) -> UUID {
        let tail = String(n)
        return UUID(uuidString: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - tail.count) + tail) ?? UUID()
    }

    static func at(minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    static func work(_ load: Double?, _ reps: Int, rir: Double = 2, seconds: Int? = nil) -> SetPrescription {
        SetPrescription(kind: .working, loadKg: load, targetReps: reps, targetRIR: rir, seconds: seconds)
    }

    static var plan: SessionPlan {
        let none = RestPlan(target: 0, minimum: 0, heartRateGuided: false)
        let items = [
            PlannedItem(
                id: id(101), slotID: id(201), block: .main, exerciseID: "barbell-bench-press", role: .main,
                sets: [
                    SetPrescription(kind: .warmup, loadKg: 40, targetReps: 8, targetRIR: 5), work(80, 8), work(80, 8),
                    SetPrescription(kind: .repOut, loadKg: 80, targetReps: 8, targetRIR: 0, stopAtFormBreakdown: true),
                ],
                repRange: RepRange(6, 10), rest: RestPlan(target: 180, minimum: 120, heartRateGuided: false),
                reason: "Pressing comes first this block.", note: "Up from last week's 77.5 kg.", mode: .load),
            PlannedItem(
                id: id(102), slotID: id(202), block: .accessory, exerciseID: "chest-supported-db-row", role: .accessory,
                sets: [work(26, 10), work(26, 10), work(26, 10)], repRange: RepRange(8, 12),
                rest: RestPlan(target: 90, minimum: 0, heartRateGuided: true), supersetGroup: 1, restFiller: "couch-stretch",
                mode: .reps, substitutedFor: "barbell-row"),
            PlannedItem(
                id: id(103), slotID: id(203), block: .accessory, exerciseID: "cable-fly", role: .accessory,
                sets: [work(15, 12), work(15, 12), work(15, 12)], repRange: RepRange(10, 15),
                rest: RestPlan(target: 90, minimum: 0, heartRateGuided: true), supersetGroup: 1, mode: .reps),
            PlannedItem(
                id: id(104), slotID: id(204), block: .limiter, exerciseID: "couch-stretch", role: .mobility,
                sets: [work(nil, 1, rir: 5, seconds: 60), work(nil, 1, rir: 5, seconds: 60)], repRange: RepRange(1, 1), rest: none,
                seconds: 60, reason: "Hips are today's limiter."),
            PlannedItem(
                id: id(105), slotID: id(205), block: .conditioning, exerciseID: "bike-30-30-intervals", role: .conditioning,
                sets: [work(nil, 1, rir: 3, seconds: 900)], repRange: RepRange(1, 1), rest: none, seconds: 900,
                conditioning: ConditioningPlan(minutes: 15, zones: 2...4, style: .intervals, workSeconds: 30, restSeconds: 30)),
            PlannedItem(
                id: id(106), slotID: nil, block: .recovery, exerciseID: "sauna", role: .recovery, sets: [work(nil, 1, rir: 5, seconds: 720)],
                repRange: RepRange(1, 1), rest: none, seconds: 720, reason: "Optional."),
        ]
        return SessionPlan(
            id: id(1), day: day, title: "Upper A", mesocycleID: id(2), dayID: id(3), week: 1, deload: false, checkIn: false,
            assessment: false, minimumEffectiveDose: false, items: items, notes: ["About 50 minutes today, under your 60."],
            quests: [
                Quest(
                    id: "lift-2026-10-19-conditioning", title: "Zone 2 this evening",
                    detail: "It didn't fit in today's session.", stat: .endurance, source: .liftTrack, minutes: 20,
                    day: day, timeOfDay: .evening, priority: 1)
            ])
    }

    /// Partway through: the bench's first work set rated easy and the rest bumped, the superset
    /// under way with its 20-second changeover running, the bike and the stretch done.
    static var liveSession: LiveSession {
        var live = LiveSession(plan: plan, device: "Watch", now: start)
        live.id = id(4)
        for i in live.items.indices {
            for s in live.items[i].sets.indices { live.items[i].sets[s].id = id(1_000 + i * 10 + s) }
        }
        live.items[0].sets[0].logged = LoggedSet(
            id: id(301), exerciseID: "barbell-bench-press", date: at(minutes: 4), kind: .warmup, loadKg: 40,
            reps: 8, targetReps: 8, bodyweightKg: 82)
        live.items[0].sets[1].logged = LoggedSet(
            id: id(302), exerciseID: "barbell-bench-press", date: at(minutes: 8), loadKg: 80, reps: 8,
            targetReps: 8, rating: .green, bodyweightKg: 82, restBeforeSeconds: 240, heartRatePeak: 151)
        live.items[0].sets[2].prescription.loadKg = 82.5
        live.items[0].sets[2].note = "Easy: up to 82.5 kg."
        live.items[0].sets[3].prescription.loadKg = 82.5
        live.items[0].verified = true
        live.items[1].sets[0].logged = LoggedSet(
            id: id(303), exerciseID: "chest-supported-db-row", date: at(minutes: 15), loadKg: 26, reps: 10,
            targetReps: 10, rating: .orange, restBeforeSeconds: 200)
        live.items[2].sets[0].logged = LoggedSet(
            id: id(304), exerciseID: "cable-fly", date: at(minutes: 16), loadKg: 15, reps: 12,
            targetReps: 12, rating: .orange, restBeforeSeconds: 20)
        live.items[2].sets[2].skipped = true
        for s in 0..<2 {
            live.items[3].sets[s].logged = LoggedSet(
                id: id(305 + s), exerciseID: "couch-stretch", date: at(minutes: 1 + Double(s)), loadKg: 0,
                reps: 1, seconds: 60)
        }
        live.mobilityDone = ["couch-stretch"]
        live.items[4].conditioning = ConditioningLog(
            exerciseID: "bike-30-30-intervals", minutes: 15, averageHeartRate: 142,
            zoneMinutes: [2: 6.5, 3: 5, 4: 3.5], zone: 2)
        live.items[4].sets[0].logged = LoggedSet(
            id: id(307), exerciseID: "bike-30-30-intervals", date: at(minutes: 40), loadKg: 0, reps: 1,
            seconds: 900)
        live.items[5].heat = HeatLog(
            exerciseID: "sauna", date: at(minutes: 70), minutes: 12, temperatureC: 85, rating: .orange,
            averageHeartRate: 104, peakHeartRate: 118)
        live.rest = RestState(
            started: at(minutes: 16), plan: RestPlan(target: 20, minimum: 0, heartRateGuided: false), itemID: id(103),
            endsAt: at(minutes: 16).addingTimeInterval(20), preSetHeartRate: 96, filler: "couch-stretch")
        live.message = "Easy: up to 82.5 kg."
        live.lastAdjustment = .bump
        live.heartRateSamples = [.init(date: at(minutes: 8), bpm: 151), .init(date: at(minutes: 9), bpm: 118)]
        live.updatedAt = at(minutes: 16)
        return live
    }

    /// One session with everything a record keeps, and a quick one from before heat and the time
    /// zone were kept.
    static var records: [SessionRecord] {
        let bench = (0..<3).map { n in
            LoggedSet(
                id: id(311 + n), exerciseID: "barbell-bench-press", date: at(minutes: 8 + 4 * Double(n)), kind: n == 2 ? .repOut : .working,
                loadKg: 82.5, reps: n == 2 ? 11 : 8, targetReps: 8, rating: n == 2 ? nil : .orange, bodyweightKg: 82,
                stoppedAtFormBreakdown: n == 2, restBeforeSeconds: 180, heartRatePeak: 150, heartRateDrop60: 28)
        }
        let row = LoggedSet(
            id: id(314), exerciseID: "chest-supported-db-row", date: at(minutes: 22), loadKg: 26, reps: 10, targetReps: 10,
            rating: .green)
        let full = SessionRecord(
            id: id(5), start: start, end: at(minutes: 62), title: "Upper A", mesocycleID: id(2), dayID: id(3), planned: true, deload: false,
            exercises: [
                ExerciseLog(id: id(401), slotID: id(201), exerciseID: "barbell-bench-press", sets: bench),
                ExerciseLog(id: id(402), slotID: id(202), exerciseID: "chest-supported-db-row", sets: [row], substitutedFor: "barbell-row"),
            ],
            conditioning: [
                ConditioningLog(
                    exerciseID: "bike-30-30-intervals", minutes: 15, averageHeartRate: 142,
                    zoneMinutes: [2: 6.5, 3: 5, 4: 3.5], zone: 2)
            ],
            mobility: ["couch-stretch"], feedback: SessionFeedback(soreness: 2, jointPain: [.shoulder], energy: 4), device: "Watch",
            averageHeartRate: 121.5,
            heat: [
                HeatLog(
                    exerciseID: "sauna", date: at(minutes: 75), minutes: 12, temperatureC: 85, rating: .orange, averageHeartRate: 104,
                    peakHeartRate: 118)
            ],
            timeZoneID: "Europe/Oslo", updatedAt: at(minutes: 62))
        let earlier = start.addingTimeInterval(-3 * 86_400)
        let curl = LoggedSet(id: id(315), exerciseID: "db-curl", date: earlier.addingTimeInterval(600), loadKg: 14, reps: 12)
        let quick = SessionRecord(
            id: id(6), start: earlier, end: earlier.addingTimeInterval(1_500), title: "Quick lift", planned: false,
            exercises: [ExerciseLog(id: id(403), exerciseID: "db-curl", sets: [curl])],
            device: "iPhone", timeZoneID: nil, updatedAt: earlier.addingTimeInterval(1_500))
        return [full, quick]
    }
}

@Suite("Saved sessions")
struct SavedSessionTests {
    let decoder = SavedJSON.decoder()

    func environment() -> SessionEnvironment {
        SessionEnvironment(
            catalog: Fixture.catalog, gym: Gym.preset(.fullGym, unit: .kg), trust: TrustState(experience: .intermediate),
            phase: NutritionPhase.assumedMaintenance.effects, bodyweightKg: 82, history: [:], enduranceScore: nil,
            heartRateGuidedRest: true)
    }

    @Test("a session in progress, as this version saved it, opens and carries on")
    func liveSessionFixture() throws {
        let data = try SavedJSON.fixture("live-session.2026-10.json")
        var live = try decoder.decode(LiveSession.self, from: data)
        #expect(live.id == SavedFixture.id(4) && live.device == "Watch")
        #expect(
            live.items.map(\.exerciseID) == [
                "barbell-bench-press", "chest-supported-db-row", "cable-fly", "couch-stretch",
                "bike-30-30-intervals", "sauna",
            ])
        #expect(live.items[0].sets[1].logged?.rating == .green && live.items[0].verified)
        #expect(live.items[0].sets[2].prescription.loadKg == 82.5 && live.items[0].sets[2].planned?.loadKg == 80)
        #expect(live.items[1].plan.supersetGroup == 1 && live.items[1].plan.substitutedFor == "barbell-row")
        #expect(live.items[2].sets[2].skipped)
        #expect(live.items[4].conditioning?.zoneMinutes == [2: 6.5, 3: 5, 4: 3.5])
        #expect(live.items[5].heat?.temperatureC == 85)
        #expect(live.rest?.itemID == SavedFixture.id(103) && live.rest?.endsAt == SavedFixture.at(minutes: 16).addingTimeInterval(20))
        #expect(live.mobilityDone == ["couch-stretch"] && live.heartRateSamples.count == 2 && live.lastAdjustment == .bump)
        #expect(live.plan.quests.map(\.stat) == [.endurance] && live.plan.week == 1)
        // Everything saved comes back when it's saved again.
        let reread = try SavedJSON.object(SavedJSON.encoder().encode(live))
        #expect(SavedJSON.missing(from: reread, saved: try SavedJSON.object(data)) == [])

        // And the session goes on from where it was.
        let next = try #require(live.current)
        #expect(next.item == 0 && next.set == 2)
        live.log(
            item: next.item, set: next.set, reps: 8, loadKg: 82.5, rating: .orange, environment: environment(),
            now: SavedFixture.at(minutes: 20))
        let record = live.record(feedback: nil, now: SavedFixture.at(minutes: 60), timeZone: .gmt)
        #expect(record.exercises.first { $0.exerciseID == "barbell-bench-press" }?.sets.count == 3)
        #expect(record.conditioning.count == 1 && record.heat?.count == 1 && record.hasContent)
    }

    @Test("finished sessions, as this version saved them, still read")
    func sessionRecordsFixture() throws {
        let data = try SavedJSON.fixture("session-records.2026-10.json")
        let records = try decoder.decode([SessionRecord].self, from: data)
        #expect(records.map(\.id) == [SavedFixture.id(5), SavedFixture.id(6)])
        let full = records[0]
        #expect(full.exercises.map(\.exerciseID) == ["barbell-bench-press", "chest-supported-db-row"])
        #expect(full.exercises.map(\.substitutedFor) == [nil, "barbell-row"])
        #expect(full.workSets.count == 4 && full.sets.last { $0.kind == .repOut }?.stoppedAtFormBreakdown == true)
        #expect(full.conditioning.first?.zoneMinutes == [2: 6.5, 3: 5, 4: 3.5])
        #expect(full.heat?.first?.temperatureC == 85 && full.timeZoneID == "Europe/Oslo" && full.day == SavedFixture.day)
        #expect(full.feedback?.jointPain == [.shoulder] && full.mobility == ["couch-stretch"] && full.device == "Watch")
        let quick = records[1]
        #expect(!quick.planned && quick.heat == nil && quick.timeZoneID == nil && quick.feedback == nil)
        #expect(records.allSatisfy { $0.hasContent })
        let reread = try SavedJSON.object(SavedJSON.encoder().encode(records))
        #expect(SavedJSON.missing(from: reread, saved: try SavedJSON.object(data)) == [])
    }

    @Test("what's saved now reads back the same")
    func roundTrip() throws {
        let live = SavedFixture.liveSession
        #expect(try decoder.decode(LiveSession.self, from: SavedJSON.encoder().encode(live)) == live)
        let records = SavedFixture.records
        #expect(try decoder.decode([SessionRecord].self, from: SavedJSON.encoder().encode(records)) == records)
    }

    func without(_ keys: Set<String>, in object: Any?) -> [String: Any] {
        (object as? [String: Any] ?? [:]).filter { !keys.contains($0.key) }
    }

    @Test("a session saved before fields were added still opens, with each one's default")
    func olderShape() throws {
        var session = without([], in: try SavedJSON.object(SavedJSON.encoder().encode(SavedFixture.liveSession)))
        let plannedKeys: Set = [
            "slotID", "sets", "seconds", "conditioning", "supersetGroup", "restFiller", "reason", "note", "mode",
            "substitutedFor",
        ]
        var plan = without(
            [
                "title", "mesocycleID", "dayID", "week", "deload", "checkIn", "assessment", "minimumEffectiveDose", "notes",
                "quests",
            ], in: session["plan"])
        plan["items"] = (plan["items"] as? [Any] ?? []).map { without(plannedKeys, in: $0) }
        session["plan"] = plan
        session["items"] = (session["items"] as? [Any] ?? []).map { entry -> [String: Any] in
            var item = without(["exerciseID", "skipped", "verified", "heat"], in: entry)
            item["plan"] = without(plannedKeys, in: item["plan"])
            item["sets"] = (item["sets"] as? [Any] ?? []).map { without(["skipped", "note", "planned"], in: $0) }
            if item["conditioning"] != nil { item["conditioning"] = without(["zoneMinutes"], in: item["conditioning"]) }
            return item
        }
        session = without(["device", "mobilityDone", "heartRateSamples", "updatedAt", "message", "lastAdjustment"], in: session)
        // A rest timer from some other shape is dropped rather than losing the session.
        session["rest"] = ["started": "half past six"]

        let old = try decoder.decode(LiveSession.self, from: JSONSerialization.data(withJSONObject: session))
        #expect(old.id == SavedFixture.id(4) && old.startedAt == SavedFixture.start && old.updatedAt == old.startedAt)
        #expect(old.device == "iPhone" && old.mobilityDone.isEmpty && old.heartRateSamples.isEmpty && old.rest == nil)
        #expect(old.message == nil && old.lastAdjustment == nil)
        #expect(old.plan.title == "" && !old.plan.deload && old.plan.notes.isEmpty && old.plan.quests.isEmpty && old.plan.week == nil)
        #expect(old.items.map(\.exerciseID) == SavedFixture.plan.items.map(\.exerciseID), "each item's exercise comes from its plan")
        #expect(old.items.allSatisfy { !$0.skipped && !$0.verified && $0.heat == nil && $0.plan.sets.isEmpty && $0.plan.mode == nil })
        #expect(old.items.flatMap(\.sets).allSatisfy { !$0.skipped && $0.note == nil && $0.planned == nil })
        #expect(old.items[0].sets[1].logged?.loadKg == 80, "what was logged is kept")
        #expect(old.items[4].conditioning?.minutes == 15 && old.items[4].conditioning?.zoneMinutes == [:])

        // Saved without its items, it starts again from the plan.
        session.removeValue(forKey: "items")
        let fresh = try decoder.decode(LiveSession.self, from: JSONSerialization.data(withJSONObject: session))
        #expect(fresh.items.map(\.id) == SavedFixture.plan.items.map(\.id))
        #expect(fresh.items.allSatisfy { $0.sets.isEmpty }, "the plan was saved without its sets too")
    }
}
