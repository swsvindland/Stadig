import Foundation
import ExerciseLibrary
import SystemCore

/// Everything a new mesocycle is built from.
public struct GeneratorInput: Sendable {
    public var profile: SharedProfile
    public var settings: LiftSettings
    public var gym: Gym
    public var catalog: ExerciseCatalog
    public var kind: BlockKind
    public var start: Day
    public var loadingWeeks: Int
    public var phase: NutritionPhase
    public var strength: StrengthProfile?
    public var physique: PhysiqueAnalysis?
    public var agility: AgilityAnalysis?
    public var endurance: EnduranceAnalysis?
    public var fatigue: FatigueAssessment?
    /// The hub's recommendations addressed to Lift Track.
    public var recommendations: [Recommendation]
    public var injuries: [Injury]
    public var previous: Mesocycle?
    /// Exercises stalled long enough to rotate out.
    public var stalled: Set<String>
    public var trust: TrustState

    public init(profile: SharedProfile, settings: LiftSettings, gym: Gym, catalog: ExerciseCatalog, kind: BlockKind, start: Day,
                loadingWeeks: Int, phase: NutritionPhase, strength: StrengthProfile? = nil, physique: PhysiqueAnalysis? = nil,
                agility: AgilityAnalysis? = nil, endurance: EnduranceAnalysis? = nil, fatigue: FatigueAssessment? = nil,
                recommendations: [Recommendation] = [], injuries: [Injury] = [], previous: Mesocycle? = nil, stalled: Set<String> = [],
                trust: TrustState) {
        self.profile = profile
        self.settings = settings
        self.gym = gym
        self.catalog = catalog
        self.kind = kind
        self.start = start
        self.loadingWeeks = loadingWeeks
        self.phase = phase
        self.strength = strength
        self.physique = physique
        self.agility = agility
        self.endurance = endurance
        self.fatigue = fatigue
        self.recommendations = recommendations
        self.injuries = injuries
        self.previous = previous
        self.stalled = stalled
        self.trust = trust
    }
}

/// What a day's slot asks for before an exercise is chosen.
struct SlotRequest {
    var role: SlotRole
    var patterns: [MovementPattern]
    var category: StrengthCategory?
    var muscles: [Muscle]
    var sets: Int
    /// A machine or cable that can be taken to failure: the calibration anchor.
    var anchor = false
}

enum Templates {
    static func main(_ category: StrengthCategory, sets: Int = 3) -> SlotRequest {
        let muscles: [Muscle] = switch category {
        case .squat: [.quads, .glutes]
        case .floorPull: [.hamstrings, .glutes, .lowerBack]
        case .horizontalPress: [.chest, .triceps]
        case .inclinePress: [.chest, .frontDelts]
        case .verticalPress: [.frontDelts, .sideDelts, .triceps]
        case .verticalPull: [.lats, .biceps]
        case .horizontalPull: [.upperBack, .lats]
        }
        return SlotRequest(role: .main, patterns: category.patterns, category: category, muscles: muscles, sets: sets)
    }

    static func accessory(_ patterns: [MovementPattern], _ muscles: [Muscle], sets: Int = 3, anchor: Bool = false) -> SlotRequest {
        SlotRequest(role: .accessory, patterns: patterns, muscles: muscles, sets: sets, anchor: anchor)
    }

    static let quadAnchor = accessory([.legPress, .legExtension, .squat], [.quads], anchor: true)
    static let hamCurl = accessory([.legCurl], [.hamstrings], anchor: true)
    // Hamstrings only: counting glutes here picks a trap bar deadlift or pull-through over the RDL.
    // The hip thrust slot covers glutes.
    static let rdl = accessory([.hinge, .hipThrust], [.hamstrings])
    /// Glutes at short length, where the squat trains them long.
    static let hipThrust = accessory([.hipThrust], [.glutes], anchor: true)
    /// The side glutes, which squats, hinges and lunges barely reach.
    static let abduction = accessory([.hipAbduction, .hipThrust], [.glutes], sets: 2, anchor: true)
    static let lunge = accessory([.lunge, .legPress], [.quads, .glutes])
    static let legExtension = accessory([.legExtension], [.quads], sets: 2, anchor: true)
    static let calves = accessory([.calfRaise], [.calves], sets: 2, anchor: true)
    static let abs = accessory([.crunch, .legRaise, .core], [.abs], sets: 2)
    static let pressAnchor = accessory([.horizontalPress, .inclinePress, .chestFly], [.chest], anchor: true)
    static let fly = accessory([.chestFly, .dip], [.chest], sets: 2, anchor: true)
    static let rowAnchor = accessory([.horizontalRow], [.upperBack, .lats], anchor: true)
    static let pulldown = accessory([.verticalPull, .pullover], [.lats], anchor: true)
    static let lateral = accessory([.lateralRaise], [.sideDelts], sets: 3, anchor: true)
    static let rearDelt = accessory([.rearDeltFly, .facePull], [.rearDelts], sets: 2, anchor: true)
    static let curl = accessory([.curl], [.biceps], sets: 2, anchor: true)
    static let triceps = accessory([.tricepsExtension, .dip], [.triceps], sets: 2, anchor: true)
    static let overhead = accessory([.verticalPress], [.frontDelts, .sideDelts])

    static func split(days: Int) -> SplitKind {
        switch days {
        case ...3: .fullBody
        case 4: .upperLower
        case 5: .upperLowerPushPullLegs
        default: .pushPullLegs
        }
    }

    struct DayTemplate {
        var name: String
        var focus: DayFocus
        var requests: [SlotRequest]

        init(_ name: String, _ focus: DayFocus, _ requests: [SlotRequest]) {
            self.name = name
            self.focus = focus
            self.requests = requests
        }
    }

    /// The days of a split, each a name, a focus and its slot requests in order of importance.
    /// Every lower and legs day has direct glute work high enough to survive an hour: a hip
    /// thrust after a squat, abduction after a deadlift, which already loads the glutes heavily.
    static func days(_ split: SplitKind, count: Int) -> [DayTemplate] {
        let upperA = DayTemplate("Upper A", .upper, [main(.horizontalPress), main(.horizontalPull), main(.verticalPress), pulldown, lateral, triceps, curl])
        let lowerA = DayTemplate("Lower A", .lower, [main(.squat), rdl, hipThrust, quadAnchor, hamCurl, calves, abs])
        let upperB = DayTemplate("Upper B", .upper, [main(.inclinePress), main(.verticalPull), rowAnchor, fly, rearDelt, curl, triceps])
        let lowerB = DayTemplate("Lower B", .lower, [main(.floorPull), lunge, hamCurl, abduction, legExtension, calves, abs])
        switch split {
        case .fullBody:
            // Two days carry all seven scored lifts between them.
            if count == 2 {
                return [
                    DayTemplate("Full body A", .full, [main(.squat), main(.horizontalPress), main(.verticalPull), main(.inclinePress), hamCurl, lateral, curl]),
                    DayTemplate("Full body B", .full, [main(.floorPull), main(.verticalPress), main(.horizontalPull), quadAnchor, fly, triceps, abs]),
                ]
            }
            let all = [
                DayTemplate("Full body A", .full, [main(.squat), main(.horizontalPress), main(.verticalPull), rdl, lateral, curl, abs]),
                DayTemplate("Full body B", .full, [main(.floorPull), main(.verticalPress), main(.horizontalPull), quadAnchor, fly, triceps, calves]),
                DayTemplate("Full body C", .full, [main(.inclinePress), lunge, pulldown, hamCurl, rowAnchor, rearDelt, abs]),
            ]
            return Array(all.prefix(max(1, count)))
        case .upperLower:
            return [upperA, lowerA, upperB, lowerB]
        case .upperLowerPushPullLegs:
            return [
                upperA, lowerA,
                DayTemplate("Push", .push, [main(.inclinePress), overhead, pressAnchor, lateral, triceps]),
                DayTemplate("Pull", .pull, [main(.verticalPull), main(.horizontalPull), rowAnchor, rearDelt, curl]),
                DayTemplate("Legs", .legs, [main(.floorPull), lunge, hamCurl, abduction, quadAnchor, calves, abs]),
            ]
        case .pushPullLegs:
            return [
                DayTemplate("Push A", .push, [main(.horizontalPress), main(.verticalPress), fly, lateral, triceps]),
                DayTemplate("Pull A", .pull, [main(.horizontalPull), main(.verticalPull), rearDelt, curl, abs]),
                DayTemplate("Legs A", .legs, [main(.squat), rdl, hipThrust, legExtension, hamCurl, calves]),
                DayTemplate("Push B", .push, [main(.inclinePress), overhead, pressAnchor, lateral, triceps]),
                DayTemplate("Pull B", .pull, [main(.verticalPull), rowAnchor, rearDelt, curl, abs]),
                DayTemplate("Legs B", .legs, [main(.floorPull), lunge, hamCurl, abduction, quadAnchor, calves]),
            ]
        }
    }
}

/// Builds mesocycles: the split, the exercises, the volume, the Fatigue Budget's trade-offs and an
/// elastic time budget for every day.
public enum ProgramGenerator {
    public static func generate(_ input: GeneratorInput) -> Mesocycle {
        var builder = Builder(input: input)
        return builder.build()
    }

    /// The same day fitted to a different amount of time ("I've only got 30 minutes today").
    /// Lifting keeps its exercises in order of importance; warm-up, mobility and conditioning flex.
    public static func refit(_ day: PlannedDay, minutes: Int, input: GeneratorInput) -> PlannedDay {
        var builder = Builder(input: input)
        builder.gatherPriorities()
        var lifting = day
        lifting.blocks = day.blocks.filter { $0.kind == .main || $0.kind == .accessory }
        lifting.overflow = []
        // A longer day today adds only what a day's share of the recovery budget has room for.
        let budget = FatigueBudget.weeklySystemicBudget(experience: input.profile.experience, daysPerWeek: input.profile.schedule.daysPerWeek,
                                                        phase: input.kind == .standard ? input.phase.effects : NutritionPhase.assumedMaintenance.effects,
                                                        assessment: input.fatigue, outside: .zero)
        let cost = lifting.strengthSlots.map { Double($0.sets(week: 0)) * input.catalog.resolve($0.exerciseID).fatigue.systemic }.reduce(0, +)
        let allowance = max(0, budget / Double(max(1, input.profile.schedule.daysPerWeek)) - cost)
        return builder.fitTime(lifting, minutes: minutes, allowance: allowance)
    }
}

struct Builder {
    let input: GeneratorInput
    let emphasis: GoalEmphasis
    let availability: Availability
    var reasons: [String] = []
    var priorities: [TrainingPriority] = []
    var used: [String: Int] = [:]
    /// Weekly recovery budget left after the plan, for sets added to fill spare time.
    var fatigueHeadroom: Double = .infinity

    init(input: GeneratorInput) {
        self.input = input
        emphasis = GoalEmphasis.combined(input.profile.goals)
        availability = input.gym.availability
    }

    // MARK: Priorities

    mutating func gatherPriorities() {
        // The person's own focus comes first, in every block and whatever auto-prioritisation says.
        var list = PhysiqueRegion.allCases.filter(input.settings.focus.contains).map { region in
            TrainingPriority(target: .physique(region), emphasis: 1, reason: "You chose \(region.label.lowercased()) as a focus.", source: .person)
        }
        if input.settings.autoPrioritise, input.kind == .standard {
            list += input.strength?.priorities ?? []
            for gap in input.physique?.gaps.prefix(2) ?? [] where gap.magnitude > 0.15 {
                list.append(TrainingPriority(target: .physique(gap.region), emphasis: min(1, 0.5 + gap.magnitude),
                                             reason: "\(gap.finding) \(gap.action)", source: .physique))
            }
        }
        if let limiter = input.agility?.limiter {
            list.append(TrainingPriority(target: .mobility(limiter), emphasis: 0.5,
                                         reason: "\(limiter.label) is your weakest mobility test, so every session starts a few minutes there.",
                                         source: .agility))
        }
        if let endurance = input.endurance, endurance.engineLagging || endurance.benchmarkLagging {
            list.append(TrainingPriority(target: .conditioning, emphasis: 0.5,
                                         reason: endurance.benchmarkLagging
                                             ? "Your conditioning benchmark hasn't moved, so the post-lift block uses intervals."
                                             : "Your aerobic base is light, so the post-lift block is steady Zone 2.",
                                         source: .endurance))
        }
        for rec in input.recommendations where rec.to == .liftTrack && rec.isActive() {
            guard let subject = rec.subject else { continue }
            let sign: Double = rec.kind == .deprioritise ? -0.7 : 1
            let target: TrainingPriority.Target? = switch subject {
            case .strength(let c): .category(c)
            case .physique(let p): .physique(p)
            case .mobility(let m): .mobility(m)
            case .conditioning: .conditioning
            case .muscle(let m): .physique(m.physiqueRegion)
            case .stat: nil
            }
            if let target, rec.kind != .deloadNow { list.append(TrainingPriority(target: target, emphasis: sign, reason: rec.reason, source: .hub)) }
        }
        priorities = list
    }

    /// −1…+1: how much this slot's work is wanted this block.
    func emphasis(for exercise: Exercise, request: SlotRequest) -> Double {
        var total = 0.0
        for priority in priorities {
            switch priority.target {
            case .category(let c):
                if exercise.strength?.category == c || (request.category == c) || c.patterns.contains(exercise.pattern) { total += priority.emphasis }
            case .region(let r):
                if region(of: exercise) == r { total += priority.emphasis }
            case .physique(let p):
                let share = exercise.muscles.filter { $0.muscle.physiqueRegion == p }.map(\.weight).reduce(0, +)
                if share >= 1 { total += priority.emphasis }
            case .mobility, .conditioning:
                break
            }
        }
        return clamp(total, -1, 1.5)
    }

    func region(of exercise: Exercise) -> StrengthCategory.Region? {
        let primary = exercise.primaryMuscles.first ?? exercise.muscles.first?.muscle
        guard let muscle = primary else { return nil }
        switch muscle.region {
        case .legs: return .lower
        case .push: return .upperPush
        case .pull: return .upperPull
        case .core: return muscle == .lowerBack ? .lower : nil
        }
    }

    // MARK: Choosing exercises

    var strengthCandidates: [Exercise] {
        input.catalog.of(kind: .strength).filter { exercise in
            availability.allows(exercise) && !input.settings.avoid.contains(exercise.id)
                && !input.injuries.contains { $0.excludes(exercise) }
        }
    }

    /// The classic lift for each scored category: the default for a main slot.
    static let canonical: [StrengthCategory: String] = [
        .squat: "barbell-back-squat", .floorPull: "conventional-deadlift", .horizontalPress: "barbell-bench-press",
        .inclinePress: "barbell-incline-bench-press", .verticalPress: "barbell-overhead-press", .verticalPull: "pull-up",
        .horizontalPull: "barbell-row",
    ]

    func score(_ exercise: Exercise, for request: SlotRequest, dayUsed: Set<String>) -> Double? {
        guard request.patterns.contains(exercise.pattern) else { return nil }
        if dayUsed.contains(exercise.id) { return nil }
        var score = 0.0
        if let index = request.patterns.firstIndex(of: exercise.pattern) { score -= Double(index) * 1.2 }
        if let category = request.category {
            // Scored slots want the scored lift: the reference itself first, then close variants.
            if exercise.strength?.category == category { score += 4 } else { score -= 2 }
            if exercise.strength?.factor == 1 { score += 1.5 }
            if Self.canonical[category] == exercise.id { score += 1.5 }
            if exercise.pattern == .hinge, category == .floorPull, exercise.strength == nil { score -= 3 }
        }
        // Calibration anchors want something that can be taken to failure safely; doubly so in
        // the assessment, where machines come first.
        if request.anchor {
            if exercise.safetyTier == .safeToFail { score += input.kind == .assessment ? 2.5 : 1.5 }
            if exercise.equipment.isMachine { score += 1 }
        }
        if input.profile.experience == .novice, request.category == nil, exercise.safetyTier == .safeToFail { score += 0.5 }
        // Stimulus first; then stimulus for the fatigue it costs, on a log scale so cheap isolation
        // doesn't crowd out everything else.
        score += exercise.fatigue.stimulus * 2 + log(max(0.5, exercise.fatigue.sfr)) * 0.6
        let overlap = request.muscles.map { exercise.weight(of: $0) }.reduce(0, +) / Double(max(1, request.muscles.count))
        score += overlap * 2
        // One side at a time doubles the time.
        if exercise.unilateral { score -= 0.8 }
        if exercise.isCompound, exercise.equipment.isFreeWeight { score += 0.3 }
        // Continuity: keep what's working; rotate what stalled.
        if let previous = input.previous?.exerciseIDs, previous.contains(exercise.id) { score += input.stalled.contains(exercise.id) ? -5 : 1.5 }
        else if input.stalled.contains(exercise.id) { score -= 5 }
        score -= Double(used[exercise.id, default: 0]) * 2.5
        if input.fatigue?.action == .reduceSystemic, request.category == nil { score -= exercise.fatigue.systemic * 4 }
        // Plain names first among equals.
        score -= Double(exercise.name.count) * 0.02
        return score
    }

    mutating func choose(_ request: SlotRequest, dayUsed: Set<String>) -> Exercise? {
        let ranked = strengthCandidates.compactMap { e in score(e, for: request, dayUsed: dayUsed).map { (e, $0) } }
            .sorted { $0.1 > $1.1 }
        guard let best = ranked.first?.0 else { return nil }
        used[best.id, default: 0] += 1
        return best
    }

    // MARK: Volume

    /// Main lifts lean on the goal: strength ranges for strength, hypertrophy ranges for size, and
    /// in between when both matter.
    func repRange(for exercise: Exercise, role: SlotRole) -> RepRange {
        guard role == .main else { return exercise.reps.hypertrophy }
        if emphasis.strength > emphasis.hypertrophy + 0.1 { return exercise.reps.strength }
        if emphasis.hypertrophy > emphasis.strength + 0.1 { return exercise.reps.hypertrophy }
        let lower = max(exercise.reps.strength.lower, min(5, exercise.reps.hypertrophy.lower))
        return RepRange(lower, max(lower + 2, min(exercise.reps.hypertrophy.upper, lower + 3)))
    }

    func rest(for exercise: Exercise, role: SlotRole) -> Int {
        role == .main && emphasis.strength > emphasis.hypertrophy + 0.1 ? exercise.rest.strength : exercise.rest.hypertrophy
    }

    func weeklySets(base: Int, emphasis e: Double, role: SlotRole) -> [Int] {
        var sets = Double(base)
        switch input.profile.experience {
        case .novice: break
        case .intermediate: if role == .accessory { sets += 0.3 }
        case .experienced: sets += 0.5
        }
        if input.kind == .standard { sets *= input.phase.effects.volumeTolerance }
        if e > 0.3 { sets += 1 } else if e < -0.3 { sets -= 1 }
        // Two sets at least: one set of a lift is rarely worth walking over to the equipment for.
        let start = max(2, Int(sets.rounded()))
        let weeks = input.kind == .assessment ? input.loadingWeeks : input.loadingWeeks
        // Volume ramps across a standard block for wanted work: a set more from the middle on.
        return (0..<max(1, weeks)).map { week in
            if input.kind == .standard, e > 0, week >= weeks / 2 { return start + 1 }
            return start
        }
    }

    // MARK: Build

    mutating func build() -> Mesocycle {
        gatherPriorities()
        let schedule = input.profile.schedule
        let split = Templates.split(days: schedule.daysPerWeek)
        let templates = Templates.days(split, count: schedule.daysPerWeek)
        let minutes = input.profile.schedule.minutesPerSession

        var days: [PlannedDay] = []
        for template in templates.prefix(max(1, schedule.daysPerWeek)) {
            var dayUsed: Set<String> = []
            var main: [SlotPlan] = []
            var accessory: [SlotPlan] = []
            for request in template.requests {
                guard let exercise = choose(request, dayUsed: dayUsed) else { continue }
                dayUsed.insert(exercise.id)
                let e = emphasis(for: exercise, request: request)
                // Two main lifts a day; a third scored lift is a secondary compound in the
                // accessory block, at hypertrophy reps and rests.
                let role: SlotRole = request.role == .main && main.count >= 2 ? .accessory : request.role
                let slot = SlotPlan(exerciseID: exercise.id, role: role, sets: weeklySets(base: request.sets, emphasis: e, role: request.role),
                                    repRange: repRange(for: exercise, role: role), restSeconds: rest(for: exercise, role: role),
                                    seconds: exercise.timed ? (exercise.seconds ?? 30) : nil,
                                    reason: slotReason(exercise, emphasis: e, request: request))
                if role == .main { main.append(slot) } else { accessory.append(slot) }
            }
            days.append(PlannedDay(name: template.name, focus: template.focus,
                                   blocks: [SessionBlockPlan(kind: .main, minutes: 0, slots: main),
                                            SessionBlockPlan(kind: .accessory, minutes: 0, slots: accessory)]))
        }
        addPhysiqueVolume(&days)
        applyAsymmetries(&days)
        applyFatigueBudget(&days)
        // Spare time can only add sets the recovery budget has room for, shared across the week.
        let allowance = fatigueHeadroom / Double(max(1, days.count))
        days = days.map { fitTime($0, minutes: minutes, allowance: allowance) }

        let block = TrainingBlock(kind: input.kind, start: input.start, loadingWeeks: input.loadingWeeks,
                                  deloadWeeks: input.kind == .assessment ? 0 : 1)
        return Mesocycle(block: block, split: split, days: days, priorities: priorities, rationale: rationale(split: split, days: days),
                         minutesPerSession: minutes, phase: input.phase)
    }

    func slotReason(_ exercise: Exercise, emphasis e: Double, request: SlotRequest) -> String? {
        if input.stalled.contains(where: { id in input.catalog[id]?.pattern == exercise.pattern }) && !(input.previous?.exerciseIDs.contains(exercise.id) ?? true) {
            return "Rotated in for a stalled lift with the same movement."
        }
        if e > 0.3, let p = priorities.first(where: { $0.emphasis > 0 && matches($0, exercise, request) }) { return p.reason }
        if e < -0.3 { return "Held at maintenance volume this block." }
        if input.kind == .assessment, request.anchor, exercise.safetyTier == .safeToFail {
            return "A safe exercise to rep out on: it calibrates your ratings."
        }
        return nil
    }

    func matches(_ priority: TrainingPriority, _ exercise: Exercise, _ request: SlotRequest) -> Bool {
        switch priority.target {
        case .category(let c): exercise.strength?.category == c || request.category == c
        case .region(let r): region(of: exercise) == r
        case .physique(let p): exercise.muscles.contains { $0.muscle.physiqueRegion == p && $0.weight >= 1 }
        default: false
        }
    }

    /// Lagging physique areas get cheap, local volume where it fits: lateral raises for shoulders,
    /// arm work for arms, a hip thrust on the lower day that lacks one. It barely touches recovery.
    mutating func addPhysiqueVolume(_ days: inout [PlannedDay]) {
        // Once per region, with the first reason: a focus and a measured gap don't add it twice.
        var seen: Set<PhysiqueRegion> = []
        let wanted = priorities.filter { $0.emphasis > 0 }.compactMap { p -> (PhysiqueRegion, String)? in
            if case .physique(let region) = p.target { return (region, p.reason) }
            return nil
        }.filter { seen.insert($0.0).inserted }
        for (region, reason) in wanted {
            let request: SlotRequest? = switch region {
            case .shoulders: Templates.lateral
            case .arms: Templates.curl
            case .chest: Templates.fly
            case .back: Templates.rowAnchor
            case .thighs: Templates.hamCurl
            case .calves: Templates.calves
            case .glutes: Templates.hipThrust
            case .core: Templates.abs
            }
            guard let request else { continue }
            for index in days.indices {
                let day = days[index]
                let fits = switch region {
                case .shoulders, .arms, .chest, .back: day.focus != .lower && day.focus != .legs
                default: day.focus != .upper && day.focus != .push && day.focus != .pull
                }
                guard fits, !day.slots.contains(where: { request.patterns.contains(input.catalog.resolve($0.exerciseID).pattern) }) else { continue }
                let dayUsed = Set(day.slots.map(\.exerciseID))
                guard let exercise = choose(request, dayUsed: dayUsed) else { continue }
                let slot = SlotPlan(exerciseID: exercise.id, role: .accessory, sets: weeklySets(base: 2, emphasis: 0.5, role: .accessory),
                                    repRange: exercise.reps.hypertrophy, restSeconds: exercise.rest.hypertrophy, reason: reason)
                if let accessory = days[index].blocks.firstIndex(where: { $0.kind == .accessory }) {
                    days[index].blocks[accessory].slots.insert(slot, at: 0)
                }
                break
            }
        }
    }

    /// A side that measures smaller trains one side at a time, smaller side first so it sets the
    /// reps. On each day the first accessory for that area (one already one-sided, if there is one)
    /// becomes its one-sided version and moves to the front, like any priority, so a short session
    /// keeps it.
    mutating func applyAsymmetries(_ days: inout [PlannedDay]) {
        guard input.settings.autoPrioritise, input.kind == .standard else { return }
        for asymmetry in input.physique?.asymmetries ?? [] {
            var applied = false
            for d in days.indices {
                guard let b = days[d].blocks.firstIndex(where: { $0.kind == .accessory }) else { continue }
                let slots = days[d].blocks[b].slots
                let trains = slots.indices.filter { i in
                    input.catalog.resolve(slots[i].exerciseID).muscles
                        .filter { $0.muscle.physiqueRegion == asymmetry.limb.region }.map(\.weight).reduce(0, +) >= 1
                }
                guard let s = trains.first(where: { input.catalog.resolve(slots[$0].exerciseID).unilateral }) ?? trains.first else { continue }
                var slot = slots[s]
                let current = input.catalog.resolve(slot.exerciseID)
                if !current.unilateral {
                    let dayUsed = Set(days[d].slots.map(\.exerciseID))
                    let request = SlotRequest(role: .accessory, patterns: [current.pattern], muscles: current.primaryMuscles,
                                              sets: slot.sets(week: 0))
                    let options = strengthCandidates.filter { $0.unilateral && $0.pattern == current.pattern }
                        .compactMap { e in score(e, for: request, dayUsed: dayUsed).map { (e, $0) } }
                    guard let pick = options.max(by: { $0.1 < $1.1 })?.0 else { continue }
                    slot.exerciseID = pick.id
                    slot.repRange = pick.reps.hypertrophy
                    slot.restSeconds = pick.rest.hypertrophy
                }
                slot.reason = asymmetry.action
                days[d].blocks[b].slots.remove(at: s)
                days[d].blocks[b].slots.insert(slot, at: 0)
                applied = true
            }
            if applied { reasons.append("\(asymmetry.finding) \(asymmetry.action)") }
        }
    }

    /// Spend the systemic budget on the highest-SFR options, trim before cutting total work, and
    /// fill cheap local volume freely.
    mutating func applyFatigueBudget(_ days: inout [PlannedDay]) {
        let outside = input.profile.recurring.map { recurring -> FatigueLoad in
            let log = ActivityLog(type: recurring.activity, start: Date(), minutes: recurring.minutes, intensity: recurring.intensity)
            return log.fatigue.scaled(Double(recurring.weekdays.count))
        }.reduce(FatigueLoad.zero, +)
        if !input.profile.recurring.isEmpty {
            reasons.append("Planned around \(input.profile.recurring.map(\.summary).joined(separator: "; ")): it spends the same recovery.")
        }
        let budget = FatigueBudget.weeklySystemicBudget(experience: input.profile.experience, daysPerWeek: input.profile.schedule.daysPerWeek,
                                                        phase: input.kind == .standard ? input.phase.effects : NutritionPhase.assumedMaintenance.effects,
                                                        assessment: input.fatigue, outside: outside)
        func cost() -> Double {
            days.flatMap(\.strengthSlots).map { Double($0.sets(week: 0)) * input.catalog.resolve($0.exerciseID).fatigue.systemic }.reduce(0, +)
        }

        // Beat up and stalled, or simply over budget: swap the costliest lifts for cheaper ones first.
        let swapFirst = input.fatigue?.action == .reduceSystemic || cost() > budget * 1.1
        if swapFirst {
            var swapped: [String] = []
            let slots = days.enumerated().flatMap { d, day in day.blocks.enumerated().flatMap { b, block in block.slots.indices.map { (d, b, $0) } } }
            let ranked = slots.sorted {
                input.catalog.resolve(days[$0.0].blocks[$0.1].slots[$0.2].exerciseID).fatigue.systemic >
                    input.catalog.resolve(days[$1.0].blocks[$1.1].slots[$1.2].exerciseID).fatigue.systemic
            }
            for (d, b, s) in ranked.prefix(2) {
                let slot = days[d].blocks[b].slots[s]
                let exercise = input.catalog.resolve(slot.exerciseID)
                guard exercise.fatigue.systemic >= 0.6 else { continue }
                // Scored lifts stay unless the person is beat up and stalled; the assessment needs them all.
                if exercise.strength != nil, input.fatigue?.action != .reduceSystemic || input.kind == .assessment { continue }
                let dayUsed = Set(days[d].slots.map(\.exerciseID))
                // The cheaper options, ranked the same way slots are chosen: stimulus and the same muscles first.
                let request = SlotRequest(role: .accessory, patterns: MovementPattern.allCases, muscles: exercise.primaryMuscles, sets: slot.sets(week: 0))
                let options = Substitutions.lowerSystemicCost(for: exercise, in: strengthCandidates, availability: availability, injuries: input.injuries)
                    .prefix(8).filter { !dayUsed.contains($0.id) }
                guard let cheaper = options.max(by: { (score($0, for: request, dayUsed: dayUsed) ?? -99) < (score($1, for: request, dayUsed: dayUsed) ?? -99) })
                else { continue }
                days[d].blocks[b].slots[s].exerciseID = cheaper.id
                days[d].blocks[b].slots[s].repRange = cheaper.reps.hypertrophy
                days[d].blocks[b].slots[s].restSeconds = cheaper.rest.hypertrophy
                days[d].blocks[b].slots[s].reason = "Swapped in for \(exercise.name): same muscles, less whole-body fatigue."
                swapped.append("\(exercise.name) → \(cheaper.name)")
                if cost() <= budget { break }
            }
            if !swapped.isEmpty {
                reasons.append(input.fatigue?.action == .reduceSystemic
                    ? "You've been beat up and stalled, so the costliest lifts are swapped before any work is cut (\(swapped.joined(separator: ", ")))."
                    : "To fit your recovery budget, the costliest lifts are swapped (\(swapped.joined(separator: ", "))).")
            }
        }

        // Still over: trim a set from the costliest accessories, protecting heavy compounds in a cut.
        var guardCount = 0
        while cost() > budget, guardCount < 40 {
            guardCount += 1
            var best: (Int, Int, Int, Double)?
            for d in days.indices {
                for b in days[d].blocks.indices {
                    for s in days[d].blocks[b].slots.indices {
                        let slot = days[d].blocks[b].slots[s]
                        // Two sets at least: a lone set isn't worth walking over to the equipment for.
                        guard slot.sets(week: 0) > 2 else { continue }
                        if slot.role == .main, input.phase.effects.protectCompounds { continue }
                        let c = input.catalog.resolve(slot.exerciseID).fatigue.systemic * (slot.role == .main ? 0.7 : 1)
                        if c > (best?.3 ?? 0) { best = (d, b, s, c) }
                    }
                }
            }
            guard let (d, b, s, _) = best else { break }
            days[d].blocks[b].slots[s].sets = days[d].blocks[b].slots[s].sets.map { max(2, $0 - 1) }
        }
        // Everything at two sets and still over: the costliest accessory goes, rather than lifts at one set.
        var dropped: [String] = []
        while cost() > budget, dropped.count < 6 {
            var best: (Int, Int, Int, Double)?
            for d in days.indices {
                for b in days[d].blocks.indices where days[d].blocks[b].kind == .accessory {
                    for s in days[d].blocks[b].slots.indices {
                        let c = input.catalog.resolve(days[d].blocks[b].slots[s].exerciseID).fatigue.systemic
                        if c > (best?.3 ?? 0) { best = (d, b, s, c) }
                    }
                }
            }
            guard let (d, b, s, _) = best else { break }
            dropped.append(input.catalog.resolve(days[d].blocks[b].slots[s].exerciseID).name)
            days[d].blocks[b].slots.remove(at: s)
        }
        if guardCount > 1 || !dropped.isEmpty {
            reasons.append("Some sets trimmed\(dropped.isEmpty ? "" : " (and \(dropped.joined(separator: ", ")) left out)") to stay within your recovery budget, so sessions can come in under your time.")
        }
        fatigueHeadroom = max(0, budget - cost())
    }

    // MARK: Time

    struct BlockSpec {
        var kind: SessionBlockKind
        var minimum: Int
        var desired: Int
        var priority: Double
    }

    static func seconds(for slot: SlotPlan, exercise: Exercise, week: Int = 0) -> Int {
        let sets = slot.sets(week: week)
        let work = slot.seconds ?? (slot.repRange.middle * 3 + 15)
        let ramp = slot.role == .main && exercise.isCompound ? 150 : 0
        return sets * (work + slot.restSeconds) + 60 + ramp
    }

    /// Fits a day into the time available. Every block has a minimum, a desired length and a
    /// priority; goals reorder the priorities. Blocks that don't fit become quests for a free block.
    func fitTime(_ day: PlannedDay, minutes: Int, allowance: Double = .infinity) -> PlannedDay {
        var day = day
        let short = minutes <= 35
        var main = day.blocks.first { $0.kind == .main }?.slots ?? []
        var accessory = day.blocks.first { $0.kind == .accessory }?.slots ?? []
        let resolve = { (slot: SlotPlan) in input.catalog.resolve(slot.exerciseID) }
        let mainSeconds = main.map { Self.seconds(for: $0, exercise: resolve($0)) }.reduce(0, +)
        let accessorySeconds = accessory.map { Self.seconds(for: $0, exercise: resolve($0)) }.reduce(0, +)

        let conditioningMinimum = minutes >= 85 ? 20 : (minutes >= 70 ? 15 : 10)
        var specs: [BlockSpec] = [
            BlockSpec(kind: .main, minimum: 15, desired: mainSeconds / 60, priority: 10),
            // Five easy minutes on a bike or rower, then a few drills.
            BlockSpec(kind: .warmup, minimum: 5, desired: minutes >= 80 ? 12 : (minutes >= 50 ? 9 : 6), priority: 8),
            BlockSpec(kind: .limiter, minimum: 3, desired: minutes >= 80 ? 8 : 4, priority: 7 + emphasis.mobility),
            BlockSpec(kind: .accessory, minimum: 8, desired: accessorySeconds / 60, priority: 6 + emphasis.hypertrophy - 0.5),
        ]
        let conditioningWanted = priorities.contains { $0.target == .conditioning } ? 1.0 : 0
        let conditioningDesired = Int(Double(minutes >= 80 ? 30 : (minutes >= 50 ? 12 : 10)) * (0.6 + 0.6 * emphasis.conditioning + 0.3 * conditioningWanted))
        if input.settings.includeConditioning, input.kind != .minimumEffective {
            specs.append(BlockSpec(kind: .conditioning, minimum: conditioningMinimum, desired: max(conditioningMinimum, conditioningDesired),
                                   priority: 4 + emphasis.conditioning * 2 + conditioningWanted))
        }
        if input.settings.includeCooldown { specs.append(BlockSpec(kind: .cooldown, minimum: 5, desired: minutes >= 80 ? 10 : 5, priority: 2)) }
        if short {
            // Ramp-up sets double as the warm-up; the limiter happens in the rests.
            specs.removeAll { $0.kind == .warmup || $0.kind == .limiter }
        }

        var allocation: [SessionBlockKind: Int] = [:]
        var remaining = minutes
        for spec in specs.sorted(by: { $0.priority > $1.priority }) where spec.minimum <= remaining && spec.desired > 0 {
            allocation[spec.kind] = spec.minimum
            remaining -= spec.minimum
        }
        for spec in specs.sorted(by: { $0.priority > $1.priority }) where allocation[spec.kind] != nil {
            let extra = min(remaining, max(0, spec.desired - spec.minimum))
            allocation[spec.kind, default: 0] += extra
            remaining -= extra
        }

        // Fit the lifting into its share: two compounds (supersetted when they don't compete) in a
        // short session; otherwise the main lifts, then accessories in order while they fit.
        if short {
            main = Array(main.prefix(2))
            if main.count == 2, resolve(main[0]).pattern.isLowerBody != resolve(main[1]).pattern.isLowerBody
                || region(of: resolve(main[0])) != region(of: resolve(main[1])) {
                main[0].supersetGroup = 1
                main[1].supersetGroup = 1
            }
        }
        let liftingBudget = ((allocation[.main] ?? 0) + (allocation[.accessory] ?? 0)) * 60
        func seconds(_ slots: [SlotPlan]) -> Int {
            slots.map { slot in
                let s = Self.seconds(for: slot, exercise: resolve(slot))
                // Supersets share their rests.
                return slot.supersetGroup != nil ? s - slot.sets(week: 0) * slot.restSeconds / 2 : s
            }.reduce(0, +)
        }
        var thinning = 0
        while seconds(main) > liftingBudget, thinning < 20 {
            thinning += 1
            if let i = main.indices.last(where: { main[$0].sets(week: 0) > 2 }) {
                main[i].sets = main[i].sets.map { max(2, $0 - 1) }
            } else if main.count > 1 {
                main.removeLast()
            } else { break }
        }
        var kept: [SlotPlan] = []
        for slot in accessory where seconds(main + kept + [slot]) <= liftingBudget { kept.append(slot) }
        accessory = kept
        // Time the lifting doesn't use goes to more sets before conditioning gets it: the main lifts
        // up to four work sets, then accessories up to three, in order of importance, while the
        // session still fits. A plan with a spare quarter of an hour shouldn't stop at two sets.
        let otherMinutes = allocation.filter { $0.key != .main && $0.key != .accessory }.values.reduce(0, +)
        var spareSeconds = minutes * 60 - otherMinutes * 60 - seconds(main + accessory)
        // Conditioning keeps the extra it was meant to have; only time beyond that is spare.
        if let wanted = specs.first(where: { $0.kind == .conditioning }), let given = allocation[.conditioning] {
            spareSeconds += max(0, given - wanted.desired) * 60
            if given > wanted.desired { allocation[.conditioning] = wanted.desired }
        }
        var growing = true
        var recovery = allowance
        while growing, spareSeconds > 0, !short {
            growing = false
            for (list, cap) in [(0, 4), (1, 3)] {
                var slots = list == 0 ? main : accessory
                for i in slots.indices where slots[i].sets(week: 0) < cap {
                    let cost = Self.seconds(for: slots[i], exercise: resolve(slots[i])) / max(1, slots[i].sets(week: 0))
                    let fatigue = resolve(slots[i]).fatigue.systemic
                    guard cost <= spareSeconds, fatigue <= recovery else { continue }
                    slots[i].sets = slots[i].sets.map { min(cap, $0 + 1) }
                    spareSeconds -= cost
                    recovery -= fatigue
                    growing = true
                    break
                }
                if list == 0 { main = slots } else { accessory = slots }
                if growing { break }
            }
        }
        allocation[.main] = Int((Double(seconds(main)) / 60).rounded())
        allocation[.accessory] = accessory.isEmpty ? nil : Int((Double(seconds(accessory)) / 60).rounded())
        // What's left after that goes to conditioning.
        let spare = minutes - allocation.values.reduce(0, +)
        if spare > 0, allocation[.conditioning] != nil { allocation[.conditioning, default: 0] += spare }

        var blocks: [SessionBlockPlan] = []
        var overflow: [OverflowItem] = []
        let lowerBody = day.focus.lowerBody
        if let m = allocation[.warmup] {
            // Easy cardio first, for the time the drills leave (five minutes at most, two at least),
            // then the drills by reps, about a minute each.
            let options = Drills.warmup(lowerBody: lowerBody, in: input.catalog.all, availability: availability)
            let opener = options.first { $0.equipment.isCardio }
            let moves = Array(options.filter { !$0.equipment.isCardio }.prefix(m >= 12 ? 4 : (m >= 8 ? 3 : 2)))
            let openerSeconds = opener.map { min($0.seconds ?? 300, max(120, (m - moves.count) * 60) / 30 * 30) }
            let slots = (opener.map { [SlotPlan(exerciseID: $0.id, role: .warmup, sets: [1], repRange: RepRange(1, 1), restSeconds: 0,
                                                seconds: openerSeconds)] } ?? [])
                + moves.map {
                    SlotPlan(exerciseID: $0.id, role: .warmup, sets: [1], repRange: RepRange(10, 10), restSeconds: 15,
                             seconds: $0.timed ? min(45, $0.seconds ?? 45) : nil)
                }
            blocks.append(SessionBlockPlan(kind: .warmup, minutes: m, slots: slots))
        }
        let limiterTarget = input.agility?.limiter ?? (lowerBody ? .hips : .shoulders)
        let limiterDrills = Drills.mobility(for: limiterTarget, in: input.catalog.all, availability: availability)
        if let m = allocation[.limiter], !limiterDrills.isEmpty {
            let drills = limiterDrills.prefix(m >= 4 ? 2 : 1)
            blocks.append(SessionBlockPlan(kind: .limiter, minutes: m, slots: drills.map {
                SlotPlan(exerciseID: $0.id, role: .mobility, sets: [2], repRange: RepRange(8, 8), restSeconds: 15,
                         seconds: $0.timed ? ($0.seconds ?? 45) : nil,
                         reason: input.agility?.limiter == nil ? nil : "Your weakest mobility test: \(limiterTarget.label.lowercased()).")
            }))
        } else if short, let drill = limiterDrills.first, !main.isEmpty {
            main[0].restFiller = drill.id
        } else if !limiterDrills.isEmpty, input.agility?.limiter != nil {
            overflow.append(OverflowItem(kind: .limiter, title: "10 min \(limiterTarget.label.lowercased()) mobility", minutes: 10, stat: .agility))
        }
        blocks.append(SessionBlockPlan(kind: .main, minutes: allocation[.main] ?? 15, slots: main))
        if !accessory.isEmpty { blocks.append(SessionBlockPlan(kind: .accessory, minutes: allocation[.accessory] ?? 0, slots: accessory)) }

        if input.settings.includeConditioning, input.kind != .minimumEffective {
            let style: ConditioningSpec.Style = input.endurance?.benchmarkLagging == true ? .intervals : .steady
            let options = Drills.conditioning(in: input.catalog.all, availability: availability, style: style)
            if let m = allocation[.conditioning], let pick = options.first {
                let spec = pick.conditioning ?? ConditioningSpec(style: style, zones: style == .steady ? 2...3 : 4...5)
                let plan = ConditioningPlan(minutes: m, zones: spec.zones, style: spec.style, workSeconds: spec.workSeconds, restSeconds: spec.restSeconds)
                blocks.append(SessionBlockPlan(kind: .conditioning, minutes: m, slots: [
                    SlotPlan(exerciseID: pick.id, role: .conditioning, sets: [1], repRange: RepRange(1, 1), restSeconds: 0, seconds: m * 60,
                             conditioning: plan, reason: priorities.first { $0.target == .conditioning }?.reason)
                ]))
            } else {
                overflow.append(OverflowItem(kind: .conditioning, title: style == .steady ? "20 min Zone 2" : "15 min intervals", minutes: 20, stat: .endurance))
            }
        }
        if input.settings.includeCooldown {
            if let m = allocation[.cooldown] {
                let muscles = Array(Set((main + accessory).flatMap { resolve($0).primaryMuscles }))
                let stretches = Drills.stretches(for: muscles, in: input.catalog.all).prefix(3)
                blocks.append(SessionBlockPlan(kind: .cooldown, minutes: m, slots: stretches.map {
                    SlotPlan(exerciseID: $0.id, role: .stretch, sets: [1], repRange: RepRange(1, 1), restSeconds: 10, seconds: $0.seconds ?? 45)
                }))
            }
        }
        day.blocks = blocks.sorted { $0.kind < $1.kind }
        day.overflow = overflow
        return day
    }

    // MARK: Why

    func rationale(split: SplitKind, days: [PlannedDay]) -> Rationale {
        var list: [String] = []
        let headline: String
        switch input.kind {
        case .assessment:
            headline = "The first \(input.loadingWeeks) weeks find your working weights and how well your ratings match what you can do."
            list.append("Machines and cables come first: they can be taken to failure safely, so they calibrate your ratings.")
            list.append("Every scored lift appears each week, so imbalances show up by the end.")
        case .neutral:
            headline = "General strength and size at normal volume while your nutrition phase is decided. It works in any phase."
        case .minimumEffective:
            headline = "The minimum effective dose: short sessions that keep strength and muscle."
        case .standard:
            let lead = priorities.filter { $0.emphasis > 0 && [.person, .strength, .physique, .hub].contains($0.source) }
            if let first = lead.first {
                let plural = if case .physique(let p) = first.target { [.shoulders, .arms, .glutes, .thighs, .calves].contains(p) } else { false }
                headline = "\(first.label) \(plural ? "come" : "comes") first this block. \(input.loadingWeeks) weeks of loading, then a deload."
            } else {
                headline = "A balanced \(input.loadingWeeks)-week block across every lift, then a deload."
            }
        }
        list.append("\(split.label), \(days.count) day\(days.count == 1 ? "" : "s") a week, about \(input.profile.schedule.minutesPerSession) minutes each.")
        for priority in priorities where priority.emphasis != 0 { list.append(priority.reason) }
        // Gaps the waist drives get no extra volume; say why.
        if input.settings.autoPrioritise, input.kind == .standard {
            for reading in input.physique?.proportions ?? [] where reading.cause == .fat {
                list.append([reading.finding, reading.action].compactMap { $0 }.joined(separator: " "))
            }
        }
        if input.kind == .standard {
            switch input.phase.kind.energy {
            case .deficit: list.append("You're in a \(input.phase.kind.label.lowercased()), so the block is shorter, heavy compounds are protected, and a stall is expected rather than a problem.")
            case .surplus: list.append("You're in a \(input.phase.kind.label.lowercased()), so volume and progression targets run a little higher.")
            case .maintenance: break
            }
            if input.phase.source != .macroTrack {
                list.append("Phase: \(input.phase.source == .selfReported ? "your answer (\(input.phase.kind.label.lowercased()))" : "not known, so maintenance is assumed"). Macro Track would make this more precise.")
            }
        }
        for injury in input.injuries { list.append("\(injury.summary): exercises that load it are swapped out; everything else keeps progressing.") }
        list += reasons
        let scored = input.strength?.categories.count ?? 0
        let confidence: String? = switch input.kind {
        case .assessment: nil
        default: scored < 4 ? "Early read: \(scored) of 7 lifts scored so far, so this block stays conservative." : nil
        }
        return Rationale(headline: headline, reasons: list, confidence: confidence)
    }
}
