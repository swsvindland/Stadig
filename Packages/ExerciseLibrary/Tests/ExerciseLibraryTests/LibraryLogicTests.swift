import SystemCore
import Testing

@testable import ExerciseLibrary

private func exercise(_ id: String) throws -> Exercise { try #require(ExerciseLibrary.byID[id]) }

@Suite("Catalog and availability")
struct CatalogTests {
    @Test func catalogResolvesKnownAndUnknownIDs() throws {
        let custom = Exercise.placeholder(id: "my-odd-lift")
        let catalog = ExerciseCatalog(custom: [custom])
        #expect(catalog.all.count == ExerciseLibrary.bundled.count + 1)
        #expect(catalog["barbell-back-squat"]?.name == "Barbell Back Squat")
        #expect(catalog["my-odd-lift"] != nil)
        let ghost = catalog.resolve("old-cable-thing")
        #expect(ghost.id == "old-cable-thing" && ghost.name == "Old Cable Thing")
        #expect(catalog.of(kind: .conditioning).allSatisfy { $0.kind == .conditioning })
        #expect(ExerciseCatalog(exercises: []).all.isEmpty)
    }

    @Test func hotelGymHasDumbbellsButNoRack() throws {
        let hotel = Availability(access: .hotelGym)
        #expect(!hotel.allows(try exercise("barbell-back-squat")))
        #expect(hotel.allows(try exercise("db-curl")))
        #expect(hotel.allows(try exercise("db-bench-press")))
        #expect(!hotel.allows(try exercise("pull-up")))
        #expect(!hotel.hasSafeties)
        #expect(hotel.dumbbellMaxKg == 22.5)
    }

    @Test func presetsMatchTheEquipmentDial() throws {
        let full = Availability(access: .fullGym)
        // Everything but the sauna and steam room, which a full gym may or may not have.
        #expect(ExerciseLibrary.bundled.filter { $0.kind != .recovery }.allSatisfy(full.allows))
        #expect(!ExerciseLibrary.bundled.filter { $0.kind == .recovery }.contains(where: full.allows))
        #expect(full.hasSafeties && full.dumbbellMaxKg == nil)
        let home = Availability(access: .homeGym)
        #expect(home.hasSafeties && home.dumbbellMaxKg == 40)
        for id in ["barbell-back-squat", "pull-up", "landmine-press"] { #expect(home.allows(try exercise(id)), "\(id)") }
        for id in ["leg-press", "glute-ham-raise", "lat-pulldown"] { #expect(!home.allows(try exercise(id)), "\(id)") }
        let floor = Availability(access: .bodyweightOnly)
        for id in ["push-up", "bodyweight-bulgarian-split-squat", "plank"] { #expect(floor.allows(try exercise(id)), "\(id)") }
        for id in ["chest-dip", "db-curl", "inverted-row"] { #expect(!floor.allows(try exercise(id)), "\(id)") }
    }

    @Test func overridesBeatTheEquipmentList() throws {
        var hotel = Availability(access: .hotelGym)
        hotel.included = ["pull-up"]
        hotel.excluded = ["db-curl"]
        #expect(hotel.allows(try exercise("pull-up")))
        #expect(!hotel.allows(try exercise("db-curl")))
    }
}

@Suite("Injuries and substitutions")
struct SubstitutionTests {
    let library = ExerciseLibrary.bundled
    let lowerBack = Injury(parts: [InjuredPart(.lowerBack)], severity: .moderate)

    @Test func lowerBackInjuryDropsDeadliftsAndKeepsLegExtensions() {
        let allowed = Set(InjuryFilter.allowed(library, injuries: [lowerBack]).map(\.id))
        #expect(!allowed.contains("conventional-deadlift"))
        #expect(!allowed.contains("barbell-back-squat"))
        #expect(allowed.contains("leg-extension"))
        #expect(allowed.contains("chest-supported-db-row"))
        let overridden = Injury(parts: [InjuredPart(.lowerBack)], severity: .moderate, allowed: ["conventional-deadlift"])
        #expect(InjuryFilter.allowed(library, injuries: [overridden]).contains { $0.id == "conventional-deadlift" })
    }

    @Test func benchAtAHotelBecomesADumbbellPress() throws {
        let bench = try exercise("barbell-bench-press")
        let picks = Substitutions.candidates(for: bench, in: library, availability: Availability(access: .hotelGym))
        #expect(!picks.isEmpty && picks.count <= 12)
        #expect(picks.first?.id == "db-bench-press")
        #expect(picks.prefix(3).allSatisfy { $0.equipment == .dumbbell && $0.pattern == .horizontalPress })
        #expect(picks.allSatisfy { Availability(access: .hotelGym).allows($0) && $0.kind == .strength })
    }

    @Test func candidatesRespectInjuriesAndAvoid() throws {
        let squat = try exercise("barbell-back-squat")
        let knee = Injury(parts: [InjuredPart(.knee, side: .left)], severity: .mild)
        let picks = Substitutions.candidates(for: squat, in: library, availability: nil, injuries: [knee], avoid: ["belt-squat"])
        #expect(!picks.isEmpty)
        #expect(picks.allSatisfy { ($0.stress(on: .knee) ?? .low) < .high })
        #expect(!picks.contains { $0.id == "belt-squat" || $0.id == squat.id })
        #expect(picks.first?.pattern == .squat)
    }

    @Test func cheaperThanADeadliftStartsWithHinges() throws {
        let deadlift = try exercise("conventional-deadlift")
        let cheaper = Substitutions.lowerSystemicCost(for: deadlift, in: library, availability: nil)
        #expect(cheaper.contains { $0.id == "barbell-rdl" })
        #expect(cheaper.allSatisfy { $0.fatigue.systemic < deadlift.fatigue.systemic && $0.fatigue.sfr > deadlift.fatigue.sfr })
        #expect(cheaper.first?.pattern == .hinge)
        let firstOther = try #require(cheaper.firstIndex { $0.pattern != .hinge })
        #expect(cheaper[firstOther...].allSatisfy { $0.pattern != .hinge })
        #expect(cheaper.contains { $0.pattern == .backExtension })
        // A real saving beats a near-copy: RDLs well ahead of the barely cheaper sumo pull.
        #expect(cheaper.prefix(6).contains { $0.id == "barbell-rdl" || $0.id == "db-rdl" })
        let sumo = try #require(cheaper.firstIndex { $0.id == "sumo-deadlift" })
        let rdl = try #require(cheaper.firstIndex { $0.id == "barbell-rdl" })
        #expect(rdl < sumo)
    }

    @Test func standInsKeepWhatFitsAndSwapTheRest() throws {
        let day = try ["barbell-back-squat", "db-bulgarian-split-squat", "leg-extension", "seated-leg-curl"].map(exercise)
        let hotel = Availability(access: .hotelGym)
        let stands = Substitutions.standIns(day, in: library, availability: hotel)
        #expect(stands.count == day.count)
        #expect(stands[1]?.id == "db-bulgarian-split-squat")
        let ids = stands.compactMap { $0?.id }
        #expect(Set(ids).count == ids.count, "a stand-in repeats an exercise")
        #expect(stands.compactMap { $0 }.allSatisfy(hotel.allows))
        #expect(stands[0]?.pattern == .squat || stands[0]?.pattern == .lunge)

        let nothing = Availability(equipment: [], apparatus: [])
        #expect(Substitutions.standIns(day, in: library, availability: nothing).allSatisfy { $0 == nil })
    }
}

@Suite("Search")
struct SearchTests {
    let library = ExerciseLibrary.bundled

    @Test(arguments: [
        ("rdl", "barbell-rdl"), ("ohp", "barbell-overhead-press"), ("bss", "db-bulgarian-split-squat"),
        ("incline db press", "db-incline-bench-press"), ("tricpes pushdown", "cable-pushdown-bar"),
        ("lat pulldowns", "lat-pulldown"), ("couch stretch", "couch-stretch"),
    ])
    func findsShorthandAndTypos(query: String, id: String) {
        let results = ExerciseSearch.search(library, query)
        #expect(results.prefix(3).contains { $0.id == id }, "\(query) → \(results.prefix(3).map(\.id))")
    }

    @Test func plainNamesAreCanonical() {
        #expect(ExerciseSearch.match(library, "Squat").exercise?.id == "barbell-back-squat")
        #expect(ExerciseSearch.match(library, "Deadlift").confident)
        #expect(ExerciseSearch.match(library, "RDL").exercise?.id == "barbell-rdl")
        let incline = ExerciseSearch.match(library, "Incline DB Press")
        #expect(incline.exercise?.id == "db-incline-bench-press" && incline.confident)
        #expect(ExerciseSearch.match(library, "").exercise == nil)
    }

    @Test func boostBreaksTies() {
        let boosted = ExerciseSearch.search(library, "curl") { $0.id == "bayesian-curl" ? 100 : 0 }
        #expect(boosted.first?.id == "bayesian-curl")
        #expect(ExerciseSearch.search(library, "").count == library.count)
    }

    @Test func stemmingIsConsistent() {
        #expect(ExerciseSearch.stem("presses") == "press")
        #expect(ExerciseSearch.stem("lunges") == "lunge")
        #expect(ExerciseSearch.stem("flies") == "fly")
        #expect(ExerciseSearch.stem("press") == "press")
        #expect(ExerciseSearch.words("Farmer's Carry") == ["farmer", "carry"])
    }

    @Test func oneTypoIsForgiven() {
        #expect(ExerciseSearch.nearly("triceps", "tricpes"), "two letters swapped")
        #expect(ExerciseSearch.nearly("lateral", "lateal"), "a letter dropped")
        #expect(ExerciseSearch.nearly("lateral", "ateral") && ExerciseSearch.nearly("lateral", "laterals"), "at either end")
        #expect(ExerciseSearch.nearly("lateral", "xlateral") && ExerciseSearch.nearly("lateral", "latxral"))
        #expect(!ExerciseSearch.nearly("lateral", "latxrxl"), "two edits")
        #expect(!ExerciseSearch.nearly("lateral", "lat"), "a prefix is the prefix check's job")
        // The five-letter floor is on the list's word: "pres" may be a typo of "press", not the other way round.
        #expect(ExerciseSearch.nearly("press", "pres"))
        #expect(!ExerciseSearch.nearly("pres", "press"))
        #expect(!ExerciseSearch.nearly("curl", "curs"))
    }

    @Test func matchDropsWordsItCantPlace() {
        let fly = ExerciseSearch.match(library, "cable fly zigzag")
        #expect(fly.exercise.map { $0.name.lowercased().contains("fly") } == true)
        #expect(!fly.confident, "a dropped word isn't a confident match")
        #expect(ExerciseSearch.match(library, "deadlfit").exercise?.id == "conventional-deadlift")
        #expect(ExerciseSearch.match(library, "with the and").exercise == nil, "only stop words")
    }

    @Test func aCustomExerciseIsSearchedByItsOwnWords() throws {
        // Same id as a bundled lift, different contents: its own name counts, not the bundled one's.
        var custom = try #require(ExerciseLibrary.byID["barbell-back-squat"])
        custom.name = "Zercher Thing"
        custom.aliases = []
        let list = [custom, Exercise.placeholder(id: "my-odd-lift")]
        #expect(ExerciseSearch.search(list, "zercher").map(\.id) == ["barbell-back-squat"])
        #expect(ExerciseSearch.search(list, "odd lift").map(\.id) == ["my-odd-lift"])
        #expect(ExerciseSearch.search(list, "back squat").isEmpty)
        #expect(ExerciseSearch.search(ExerciseLibrary.bundled, "back squat").first?.id == "barbell-back-squat")
    }
}

@Suite("Drills")
struct DrillTests {
    let library = ExerciseLibrary.bundled

    @Test func mobilityPutsTheMainTargetFirst() {
        for target in MobilityTarget.allCases {
            let drills = Drills.mobility(for: target, in: library, availability: Availability(access: .bodyweightOnly))
            #expect(drills.count >= 3, "\(target)")
            #expect(drills.first?.mobilityTargets.first == target)
        }
    }

    @Test func warmupsOpenWithCardioWhenThereIsSome() {
        let lower = Drills.warmup(lowerBody: true, in: library, availability: Availability(access: .fullGym))
        #expect(lower.first?.equipment.isCardio == true)
        #expect(lower.dropFirst().allSatisfy { !$0.equipment.isCardio && $0.preparesLowerBody })
        #expect(lower.count >= 6)
        let upper = Drills.warmup(lowerBody: false, in: library, availability: Availability(access: .bodyweightOnly))
        #expect(upper.allSatisfy { !$0.equipment.isCardio && !$0.preparesLowerBody })
        #expect(upper.count >= 3)
    }

    @Test func stretchesFollowTheMusclesTrained() {
        let stretches = Drills.stretches(for: [.hamstrings, .chest], in: library)
        #expect(stretches.first?.id == "hamstring-stretch")
        #expect(stretches.contains { $0.id == "doorway-chest-stretch" })
        #expect(Set(stretches.map(\.id)).count == stretches.count)
        for muscle in Muscle.allCases {
            #expect(!Drills.stretches(for: [muscle], in: library).isEmpty, "no stretch for \(muscle)")
        }
    }

    @Test func conditioningFiltersByStyleAndEquipment() {
        let all = Drills.conditioning(in: library, availability: nil, style: nil)
        #expect(all.count >= 10)
        let intervals = Drills.conditioning(in: library, availability: nil, style: .intervals)
        #expect(!intervals.isEmpty && intervals.allSatisfy { $0.conditioning?.style == .intervals })
        let hotel = Drills.conditioning(in: library, availability: Availability(access: .hotelGym), style: .steady)
        #expect(hotel.contains { $0.equipment == .treadmill } && !hotel.contains { $0.equipment == .rower })
    }
}
