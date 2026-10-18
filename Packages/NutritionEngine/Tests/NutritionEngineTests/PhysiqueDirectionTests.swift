import Foundation
import Testing
import SystemCore
@testable import NutritionEngine

/// The phase planner reading Lift Track's proportions: fat loss first where the waist holds a ratio
/// back, building where muscle does, and never a cut at the lean floor.
@Suite("Phases and proportions")
struct PhysiqueDirectionTests {
    let today = Day(year: 2026, month: 3, day: 2)

    // At 180 cm: lean under an 82.8 cm waist, moderate to 93.6, higher to 102.6, then high.
    func input(waist: Double, goals: [OutcomeGoal], physique: PhysiqueDirection? = nil) -> PlannerInput {
        PlannerInput(profile: profile(goals: goals), history: .none, today: today, weightKg: 82, weeklyChange: nil,
                     maintenance: MaintenanceEstimate(kcal: 2600, low: 2450, high: 2750, basis: .data, days: 21, formula: 2600),
                     waistCm: waist, physique: physique)
    }

    func direction(fatLoss: Double = 0, build: Double = 0, floor: Bool = false, room: FFMIBand? = nil) -> PhysiqueDirection {
        PhysiqueDirection(targets: .vTaper, fatLoss: fatLoss, build: build, buildRegions: build > 0 ? [.shoulders] : [], atLeanFloor: floor,
                          waistToHeight: nil, bodyFatPercent: floor ? 9 : nil, normalizedFFMI: room == nil ? nil : 21.4, ffmiBand: room,
                          fatLossReasons: fatLoss > 0 ? ["Shoulders to waist is 1.41; the target is 1.50 or more."] : [],
                          buildReasons: build > 0 ? ["Shoulders to waist is 1.40; the target is 1.50 or more."] : [])
    }

    @Test func anEmptyDirectionChangesNothing() {
        for (waist, goals) in [(80.0, [OutcomeGoal.biggerAndStronger]), (88, [.leaner]), (88, [.biggerAndStronger]), (98, [.healthier]), (106, [.leaner])] {
            let plain = PhasePlanner.recommend(input(waist: waist, goals: goals))
            let read = PhasePlanner.recommend(input(waist: waist, goals: goals, physique: direction()))
            #expect(plain.phases.map(\.kind) == read.phases.map(\.kind), "\(waist) \(goals)")
            #expect(plain.phases.map(\.ratePerWeek) == read.phases.map(\.ratePerWeek))
            #expect(plain.headline == read.headline)
        }
    }

    @Test func aWaistDrivenRatioCutsBeforeAnyGain() {
        // Moderate and wanting size: a lean bulk, until the waist is what holds the ratio back.
        #expect(PhasePlanner.recommend(input(waist: 88, goals: [.biggerAndStronger])).phases.first?.kind == .leanBulk)
        let plan = PhasePlanner.recommend(input(waist: 88, goals: [.biggerAndStronger], physique: direction(fatLoss: 0.5)))
        #expect(plan.phases.map(\.kind) == [.miniCut, .leanBulk])
        #expect(plan.reasons.contains { $0.contains("Shoulders to waist is 1.41") })
        #expect(plan.reasons.contains { $0 == "At a leaner waist it reaches its target, so fat loss comes before any gain." })
        // A weak signal doesn't move it.
        #expect(PhasePlanner.recommend(input(waist: 88, goals: [.biggerAndStronger], physique: direction(fatLoss: 0.2))).phases.first?.kind == .leanBulk)
    }

    @Test func proportionsOnlyCountForTheGoalsTheyServe() {
        let plan = PhasePlanner.recommend(input(waist: 88, goals: [.stronger, .fitter], physique: direction(fatLoss: 0.8)))
        #expect(plan.phases.first?.kind == .leanBulk)
        #expect(!plan.reasons.contains { $0.contains("Shoulders to waist") })
    }

    @Test func nothingCutsAtTheLeanFloor() {
        // A high waist says cut; 9% body fat says the waist isn't fat.
        let plan = PhasePlanner.recommend(input(waist: 106, goals: [.leaner], physique: direction(fatLoss: 0.9, floor: true)))
        #expect(plan.phases.allSatisfy { $0.kind.energy != .deficit })
        #expect(plan.reasons.contains { $0.contains("lean floor") })
        // A cut already running ends at the next review.
        let cut = PhasePlanner.recommend(input(waist: 106, goals: [.leaner]))
        #expect(cut.phases.first?.kind == .cut)
        var later = input(waist: 104, goals: [.leaner], physique: direction(floor: true))
        later.today = today.adding(weeks: 4)
        #expect(PhasePlanner.review(cut, input: later)?.phases.last?.kind == .dietBreak)
    }

    @Test func leanWithABuildGapBuilds() {
        // Lean and only wanting leaner: maintenance, unless the ratios need muscle, then a recomp.
        #expect(PhasePlanner.recommend(input(waist: 80, goals: [.leaner])).phases.first?.kind == .maintenance)
        let recomp = PhasePlanner.recommend(input(waist: 80, goals: [.leaner], physique: direction(build: 0.5, room: .lotsOfRoom)))
        #expect(recomp.phases.first?.kind == .recomp)
        #expect(recomp.reasons.contains { $0.contains("Shoulders to waist is 1.40") })
        #expect(recomp.reasons.contains { $0.contains("lots of room") })
        // Some room left: a smaller surplus.
        let slow = PhasePlanner.recommend(input(waist: 80, goals: [.biggerAndStronger], physique: direction(build: 0.5, room: .someRoom)))
        #expect(slow.phases.first?.kind == .leanBulk && slow.phases.first?.ratePerWeek == 0.0015)
        #expect(slow.headline.contains("0.15%"))
    }

    @Test func nearTheCeilingHoldsUnlessSizeIsTheGoal() {
        #expect(PhasePlanner.recommend(input(waist: 80, goals: [.healthier])).phases.first?.kind == .leanBulk)
        let held = PhasePlanner.recommend(input(waist: 80, goals: [.healthier], physique: direction(room: .nearCeiling)))
        #expect(held.phases.first?.kind == .maintenance)
        let recomp = PhasePlanner.recommend(input(waist: 80, goals: [.healthier], physique: direction(build: 0.6, room: .nearCeiling)))
        #expect(recomp.phases.first?.kind == .recomp)
        // Asking for size still gets a slow gain.
        let size = PhasePlanner.recommend(input(waist: 80, goals: [.biggerAndStronger], physique: direction(room: .nearCeiling)))
        #expect(size.phases.first?.kind == .leanBulk && size.phases.first?.ratePerWeek == 0.0015)
    }

    @Test func aBuildGapCantStartABulkAboveLean() {
        // Higher waist, wanting size, with a big build gap: still a mini-cut first.
        let plan = PhasePlanner.recommend(input(waist: 98, goals: [.biggerAndStronger], physique: direction(build: 0.9, room: .lotsOfRoom)))
        #expect(plan.phases.first?.kind.energy == .deficit)
        #expect(!plan.reasons.contains { $0.contains("Shoulders to waist is 1.40") })
    }

    @Test func aSummaryFromTheFirstBuildStillReads() throws {
        // The first builds to publish this kept every reason in one list.
        let old = #"{"targets":"vTaper","fatLoss":0.4,"build":0,"buildRegions":[],"atLeanFloor":false,"reasons":["Shoulders to waist is 1.41."]}"#
        let read = try JSONDecoder().decode(PhysiqueDirection.self, from: Data(old.utf8))
        #expect(read.fatLoss == 0.4 && read.fatLossReasons.isEmpty && read.buildReasons.isEmpty)
        // Without its reasons, the plan still says why.
        let plan = PhasePlanner.recommend(input(waist: 88, goals: [.biggerAndStronger], physique: read))
        #expect(plan.phases.first?.kind == .miniCut)
        #expect(plan.reasons.contains { $0.contains("waist holds your proportions back") })
        #expect(!plan.reasons.contains { $0.hasPrefix("At a leaner waist these") })
    }
}
