import SystemCore
import Testing

@testable import ExerciseLibrary

/// The Library screen's filters: each narrows the catalog on its own tag, together they all apply,
/// and a muscle filter ranks the exercises that train it hardest first.
@Suite("Library filters")
struct ExerciseFilterTests {
    let library = ExerciseLibrary.bundled

    @Test func noFilterIsTheWholeLibraryInOrder() {
        let filter = ExerciseFilter()
        #expect(filter.isEmpty)
        #expect(filter.apply(to: library).map(\.id) == library.map(\.id))
    }

    @Test func eachFilterNarrowsOnItsOwnTag() {
        let strength = ExerciseFilter(kind: .strength).apply(to: library)
        #expect(!strength.isEmpty && strength.allSatisfy { $0.kind == .strength })
        #expect(strength.count < library.count)

        let squats = ExerciseFilter(pattern: .squat).apply(to: library)
        #expect(!squats.isEmpty && squats.allSatisfy { $0.pattern == .squat })

        let cables = ExerciseFilter(equipment: .cable).apply(to: library)
        #expect(!cables.isEmpty && cables.allSatisfy { $0.equipment == .cable })
    }

    @Test func aMuscleFilterRanksPrimaryMoversFirst() throws {
        let lats = ExerciseFilter(kind: .strength, muscle: .lats).apply(to: library)
        #expect(lats.allSatisfy { $0.weight(of: .lats) > 0 })
        #expect(lats.contains { $0.id == "lat-pulldown" })
        // Every primary mover before any exercise that only helps.
        let weights = lats.map { $0.weight(of: .lats) }
        #expect(weights == weights.sorted(by: >))
        let firstSecondary = try #require(lats.firstIndex { $0.weight(of: .lats) < 1 })
        #expect(lats[..<firstSecondary].allSatisfy { $0.primaryMuscles.contains(.lats) })
    }

    @Test func easyOnAJointKeepsOnlyLightOrNoStress() throws {
        let kneeFriendly = ExerciseFilter(kind: .strength, easyOn: .knee).apply(to: library)
        #expect(kneeFriendly.allSatisfy { ($0.stress(on: .knee) ?? .low) <= .low })
        let ids = Set(kneeFriendly.map(\.id))
        #expect(!ids.contains("barbell-back-squat"))
        #expect(!ids.contains("leg-extension"))
        #expect(ids.contains("barbell-bench-press"))
    }

    @Test func inMyGymFollowsAvailabilityAndItsOverrides() {
        var hotel = Availability(access: .hotelGym)
        let inHotel = Set(ExerciseFilter(availability: hotel).apply(to: library).map(\.id))
        #expect(!inHotel.contains("barbell-back-squat"))
        #expect(inHotel.contains("db-curl"))
        hotel.included = ["barbell-back-squat"]
        hotel.excluded = ["db-curl"]
        let overridden = Set(ExerciseFilter(availability: hotel).apply(to: library).map(\.id))
        #expect(overridden.contains("barbell-back-squat"))
        #expect(!overridden.contains("db-curl"))
    }

    @Test func safeWithInjuriesFollowsTheFilterAndTheOverrides() {
        var knee = Injury(parts: [InjuredPart(.knee)], severity: .severe)
        let safe = Set(ExerciseFilter(kind: .strength, injuries: [knee]).apply(to: library).map(\.id))
        #expect(!safe.contains("barbell-back-squat"))
        #expect(safe.contains("barbell-bench-press"))
        // Added back by hand, it's safe; taken out by hand, it isn't.
        knee.allowed = ["barbell-back-squat"]
        knee.removed = ["barbell-bench-press"]
        let overridden = Set(ExerciseFilter(kind: .strength, injuries: [knee]).apply(to: library).map(\.id))
        #expect(overridden.contains("barbell-back-squat"))
        #expect(!overridden.contains("barbell-bench-press"))
        // No injuries: nothing is ruled out.
        #expect(ExerciseFilter(kind: .strength, injuries: []).apply(to: library).count == ExerciseFilter(kind: .strength).apply(to: library).count)
    }

    @Test func filtersCombineAndASearchStillRanks() {
        let filter = ExerciseFilter(kind: .strength, equipment: .dumbbell, muscle: .sideDelts)
        let found = filter.apply(to: library)
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.equipment == .dumbbell && $0.weight(of: .sideDelts) > 0 })
        let searched = filter.apply(to: library, query: "lateral")
        #expect(searched.first?.id == "db-lateral-raise")
        #expect(searched.allSatisfy(filter.includes))
    }

    @Test func menusOfferOnlyWhatsThere() {
        let patterns = ExerciseFilter.patterns(in: library, kind: .strength)
        #expect(patterns.contains(.squat))
        #expect(!patterns.contains(.conditioning))
        #expect(patterns == MovementPattern.allCases.filter(patterns.contains))
        let equipment = ExerciseFilter.equipment(in: library, kind: .conditioning)
        #expect(equipment.allSatisfy { $0.isCardio || $0 == .bodyweight || $0 == .band || $0 == .kettlebell || $0 == .dumbbell })
        #expect(!equipment.contains(.smith))
    }
}
