import Foundation
import Testing
import ExerciseLibrary
import SystemCore
@testable import LiftEngine

enum Fixture {
    static let catalog = ExerciseCatalog()
    static let start = Day(year: 2026, month: 10, day: 19)

    static func profile(days: Int = 4, minutes: Int = 60, goals: [OutcomeGoal] = [.biggerAndStronger], experience: TrainingExperience = .intermediate,
                        access: EquipmentAccess = .fullGym, recurring: [RecurringActivity] = []) -> SharedProfile {
        SharedProfile(goals: goals, schedule: TrainingSchedule(daysPerWeek: days, minutesPerSession: minutes), equipment: access,
                      experience: experience, recurring: recurring, sex: .male, birthYear: 1992, heightCm: 180,
                      units: UnitPreference(weight: .kg, length: .cm), createdBy: .liftTrack)
    }

    static func input(_ profile: SharedProfile, kind: BlockKind = .standard, settings: LiftSettings = LiftSettings(),
                      strength: StrengthProfile? = nil, fatigue: FatigueAssessment? = nil, injuries: [Injury] = [],
                      physique: PhysiqueAnalysis? = nil, endurance: EnduranceAnalysis? = nil) -> GeneratorInput {
        GeneratorInput(profile: profile, settings: settings, gym: Gym.preset(profile.equipment, unit: .kg), catalog: catalog, kind: kind,
                       start: start, loadingWeeks: kind == .assessment ? profile.experience.assessmentWeeks : 5,
                       phase: .assumedMaintenance, strength: strength, physique: physique, endurance: endurance, fatigue: fatigue,
                       injuries: injuries, trust: TrustState(experience: profile.experience))
    }

    /// A week's sets of direct glute work: compounds that also load the glutes don't count.
    static func directGluteSets(_ m: Mesocycle) -> Int {
        m.days.flatMap(\.strengthSlots).filter { [.hipThrust, .hipAbduction].contains(catalog.resolve($0.exerciseID).pattern) }
            .map { $0.sets(week: 0) }.reduce(0, +)
    }

    static func describe(_ m: Mesocycle) -> String {
        var lines = ["\(m.block.kind.label) · \(m.split.label) · \(m.block.loadingWeeks) weeks", "Why: \(m.rationale.headline)"]
        lines += m.rationale.reasons.map { "  - \($0)" }
        for day in m.days {
            lines.append("\(day.name) (\(day.minutes) min)")
            for block in day.blocks {
                lines.append("  [\(block.kind.label) \(block.minutes)m]")
                for slot in block.slots {
                    let e = catalog.resolve(slot.exerciseID)
                    lines.append("    \(e.name) \(slot.sets.map(String.init).joined(separator: "/"))×\(slot.repRange.label) rest \(slot.restSeconds)s\(slot.supersetGroup.map { " SS\($0)" } ?? "")\(slot.restFiller.map { " filler:\($0)" } ?? "")\(slot.conditioning.map { " " + $0.summary } ?? "")\(slot.reason.map { "  — \($0)" } ?? "")")
                }
            }
            for o in day.overflow { lines.append("  overflow: \(o.title)") }
        }
        return lines.joined(separator: "\n")
    }
}

@Suite("Program generator")
struct GeneratorTests {
    @Test func fourDaysCoverEveryScoredLift() {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        #expect(m.split == .upperLower)
        #expect(m.days.count == 4)
        let categories = Set(m.days.flatMap(\.strengthSlots).compactMap { Fixture.catalog.resolve($0.exerciseID).strength?.category })
        #expect(categories == Set(StrengthCategory.allCases), "\(categories)")
        for day in m.days { #expect(day.minutes <= 60, "\(day.name) is \(day.minutes) min") }
        #expect(!m.rationale.headline.isEmpty)
        if ProcessInfo.processInfo.environment["PRINT_PROGRAMS"] != nil { print(Fixture.describe(m)) }
    }

    @Test func everyDayCountFromOneToSix() {
        for days in 1...6 {
            let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: days)))
            #expect(m.days.count == days)
            #expect(m.days.allSatisfy { !$0.strengthSlots.isEmpty })
            let ids = m.days.map { $0.strengthSlots.map(\.exerciseID) }
            #expect(ids.allSatisfy { Set($0).count == $0.count }, "no exercise twice in a day")
        }
    }

    @Test func thirtyMinutesFoldsWarmupAndMobilityIn() {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: 3, minutes: 30)))
        for day in m.days {
            #expect(!day.blocks.contains { $0.kind == .warmup || $0.kind == .limiter })
            let main = day.blocks.first { $0.kind == .main }?.slots ?? []
            #expect(main.count <= 2)
            #expect(main.first?.restFiller != nil)
            #expect(day.minutes <= 30)
            #expect(!day.blocks.contains { $0.kind == .conditioning })
            #expect(day.overflow.contains { $0.kind == .conditioning })
        }
        if ProcessInfo.processInfo.environment["PRINT_PROGRAMS"] != nil { print(Fixture.describe(m)) }
    }

    @Test func ninetyMinutesGetsTheFullWarmupAndAFinisher() {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: 4, minutes: 90)))
        for day in m.days {
            #expect((day.blocks.first { $0.kind == .warmup }?.minutes ?? 0) >= 12)
            #expect((day.blocks.first { $0.kind == .conditioning }?.minutes ?? 0) >= 20)
            #expect(day.blocks.contains { $0.kind == .limiter })
            #expect(day.minutes <= 90)
        }
        if ProcessInfo.processInfo.environment["PRINT_PROGRAMS"] != nil { print(Fixture.describe(m)) }
    }

    @Test func enduranceGoalsRankConditioningHigher() {
        let fitter = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: 3, minutes: 30, goals: [.fitter])))
        let stronger = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: 3, minutes: 30, goals: [.stronger])))
        let fit = fitter.days.map { $0.blocks.first { $0.kind == .conditioning }?.minutes ?? 0 }.reduce(0, +)
        let str = stronger.days.map { $0.blocks.first { $0.kind == .conditioning }?.minutes ?? 0 }.reduce(0, +)
        #expect(fit > str)
    }

    @Test func hotelGymMeansNoBarbells() {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(access: .hotelGym)))
        let equipment = Set(m.days.flatMap(\.slots).map { Fixture.catalog.resolve($0.exerciseID).equipment })
        #expect(!equipment.contains(.barbell))
        #expect(!m.days.flatMap(\.strengthSlots).isEmpty)
    }

    @Test func injuriesFilterDeterministically() {
        let injury = Injury(parts: [InjuredPart(.shoulder, side: .right)], severity: .moderate)
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(), injuries: [injury]))
        for slot in m.days.flatMap(\.strengthSlots) {
            let e = Fixture.catalog.resolve(slot.exerciseID)
            #expect(!injury.excludes(e), "\(e.name) loads the shoulder")
        }
        #expect(m.rationale.reasons.contains { $0.contains("Shoulder") || $0.contains("shoulder") })
    }

    @Test func legsAheadMeansUpperBodyFirst() {
        let day = Fixture.start
        let strength = StrengthProfile(categories: [
            CategoryScore(category: .squat, oneRepMaxKg: 170, score: 82, exerciseID: "barbell-back-squat", day: day),
            CategoryScore(category: .floorPull, oneRepMaxKg: 200, score: 80, exerciseID: "conventional-deadlift", day: day),
            CategoryScore(category: .horizontalPress, oneRepMaxKg: 85, score: 52, exerciseID: "barbell-bench-press", day: day),
            CategoryScore(category: .verticalPull, oneRepMaxKg: 95, score: 50, exerciseID: "pull-up", day: day),
            CategoryScore(category: .verticalPress, oneRepMaxKg: 52, score: 51, exerciseID: "barbell-overhead-press", day: day),
        ], bodyweightKg: 80, sex: .male)
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(), strength: strength))
        let upper = m.days.filter { $0.focus == .upper }.flatMap(\.strengthSlots).map { Double($0.sets(week: 0)) }
        let lower = m.days.filter { $0.focus == .lower }.flatMap(\.strengthSlots).map { Double($0.sets(week: 0)) }
        #expect((upper.mean ?? 0) > (lower.mean ?? 0))
        #expect(m.rationale.headline.contains("comes first"))
        // Switching auto-prioritisation off keeps it balanced.
        var settings = LiftSettings()
        settings.autoPrioritise = false
        let plain = ProgramGenerator.generate(Fixture.input(Fixture.profile(), settings: settings, strength: strength))
        #expect(plain.priorities.allSatisfy { $0.source != .strength })
    }

    @Test func beatUpAndStalledSwapsTheCostliestLifts() {
        let fatigue = FatigueAssessment(status: .strained, loadRatio: 1.2, acute: 6, chronic: 5, signals: ["Beat up."], action: .reduceSystemic,
                                        budgetFactor: 0.85)
        let before = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        let after = ProgramGenerator.generate(Fixture.input(Fixture.profile(), fatigue: fatigue))
        let cost: (Mesocycle) -> Double = { m in
            m.days.flatMap(\.strengthSlots).map { Double($0.sets(week: 0)) * Fixture.catalog.resolve($0.exerciseID).fatigue.systemic }.reduce(0, +)
        }
        #expect(cost(after) < cost(before))
        #expect(after.rationale.reasons.contains { $0.contains("beat up") })
    }

    @Test func shoulderGapAddsSideDeltWork() {
        let physique = Physique.analyse([BodyMeasurements(day: Fixture.start, neckCm: 39, shouldersCm: 110, waistCm: 88, armCm: 36)],
                                        sex: .male, heightCm: 180)
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(), physique: physique))
        let lateral = m.days.flatMap(\.strengthSlots).filter { Fixture.catalog.resolve($0.exerciseID).pattern == .lateralRaise }
        #expect(lateral.contains { ($0.reason ?? "").contains("side-delt") })
    }

    @Test func everyLegDayTrainsGlutesDirectly() {
        let direct: [MovementPattern] = [.hipThrust, .hipAbduction]
        for access in [EquipmentAccess.fullGym, .homeGym, .hotelGym] {
            for days in 4...6 {
                let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: days, access: access)))
                for day in m.days where day.focus == .lower || day.focus == .legs {
                    #expect(day.strengthSlots.contains { direct.contains(Fixture.catalog.resolve($0.exerciseID).pattern) },
                            "\(access) \(days) days: \(day.name) has no direct glute work")
                }
                if ProcessInfo.processInfo.environment["PRINT_PROGRAMS"] != nil, access == .fullGym { print(Fixture.describe(m)) }
            }
        }
    }

    @Test func glutePriorityAddsAHipThrust() {
        let before = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        var input = Fixture.input(Fixture.profile())
        input.recommendations = [Recommendation(to: .liftTrack, kind: .prioritise, subject: .physique(.glutes), reason: "Glutes are lagging.")]
        let after = ProgramGenerator.generate(input)
        #expect(Fixture.directGluteSets(after) > Fixture.directGluteSets(before))
        let thrusts = after.days.flatMap(\.strengthSlots).filter { Fixture.catalog.resolve($0.exerciseID).pattern == .hipThrust }
        #expect(thrusts.count >= 2)
        #expect(thrusts.contains { $0.reason == "Glutes are lagging." })
    }

    @Test func chosenFocusLeadsEvenWithoutAutoPrioritising() {
        var settings = LiftSettings(autoPrioritise: false)
        settings.focus = [.glutes]
        let before = ProgramGenerator.generate(Fixture.input(Fixture.profile()))
        let after = ProgramGenerator.generate(Fixture.input(Fixture.profile(), settings: settings))
        #expect(after.priorities.first?.source == .person)
        #expect(after.rationale.headline.hasPrefix("Glutes come first"), "\(after.rationale.headline)")
        #expect(Fixture.directGluteSets(after) > Fixture.directGluteSets(before))
        #expect(after.days.flatMap(\.strengthSlots).contains { $0.reason == "You chose glutes as a focus." })
        // The assessment honours it too.
        let assessment = ProgramGenerator.generate(Fixture.input(Fixture.profile(), kind: .assessment, settings: settings))
        #expect(assessment.priorities.contains { $0.source == .person })
    }

    @Test func aFocusAndAMeasuredGapAddVolumeOnce() {
        var settings = LiftSettings()
        settings.focus = [.shoulders]
        let physique = Physique.analyse([BodyMeasurements(day: Fixture.start, neckCm: 39, shouldersCm: 110, waistCm: 88, armCm: 36)],
                                        sex: .male, heightCm: 180)
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(days: 6), settings: settings, physique: physique))
        #expect(m.priorities.filter { $0.target == .physique(.shoulders) }.count == 2)
        // Push days have lateral raises already; one pull day gains them, not both.
        let added = m.days.filter { $0.focus == .pull }.flatMap(\.strengthSlots).filter { Fixture.catalog.resolve($0.exerciseID).pattern == .lateralRaise }
        #expect(added.count == 1)
    }

    @Test func assessmentPrefersSafeToFailAnchors() {
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(experience: .novice), kind: .assessment))
        #expect(m.block.kind == .assessment)
        #expect(m.block.deloadWeeks == 0)
        #expect(m.block.loadingWeeks == 4)
        let accessories = m.days.flatMap { $0.blocks.filter { $0.kind == .accessory }.flatMap(\.slots) }
        let safe = accessories.filter { Fixture.catalog.resolve($0.exerciseID).safetyTier == .safeToFail }
        #expect(Double(safe.count) / Double(max(1, accessories.count)) > 0.7)
        if ProcessInfo.processInfo.environment["PRINT_PROGRAMS"] != nil { print(Fixture.describe(m)) }
    }

    @Test func declaredClassesSpendTheBudget() {
        let bjj = RecurringActivity(activity: .bjj, weekdays: [.tuesday, .thursday], minutes: 90, intensity: 8)
        let m = ProgramGenerator.generate(Fixture.input(Fixture.profile(recurring: [bjj])))
        #expect(m.rationale.reasons.contains { $0.contains("BJJ") })
    }
}
