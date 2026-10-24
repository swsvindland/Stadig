import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import SystemStore
import Testing

@testable import LiftTrack

/// The session in progress survives the app being closed: live-session.json, restored at launch,
/// saved when it was left too long, and set aside when it can't be read.
@MainActor
@Suite("Session left open")
struct LiveSessionFileTests {
    private func written(_ app: TestApp) throws -> LiveSession {
        try SystemJSON.decoder().decode(LiveSession.self, from: Data(contentsOf: app.liveURL))
    }

    /// Compared as stored: the file keeps dates to the millisecond.
    private func same(_ a: LiveSession?, _ b: LiveSession?) throws -> Bool {
        try SystemJSON.encoder().encode(a) == SystemJSON.encoder().encode(b)
    }

    @Test("A session in progress is picked up again after a relaunch")
    func roundTrip() throws {
        let app = TestApp()
        let model = app.onboarded()
        model.start(try #require(model.plan()))
        model.logNext(3)
        let live = try #require(model.live)
        #expect(try same(written(app), live))

        let relaunched = app.model()
        #expect(try same(relaunched.live, live))
        #expect(relaunched.finished == nil)
        #expect(relaunched.sessions.isEmpty)
    }

    @Test("Heart-rate readings alone wait half a minute before the file is written again")
    func heartRateThrottle() throws {
        let app = TestApp()
        let model = app.onboarded()
        model.start(try #require(model.plan()))
        model.logNext(1)
        let before = try written(app)
        let reading = try #require(MirrorMessage.heartRate(bpm: 120, date: Date()).encoded())
        model.fromWatch([reading])
        #expect(model.live?.heartRateSamples.count == 1)
        #expect(model.heartRate == 120)
        // Not yet on disk: samples come every few seconds.
        #expect(try written(app).heartRateSamples.isEmpty)
        #expect(try written(app) == before)
        // The next real change writes everything, the reading included.
        model.logNext(1)
        #expect(try written(app).heartRateSamples.count == 1)
    }

    /// A session left with work logged in it, its last change `hours` ago.
    private func leaveSession(in app: TestApp, hoursAgo hours: Double, logging count: Int) throws -> LiveSession {
        let model = app.onboarded()
        let then = Date().addingTimeInterval(-hours * 3600)
        var live = LiveSession(plan: try #require(model.plan()), device: "iPhone", now: then.addingTimeInterval(-600))
        let environment = try #require(model.environment)
        for _ in 0..<count {
            guard let (i, s) = live.current else { break }
            let prescription = live.items[i].sets[s].prescription
            live.log(
                item: i, set: s, reps: prescription.targetReps, loadKg: prescription.loadKg ?? 20, rating: .orange, seconds: prescription.seconds,
                environment: environment, now: then)
        }
        try FileManager.default.createDirectory(at: app.folder, withIntermediateDirectories: true)
        try SystemJSON.encoder().encode(live).write(to: app.liveURL)
        return live
    }

    @Test("A session left more than six hours is saved as it stood and shown as finished")
    func staleSessionIsSaved() throws {
        let app = TestApp()
        let left = try leaveSession(in: app, hoursAgo: 7, logging: 8)
        let model = app.model()
        #expect(model.live == nil)
        let finished = try #require(model.finished)
        #expect(finished.id == left.id)
        #expect(abs(finished.end.timeIntervalSince(left.updatedAt)) < 1)
        #expect(model.sessions.map(\.id) == [left.id])
        #expect(!FileManager.default.fileExists(atPath: app.liveURL.path(percentEncoded: false)))
    }

    @Test("A session left more than six hours with nothing logged is dropped")
    func staleEmptySessionIsDropped() throws {
        let app = TestApp()
        _ = try leaveSession(in: app, hoursAgo: 7, logging: 0)
        let model = app.model()
        #expect(model.live == nil)
        #expect(model.finished == nil)
        #expect(model.sessions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: app.liveURL.path(percentEncoded: false)))
    }

    @Test("A session left a few hours is still open")
    func recentSessionIsRestored() throws {
        let app = TestApp()
        let left = try leaveSession(in: app, hoursAgo: 2, logging: 3)
        let model = app.model()
        #expect(model.live?.id == left.id)
        #expect(model.sessions.isEmpty)
    }

    @Test("A file that can't be read is set aside, not deleted or written over")
    func unreadableFileIsSetAside() throws {
        let app = TestApp()
        try FileManager.default.createDirectory(at: app.folder, withIntermediateDirectories: true)
        let garbage = Data("{\"not\": \"a session\"}".utf8)
        try garbage.write(to: app.liveURL)
        let model = app.model()
        #expect(model.live == nil)
        let aside = app.folder.appending(path: "live-session.unreadable.json")
        #expect(try Data(contentsOf: aside) == garbage)
        #expect(!FileManager.default.fileExists(atPath: app.liveURL.path(percentEncoded: false)))
    }
}
