import Foundation
import Testing

@testable import SystemCore

/// Life modes are set in any app and honoured by all three, each keeping its own synced copy. These
/// check that a delete travels like an edit and that the editors agree on what can be saved.
@Suite("Life modes across apps")
struct LifeModeSharingTests {
    let start = Day(year: 2026, month: 3, day: 2)
    let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    func vacation(_ id: UUID = UUID(), updatedAt: Date, by app: AppID = .liftTrack) -> LifeModePeriod {
        LifeModePeriod(id: id, kind: .vacation, start: start, end: start.adding(days: 6), createdBy: app, updatedAt: updatedAt)
    }

    @Test func aDeleteBeatsAnOlderLiveCopyFromAnotherApp() {
        let id = UUID()
        let macroCopy = vacation(id, updatedAt: t0, by: .macroTrack)
        let deleted = macroCopy.deleted(at: t0.addingTimeInterval(60))
        // Whichever order the sources come in, the delete wins and is kept to pass on.
        for sources in [[[deleted], [macroCopy]], [[macroCopy], [deleted]]] {
            let merged = LifeModePeriod.merge(sources)
            #expect(merged == [deleted])
            #expect(merged.live.isEmpty)
        }
        #expect(deleted.isDeleted && deleted.updatedAt == deleted.deletedAt && !macroCopy.isDeleted)
    }

    @Test func aNewerEditBeatsAnOlderDelete() {
        let id = UUID()
        let deleted = vacation(id, updatedAt: t0).deleted(at: t0.addingTimeInterval(60))
        var edited = vacation(id, updatedAt: t0.addingTimeInterval(120), by: .knowledge)
        edited.end = start.adding(days: 9)
        #expect(LifeModePeriod.merge([[deleted], [edited]]) == [edited])
        #expect(LifeModePeriod.merge([[edited], [deleted]]).live == [edited])
    }

    @Test func tiesAreSettledTheSameWayEverywhere() {
        let id = UUID()
        let live = vacation(id, updatedAt: t0)
        // The same moment, once through the shared container's whole milliseconds: still a tie.
        var roundTripped = live
        roundTripped.updatedAt = Date(timeIntervalSince1970: (t0.timeIntervalSince1970 * 1000).rounded() / 1000 + 0.0002)
        roundTripped.end = start.adding(days: 3)
        #expect(LifeModePeriod.merge([[live], [roundTripped]]) == [live])
        // A delete made in the same millisecond as an edit wins.
        var tombstone = live
        tombstone.deletedAt = t0
        #expect(LifeModePeriod.merge([[live], [tombstone]]) == [tombstone])
        // The merged list is in a fixed order: by start, then id.
        let later = LifeModePeriod(kind: .illness(.aboveNeck), start: start.adding(days: 20), createdBy: .macroTrack, updatedAt: t0)
        let a = vacation(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, updatedAt: t0)
        let b = vacation(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, updatedAt: t0)
        #expect(LifeModePeriod.merge([[later, b], [a]]).map(\.id) == [a.id, b.id, later.id])
    }

    @Test func aCorruptTimestampDoesntTrapTheMerge() {
        let id = UUID()
        let corrupt = vacation(id, updatedAt: Date(timeIntervalSince1970: 1e300))
        #expect(LifeModePeriod.merge([[vacation(id, updatedAt: t0)], [corrupt]]) == [corrupt])
    }

    @Test func enginesIgnoreDeletedPeriods() {
        let trip = vacation(updatedAt: t0)
        let injury = LifeModePeriod(
            kind: .injury(Injury(parts: [InjuredPart(.knee)], severity: .moderate)), start: start, end: start.adding(days: 3),
            createdBy: .liftTrack, updatedAt: t0)
        let deleted = [trip.deleted(at: t0), injury.deleted(at: t0)]
        let during = LifeModes.effects(on: start.adding(days: 2), periods: deleted)
        #expect(during.trainingExpected && !during.disciplineExempt && during.active.isEmpty && during.injuries.isEmpty)
        // Nor does a deleted injury ramp lifts back afterwards.
        #expect(LifeModes.effects(on: start.adding(days: 6), periods: deleted).injuryRamps.isEmpty)
        #expect(LifeModes.exemptDays(in: DayRange(start, start.adding(days: 6)), periods: deleted).isEmpty)
        #expect(LifeModes.effects(on: start.adding(days: 2), periods: [trip]).disciplineExempt)
    }

    @Test func editorsSaveOnlyWhatMakesSense() {
        var trip = vacation(updatedAt: t0)
        #expect(trip.isValid)
        trip.start = start.adding(days: 10)
        #expect(!trip.isValid)
        #expect(trip.normalized().isValid)
        #expect(trip.normalized().start == start.adding(days: 6) && trip.normalized().end == start.adding(days: 10))
        trip.end = nil
        #expect(!trip.isValid, "a vacation needs an end")
        #expect(trip.normalized() == trip)
        #expect(LifeModePeriod(kind: .illness(.systemic), start: start, createdBy: .macroTrack).isValid)
        #expect(!LifeModePeriod(kind: .crunch(CrunchDials()), start: start, createdBy: .knowledge).isValid)
        #expect(!LifeModePeriod(kind: .injury(Injury(parts: [], severity: .mild)), start: start, createdBy: .liftTrack).isValid)
        #expect(LifeModePeriod(kind: .injury(Injury(parts: [InjuredPart(.knee)], severity: .mild)), start: start, createdBy: .liftTrack).isValid)
        // A one-day period is fine.
        #expect(LifeModePeriod(kind: .vacation, start: start, end: start, createdBy: .liftTrack).isValid)
    }

    @Test func editorsSaveTheEndTheyShow() {
        // A trip or a crunch with no end yet gets a week, open-ended or not.
        let crunch = LifeModePeriod(kind: .crunch(CrunchDials()), start: start, createdBy: .knowledge)
        #expect(crunch.editorEnd == start.adding(days: 6))
        for openEnded in [false, true] {
            let saved = crunch.edited(openEnded: openEnded)
            #expect(saved.end == start.adding(days: 6) && saved.isValid, "open-ended: \(openEnded)")
        }
        // An injury or illness is open-ended only when asked; otherwise it keeps the end shown.
        let illness = LifeModePeriod(kind: .illness(.aboveNeck), start: start, createdBy: .macroTrack)
        #expect(illness.edited(openEnded: true).end == nil && illness.edited(openEnded: true).isValid)
        #expect(illness.edited(openEnded: false).end == start.adding(days: 6))
        var dated = illness
        dated.end = start.adding(days: 2)
        #expect(dated.edited(openEnded: false).end == start.adding(days: 2))
        #expect(dated.edited(openEnded: true).end == nil)
        // An end before the start is saved as the start.
        dated.end = start.adding(days: -3)
        #expect(dated.editorEnd == start && dated.edited(openEnded: false).end == start)
    }

    @Test func editorsKeepTheEndOnOrAfterTheStart() {
        var trip = vacation(updatedAt: t0)
        // Moving the start past the end takes the end with it; moving it earlier leaves the end.
        trip.moveStart(to: start.adding(days: 10))
        #expect(trip.start == start.adding(days: 10) && trip.end == start.adding(days: 10) && trip.isValid)
        trip.moveStart(to: start.adding(days: 8))
        #expect(trip.end == start.adding(days: 10))
        // The end can't go before the start.
        trip.moveEnd(to: start)
        #expect(trip.end == start.adding(days: 8))
        trip.moveEnd(to: start.adding(days: 12))
        #expect(trip.end == start.adding(days: 12))
        // An open-ended injury stays open-ended when its start moves.
        var injury = LifeModePeriod(kind: .injury(Injury(parts: [InjuredPart(.knee)], severity: .mild)), start: start, createdBy: .liftTrack)
        injury.moveStart(to: start.adding(days: 3))
        #expect(injury.start == start.adding(days: 3) && injury.end == nil)
    }

    @Test func periodsWrittenBeforeDeletesWereSharedStillDecode() throws {
        // A period as every app wrote it at schema 1, with no deletedAt.
        let json = #"""
            [{"createdBy":"macroTrack","end":"2026-03-08","id":"6F1C2A8E-4B0D-4C35-9E57-2F8A1D3B7C90","kind":{"vacation":{}},"start":"2026-03-02",
              "updatedAt":1780000000000},
             {"createdBy":"liftTrack","id":"0B7D9E21-5A44-4F0E-8C1B-93E2A6F4D518",
              "kind":{"injury":{"_0":{"allowed":[],"note":"","parts":[{"joint":"knee","side":"left"}],"removed":[],"severity":"moderate"}}},
              "start":"2026-03-02","updatedAt":1780000000000}]
            """#
        let periods = try ContractJSON.decoder.decode([LifeModePeriod].self, from: Data(json.utf8))
        #expect(periods.count == 2 && periods.allSatisfy { !$0.isDeleted })
        #expect(periods[0].kind == .vacation && periods[0].end == Day(year: 2026, month: 3, day: 8) && periods[0].createdBy == .macroTrack)
        #expect(periods[1].end == nil && periods[1].kind == .injury(Injury(parts: [InjuredPart(.knee, side: .left)], severity: .moderate)))
        #expect(periods[0].updatedAt == t0)
        // A live period still writes the old shape, and a tombstone round-trips.
        let live = try ContractJSON.encoder.encode(periods[0])
        #expect(String(decoding: live, as: UTF8.self).contains("deletedAt") == false)
        let tombstone = periods[0].deleted(at: t0.addingTimeInterval(1))
        #expect(try ContractJSON.decoder.decode(LifeModePeriod.self, from: ContractJSON.encoder.encode(tombstone)) == tombstone)
        #expect(LifeModePeriod.schemaVersion == 2)
    }
}
