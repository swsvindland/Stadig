import Foundation
import Testing

@testable import SystemCore

/// The JSON settings of SystemStore's `SystemJSON`, which writes everything shared and synced:
/// dates as whole milliseconds since 1970, keys sorted.
enum ContractJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            Date(timeIntervalSince1970: try decoder.singleValueContainer().decode(Double.self) / 1000)
        }
        return decoder
    }
}

/// The apps ship on their own schedules, so what one writes the others must still read. Each
/// payload below is in the shape the apps write today: if a change stops it decoding, it needs a
/// schema version bump and a migration (or an optional field) instead.
@Suite("Shared contracts")
struct ContractTests {
    let at = Date(timeIntervalSince1970: 1_780_000_000)

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ContractJSON.decoder.decode(type, from: Data(json.utf8))
    }

    func roundTrips<T: Codable & Equatable>(_ value: T) throws -> Bool {
        try ContractJSON.decoder.decode(T.self, from: ContractJSON.encoder.encode(value)) == value
    }

    @Test func days() throws {
        #expect(try decode([Day].self, #"["2026-03-02","1969-12-31"]"#) == [Day(year: 2026, month: 3, day: 2), Day(ordinal: -1)])
        #expect(
            try decode(DayRange.self, #"{"end":"2026-03-08","start":"2026-03-02"}"#)
                == DayRange(
                    Day(year: 2026, month: 3, day: 2),
                    Day(year: 2026, month: 3, day: 8)))
        #expect(
            String(decoding: try ContractJSON.encoder.encode(DayRange(Day(ordinal: 0), Day(ordinal: 1))), as: UTF8.self)
                == #"{"end":"1970-01-02","start":"1970-01-01"}"#)
    }

    @Test func loggedSets() throws {
        let set = try decode(
            LoggedSet.self,
            #"""
            {"bodyweightKg":80,"date":1780000000000,"exerciseID":"pull-up","id":"5C0E3A77-1D2B-4E8F-9A6C-7B1D2E3F4A5B","kind":"repOut",
             "loadKg":10,"rating":"orange","reps":8,"stoppedAtFormBreakdown":false,"targetReps":8}
            """#)
        #expect(set.kind == .repOut && set.loadKg == 10 && set.reps == 8 && set.rating == .orange && set.bodyweightKg == 80 && set.date == at)
        #expect(set.restBeforeSeconds == nil && set.seconds == nil)
        #expect(try roundTrips(set))
    }

    @Test func trainingBlocks() throws {
        let block = try decode(
            TrainingBlock.self,
            #"""
            {"deloadReason":"Your vacation lands near the planned deload, so it becomes the deload.","deloadStart":"2026-04-01",
             "deloadWeeks":1,"endOverride":"2026-04-09","id":"0F4E8C1A-2B3D-4E5F-8091-A2B3C4D5E6F7","kind":"standard","loadingWeeks":5,
             "start":"2026-03-02"}
            """#)
        #expect(block.kind == .standard && block.loadingWeeks == 5 && block.effectiveDeloadStart == Day(year: 2026, month: 4, day: 1))
        #expect(block.end == Day(year: 2026, month: 4, day: 9))
        let plain = try decode(
            TrainingBlock.self,
            #"""
            {"deloadWeeks":1,"id":"0F4E8C1A-2B3D-4E5F-8091-A2B3C4D5E6F8","kind":"assessment","loadingWeeks":4,"start":"2026-03-02"}
            """#)
        #expect(plain.deloadStart == nil && plain.end == Day(year: 2026, month: 4, day: 5))
        #expect(try roundTrips(block))
    }

    @Test func systemCalendar() throws {
        let calendar = try decode(
            SystemCalendar.self,
            #"""
            {"checkIns":["2026-04-05"],"currentBlock":{"end":"2026-04-05","start":"2026-03-02"},
             "deloads":[{"end":"2026-04-05","start":"2026-03-30"}],"publishedBy":"liftTrack","updated":1780000000000}
            """#)
        #expect(calendar.isDeload(Day(year: 2026, month: 4, day: 1)) && !calendar.isDeload(Day(year: 2026, month: 3, day: 29)))
        #expect(calendar.publishedBy == .liftTrack && calendar.updated == at)
        #expect(try roundTrips(calendar))
    }

    @Test func sharedProfile() throws {
        let profile = try decode(
            SharedProfile.self,
            #"""
            {"birthYear":1990,"createdAt":1780000000000,"createdBy":"macroTrack","equipment":"homeGym","experience":"intermediate",
             "goals":["leaner","stronger"],"heightCm":180,"recurring":[],"schedule":{"daysPerWeek":4,"minutesPerSession":60,"preferredDays":[1,4]},
             "sex":"female","units":{"length":"cm","weight":"kg"},"updatedAt":1780000000000}
            """#)
        #expect(
            profile.goals == [.leaner, .stronger] && profile.schedule.daysPerWeek == 4 && profile.schedule.preferredDays == [.monday, .thursday])
        #expect(profile.sex == .female && profile.birthYear == 1990 && profile.units == UnitPreference(weight: .kg, length: .cm))
        #expect(profile.age(on: Day(year: 2026, month: 10, day: 18)) == 36)
        #expect(SharedProfile.schemaVersion == 1)
        #expect(try roundTrips(profile))
    }

    @Test func aBirthYearThatCantBeRightGivesNoAge() {
        let day = Day(year: 2026, month: 10, day: 18)
        #expect(SharedProfile.plausibleBirthYears(on: day) == 1926...2016)
        var profile = SharedProfile(createdBy: .liftTrack)
        #expect(profile.age(on: day) == nil)
        for (year, age) in [(1926, 100), (1990, 36), (2016, 10)] {
            profile.birthYear = year
            #expect(profile.age(on: day) == age, "\(year)")
        }
        // A typo, a cleared field stored as 0, a future year: the apps' default ages apply instead.
        for year in [0, 1925, 2017, 2027, 19_990, -5] {
            profile.birthYear = year
            #expect(profile.age(on: day) == nil, "\(year)")
        }
    }

    @Test func appSummaryWithEverythingFilledIn() throws {
        let day = Day(year: 2026, month: 3, day: 2)
        let summary = AppSummary(
            app: .liftTrack, updated: at,
            stats: [StatReading(stat: .strength, score: 61, label: "Intermediate", trend: .onPace, updated: at)],
            sessions: [
                SessionSummary(
                    id: UUID(), app: .liftTrack, kind: .activity, activity: .bjj, start: at, minutes: 60,
                    metrics: ["intensity": 7], fatigue: FatigueLoad(systemic: 4), statCredit: [.endurance: 0.5], planned: false)
            ],
            measurements: BodyMeasurements(day: day, weightKg: 80, neckCm: 39, waistCm: 84),
            mobility: [MobilityResult(test: .hip9090, day: day, value: 2)],
            stalls: [
                StallReport(
                    exerciseID: "barbell-bench-press", weeks: 4, bestE1RM: 120, since: day, reading: .programming,
                    suggestion: SetPrescription(kind: .working, loadKg: 102.5, targetReps: 5, targetRIR: 1), suggestedSets: 3)
            ],
            phaseUsed: NutritionPhase(kind: .cut, source: .macroTrack),
            steps: StepSummary(days: [StepDay(day: day, steps: 9000)], aim: 10_000, baseline: 8000))
        #expect(try roundTrips(summary))
        #expect(AppSummary.schemaVersion == 1)
    }
}
