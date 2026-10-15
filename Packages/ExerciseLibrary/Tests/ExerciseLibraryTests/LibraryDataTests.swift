import Testing
import SystemCore
@testable import ExerciseLibrary

@Suite("Library data")
struct LibraryDataTests {
    let library = ExerciseLibrary.bundled

    @Test func decodesEveryEntry() {
        #expect(library.count >= 300)
        #expect(ExerciseLibrary.byID.count == library.count)
    }

    @Test func idsAreUniqueKebabCase() {
        #expect(Set(library.map(\.id)).count == library.count)
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        for exercise in library {
            let id = exercise.id
            #expect(!id.isEmpty && id.allSatisfy(allowed.contains) && !id.hasPrefix("-") && !id.hasSuffix("-")
                    && !id.contains("--"), "\(id) is not kebab-case")
        }
    }

    @Test func keepsEveryLegacyID() {
        #expect(legacyIDs.count == 258)
        let missing = legacyIDs.filter { ExerciseLibrary.byID[$0] == nil }
        #expect(missing.isEmpty, "missing legacy ids: \(missing)")
        #expect(legacyIDs.allSatisfy { ExerciseLibrary.byID[$0]?.kind == .strength })
    }

    @Test func strengthEntriesAreFullyTagged() {
        let strength = library.filter { $0.kind == .strength }
        #expect(strength.count >= 258)
        for e in strength {
            #expect(!e.muscles.isEmpty, "\(e.id) has no muscles")
            #expect(e.muscles.contains { $0.weight >= 1 }, "\(e.id) has no primary mover")
            #expect(!e.joints.isEmpty, "\(e.id) loads no joint")
            #expect(Set(e.joints.map(\.joint)).count == e.joints.count, "\(e.id) repeats a joint")
            #expect(e.pattern.isStrength, "\(e.id) has a non-strength pattern")
            for value in [e.fatigue.systemic, e.fatigue.local, e.fatigue.stimulus] {
                #expect((0...1).contains(value), "\(e.id) fatigue out of range")
            }
            #expect((0.2...0.6).contains(e.fatigue.local), "\(e.id) local cost out of range")
            #expect((0.5...0.95).contains(e.fatigue.stimulus), "\(e.id) stimulus out of range")
            #expect((1.0...2.0).contains(e.fatigue.failureMultiplier), "\(e.id) failure multiplier out of range")
            #expect(e.rest.strength >= e.rest.hypertrophy && e.rest.hypertrophy >= 60, "\(e.id) rest")
            for range in [e.reps.strength, e.reps.hypertrophy] {
                #expect(range.lower >= 1 && range.lower <= range.upper && range.upper <= 30, "\(e.id) reps")
            }
            if e.restRole != .accessory {
                #expect(e.pattern.isCompound, "\(e.id) is a compound role on an isolation pattern")
            }
            if e.timed {
                #expect((e.seconds ?? 0) > 0, "\(e.id) is timed without a duration")
            } else {
                #expect(e.seconds == nil)
            }
            #expect(e.conditioning == nil)
        }
    }

    @Test func heavyCompoundsRestLongest() {
        for e in library where e.restRole == .heavyCompound {
            #expect(e.rest == RestDefaults(strength: 180, hypertrophy: 150), "\(e.id)")
            #expect(e.reps.strength == RepRange(3, 6), "\(e.id)")
            #expect(e.equipment == .barbell || e.equipment == .trapBar, "\(e.id)")
        }
    }

    @Test func strengthMappingsAreFreeWeightAndMatchTheirPattern() {
        let mapped = library.filter { $0.strength != nil }
        #expect(mapped.count >= 20)
        for e in mapped {
            let mapping = e.strength!
            let bodyweight = e.equipment == .bodyweight && e.loadBasis == .bodyweightPlus
            #expect(e.equipment.isFreeWeight || bodyweight, "\(e.id) maps a machine")
            #expect(mapping.category.patterns.contains(e.pattern), "\(e.id) maps to the wrong category")
            #expect(e.kind == .strength)
            // Per-hand dumbbell loads need roughly twice the factor of a bar.
            #expect(e.loadBasis == .perHand ? mapping.factor > 2 : (0.85...1.25).contains(mapping.factor), "\(e.id)")
        }
        // Every category has its reference lift at 1.0.
        for category in StrengthCategory.allCases {
            #expect(mapped.contains { $0.strength == StrengthMapping(category, factor: 1) }, "\(category) has no reference")
        }
    }

    @Test func loadBasisFollowsEquipment() {
        for e in library {
            switch e.loadBasis {
            case .perHand: #expect(e.equipment == .dumbbell || e.equipment == .kettlebell, "\(e.id)")
            case .bodyweightPlus: #expect(e.equipment == .bodyweight, "\(e.id)")
            case .assisted: #expect(e.equipment == .machine, "\(e.id)")
            case .external: #expect(!e.timed && e.equipment != .bodyweight && e.equipment != .band, "\(e.id)")
            case .none: #expect(e.timed || e.equipment == .band || e.kind != .strength, "\(e.id)")
            }
        }
        #expect(ExerciseLibrary.byID["pull-up"]?.loadBasis == .bodyweightPlus)
        #expect(ExerciseLibrary.byID["assisted-pull-up"]?.loadBasis == .assisted)
        #expect(ExerciseLibrary.byID["farmers-carry"]?.loadBasis == .perHand)
        #expect(ExerciseLibrary.byID["plank"]?.loadBasis == LoadBasis.none)
    }

    @Test func safetyTiersFollowTheProductRules() {
        func tier(_ id: String) -> SafetyTier? { ExerciseLibrary.byID[id]?.safetyTier }
        for e in library where e.equipment.isMachine && e.id != "smith-rdl" {
            #expect(e.safetyTier == .safeToFail, "\(e.id) is a machine")
        }
        for id in ["leg-press", "hack-squat", "db-curl", "db-lateral-raise", "standing-calf-raise", "cable-crunch",
                   "push-up", "pull-up", "chin-up", "back-extension-45", "bodyweight-squat"] {
            #expect(tier(id) == .safeToFail, "\(id)")
        }
        for id in ["barbell-bench-press", "barbell-incline-bench-press", "barbell-back-squat", "front-squat", "box-squat",
                   "pause-squat", "conventional-deadlift", "sumo-deadlift", "trap-bar-deadlift", "deficit-deadlift",
                   "db-bench-press", "chest-dip", "barbell-hip-thrust", "db-bulgarian-split-squat"] {
            #expect(tier(id) == .failWithSetup, "\(id)")
        }
        for id in ["barbell-overhead-press", "barbell-row", "pendlay-row", "barbell-rdl", "good-morning",
                   "db-overhead-extension", "kb-swing", "farmers-carry", "push-press"] {
            #expect(tier(id) == .neverToFailure, "\(id)")
        }
    }

    @Test func jointTagsMatchTheGuide() {
        func stress(_ id: String) -> [Joint: Int] {
            Dictionary(uniqueKeysWithValues: (ExerciseLibrary.byID[id]?.joints ?? []).map { ($0.joint, $0.stress.rawValue) })
        }
        #expect(stress("barbell-back-squat") == [.knee: 3, .hip: 2, .lowerBack: 2, .ankle: 2])
        #expect(stress("conventional-deadlift") == [.lowerBack: 3, .hip: 3, .knee: 2])
        #expect(stress("barbell-bench-press") == [.shoulder: 3, .elbow: 2, .wrist: 2])
        #expect(stress("chest-dip") == [.shoulder: 3, .elbow: 3, .wrist: 2])
        #expect(stress("leg-extension") == [.knee: 3])
        #expect(stress("barbell-overhead-press") == [.shoulder: 3, .lowerBack: 2, .elbow: 2, .wrist: 2])
        #expect(stress("plank") == [.lowerBack: 1, .shoulder: 1])
    }

    @Test func newKindsMeetTheirMinimums() {
        func count(_ kind: ExerciseKind) -> Int { library.filter { $0.kind == kind }.count }
        #expect(count(.mobility) >= 20)
        #expect(count(.warmup) >= 12)
        #expect(count(.stretch) >= 8)
        #expect(count(.conditioning) >= 10)
        for target in MobilityTarget.allCases {
            let drills = library.filter { $0.kind == .mobility && $0.mobilityTargets.contains(target) }
            #expect(drills.count >= 3, "\(target) has \(drills.count) drills")
        }
    }

    @Test func nonStrengthEntriesAreLightAndSafe() {
        for e in library where e.kind != .strength {
            #expect(e.pattern.rawValue == e.kind.rawValue, "\(e.id) pattern should match its kind")
            #expect(e.safetyTier == .safeToFail && e.strength == nil && e.loadBasis == .none, "\(e.id)")
            #expect(e.fatigue.systemic <= 0.5 && e.fatigue.local <= 0.5, "\(e.id)")
            if e.timed { #expect((e.seconds ?? 0) > 0, "\(e.id)") }
            switch e.kind {
            case .mobility, .stretch: #expect(!e.mobilityTargets.isEmpty || e.kind == .stretch, "\(e.id)")
            case .conditioning:
                #expect(e.timed && e.conditioning != nil, "\(e.id)")
                if let spec = e.conditioning, spec.style == .intervals {
                    #expect((spec.workSeconds ?? 0) > 0 && (spec.restSeconds ?? 0) > 0, "\(e.id)")
                }
            case .warmup, .strength: break
            }
        }
        for e in library where e.kind == .stretch { #expect(!e.muscles.isEmpty, "\(e.id) stretches nothing") }
    }
}
