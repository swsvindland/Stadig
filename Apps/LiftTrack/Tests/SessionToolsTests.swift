import ExerciseLibrary
import Foundation
import LiftEngine
import SystemCore
import Testing
import UIKit

@testable import LiftTrack

/// What the gym floor sees: where the logger's weight starts, what the Lock Screen says, and the
/// progress photos' size.
@MainActor
@Suite("Session tools")
struct SessionToolsTests {
    /// Today's first strength item, as the session has it, with its exercise.
    private func strengthItem(_ model: AppModel) throws -> (item: LiveItem, exercise: Exercise) {
        let live = LiveSession(plan: try #require(model.plan()), device: "iPhone")
        let item = try #require(
            live.items.first { $0.plan.isStrength && model.catalog.resolve($0.exerciseID).loadBasis == .external && $0.sets.count >= 2 })
        return (item, model.catalog.resolve(item.exerciseID))
    }

    @Test("The prescribed load comes first")
    func prescribedLoad() throws {
        let model = TestApp().onboarded()
        let (item, exercise) = try strengthItem(model)
        var set = item.sets[0]
        set.prescription.loadKg = 42.5
        #expect(model.startingLoad(for: set, at: 0, of: item, exercise: exercise) == 42.5)
    }

    @Test("Without one, the load this exercise was just done at, but not another exercise's from before a swap")
    func earlierSetInTheSession() throws {
        let model = TestApp().onboarded()
        var (item, exercise) = try strengthItem(model)
        item.sets[1].prescription.loadKg = nil
        item.sets[0].logged = LoggedSet(exerciseID: exercise.id, loadKg: 55, reps: 8, rating: .orange)
        #expect(model.startingLoad(for: item.sets[1], at: 1, of: item, exercise: exercise) == 55)

        item.sets[0].logged = LoggedSet(exerciseID: "some-other-exercise", loadKg: 155, reps: 8, rating: .orange)
        #expect(model.startingLoad(for: item.sets[1], at: 1, of: item, exercise: exercise) != 155)
    }

    @Test("With no history, a guess near what someone like this lifts, on a load the gym can make")
    func startingGuess() throws {
        let model = TestApp().onboarded()
        var (item, exercise) = try strengthItem(model)
        item.sets[0].prescription.loadKg = nil
        let load = model.startingLoad(for: item.sets[0], at: 0, of: item, exercise: exercise)
        #expect(load > 0)
        let increments = model.gymForToday.increments(for: exercise.equipment)
        #expect(increments.round(load, down: true) == load)
    }

    @Test("The Lock Screen names the exercise and the set, warm-ups apart from work sets")
    func liveActivityContent() throws {
        let model = TestApp().onboarded()
        var live = LiveSession(plan: try #require(model.plan()), device: "iPhone")
        let environment = try #require(model.environment)
        // Through to the first strength item.
        while let (i, s) = live.current, !live.items[i].plan.isStrength {
            live.log(item: i, set: s, reps: 1, loadKg: nil, rating: nil, seconds: 30, environment: environment)
            live.endRest()
        }
        let (i, s) = try #require(live.current)
        let item = live.items[i]
        let state = LiveActivityBridge.content(live, catalog: model.catalog, unit: .kg)
        #expect(state.exercise == model.catalog.resolve(item.exerciseID).name)
        let work = item.sets.filter { $0.prescription.kind != .warmup }.count
        if item.sets[s].prescription.kind == .warmup {
            #expect(state.detail.hasPrefix("Warm-up · "))
        } else {
            #expect(state.detail.hasPrefix("Set 1 of \(work) · "))
        }
        #expect(state.restEndsAt == nil)

        // A rest shows until its time is up.
        live.startRest(after: i, environment: environment)
        let rest = try #require(live.rest)
        #expect(LiveActivityBridge.content(live, catalog: model.catalog, unit: .kg).restEndsAt == rest.endsAt)
        #expect(LiveActivityBridge.content(live, catalog: model.catalog, unit: .kg, now: rest.endsAt.addingTimeInterval(1)).restEndsAt == nil)

        // Everything done or skipped: finish.
        for index in live.items.indices { live.skip(item: index) }
        let done = LiveActivityBridge.content(live, catalog: model.catalog, unit: .kg)
        #expect(done.exercise == "Finish session")
        #expect(done.detail.isEmpty)
    }

    // MARK: Photos

    private func jpeg(width: Int, height: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    @Test("A progress photo is kept at most 1400 pixels on its long side, whichever way up")
    func photoDownscale() async throws {
        for (width, height) in [(4000, 3000), (3000, 4000)] {
            let stored = try #require(await ProgressPhotos.jpeg(from: jpeg(width: width, height: height)))
            let image = try #require(UIImage(data: stored)?.cgImage)
            #expect(max(image.width, image.height) == 1400)
            #expect((image.width > image.height) == (width > height))
            // A 12 MP original stored at full size would be megabytes; this syncs light.
            #expect(stored.count < 400_000)
        }
    }

    @Test("A small photo isn't enlarged, and data that isn't an image is refused")
    func photoEdges() async throws {
        let small = try #require(await ProgressPhotos.jpeg(from: jpeg(width: 800, height: 600)))
        let image = try #require(UIImage(data: small)?.cgImage)
        #expect(image.width == 800)
        #expect(await ProgressPhotos.jpeg(from: Data("not an image".utf8)) == nil)
    }
}
