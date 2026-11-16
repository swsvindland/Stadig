import ExerciseLibrary
import Foundation
import SystemCore

/// One exercise (or drill, or conditioning piece) in today's session, every set prescribed.
public struct PlannedItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var slotID: UUID?
    public var block: SessionBlockKind
    public var exerciseID: String
    public var role: SlotRole
    /// Warm-up sets first (`Warmup`), then the work.
    public var sets: [SetPrescription]
    public var repRange: RepRange
    public var rest: RestPlan
    public var seconds: Int?
    public var conditioning: ConditioningPlan?
    public var supersetGroup: Int?
    public var restFiller: String?
    /// Why the slot exists.
    public var reason: String?
    /// How today's numbers were chosen.
    public var note: String?
    public var mode: ProgressionMode?
    public var substitutedFor: String?

    public init(
        id: UUID = UUID(), slotID: UUID?, block: SessionBlockKind, exerciseID: String, role: SlotRole, sets: [SetPrescription],
        repRange: RepRange, rest: RestPlan, seconds: Int? = nil, conditioning: ConditioningPlan? = nil, supersetGroup: Int? = nil,
        restFiller: String? = nil, reason: String? = nil, note: String? = nil, mode: ProgressionMode? = nil, substitutedFor: String? = nil
    ) {
        self.id = id
        self.slotID = slotID
        self.block = block
        self.exerciseID = exerciseID
        self.role = role
        self.sets = sets
        self.repRange = repRange
        self.rest = rest
        self.seconds = seconds
        self.conditioning = conditioning
        self.supersetGroup = supersetGroup
        self.restFiller = restFiller
        self.reason = reason
        self.note = note
        self.mode = mode
        self.substitutedFor = substitutedFor
    }

    public var isStrength: Bool { role == .main || role == .accessory }
    public var workSets: [SetPrescription] { sets.filter { $0.kind != .warmup } }
}

// Saved inside a session in progress and the Watch's copy of today, and read back after an app
// update: anything added since decodes as absent (see LiveSession). A field added to one of these
// needs a line in its decoder.
extension PlannedItem {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        slotID = try c.decodeIfPresent(UUID.self, forKey: .slotID)
        block = try c.decode(SessionBlockKind.self, forKey: .block)
        exerciseID = try c.decode(String.self, forKey: .exerciseID)
        role = try c.decode(SlotRole.self, forKey: .role)
        sets = try c.decodeIfPresent([SetPrescription].self, forKey: .sets) ?? []
        repRange = try c.decode(RepRange.self, forKey: .repRange)
        rest = try c.decode(RestPlan.self, forKey: .rest)
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds)
        conditioning = try c.decodeIfPresent(ConditioningPlan.self, forKey: .conditioning)
        supersetGroup = try c.decodeIfPresent(Int.self, forKey: .supersetGroup)
        restFiller = try c.decodeIfPresent(String.self, forKey: .restFiller)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        mode = try c.decodeIfPresent(ProgressionMode.self, forKey: .mode)
        substitutedFor = try c.decodeIfPresent(String.self, forKey: .substitutedFor)
    }
}

/// Today's session, ready to start.
public struct SessionPlan: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var day: Day
    public var title: String
    public var mesocycleID: UUID?
    public var dayID: UUID?
    /// Zero-based loading week, nil in a deload.
    public var week: Int?
    public var deload: Bool
    public var checkIn: Bool
    public var assessment: Bool
    public var minimumEffectiveDose: Bool
    public var items: [PlannedItem]
    public var notes: [String]
    public var quests: [Quest]

    public init(
        id: UUID = UUID(), day: Day, title: String, mesocycleID: UUID?, dayID: UUID?, week: Int?, deload: Bool, checkIn: Bool,
        assessment: Bool, minimumEffectiveDose: Bool, items: [PlannedItem], notes: [String], quests: [Quest]
    ) {
        self.id = id
        self.day = day
        self.title = title
        self.mesocycleID = mesocycleID
        self.dayID = dayID
        self.week = week
        self.deload = deload
        self.checkIn = checkIn
        self.assessment = assessment
        self.minimumEffectiveDose = minimumEffectiveDose
        self.items = items
        self.notes = notes
        self.quests = quests
    }

    /// A rough length in minutes, without the optional sauna or steam room.
    public var estimatedMinutes: Int {
        let seconds = items.filter { $0.block != .recovery }.map { item -> Int in
            if let c = item.conditioning { return c.minutes * 60 }
            let sets = item.sets.map { set in
                let (work, rest) = item.estimatedSeconds(of: set)
                return work + rest
            }
            return sets.reduce(0, +) + (item.isStrength ? PlannedItem.setupSeconds : 0)
        }.reduce(0, +)
        return max(5, Int((Double(seconds) / 60).rounded()))
    }
}

extension SessionPlan {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        day = try c.decode(Day.self, forKey: .day)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        mesocycleID = try c.decodeIfPresent(UUID.self, forKey: .mesocycleID)
        dayID = try c.decodeIfPresent(UUID.self, forKey: .dayID)
        week = try c.decodeIfPresent(Int.self, forKey: .week)
        deload = try c.decodeIfPresent(Bool.self, forKey: .deload) ?? false
        checkIn = try c.decodeIfPresent(Bool.self, forKey: .checkIn) ?? false
        assessment = try c.decodeIfPresent(Bool.self, forKey: .assessment) ?? false
        minimumEffectiveDose = try c.decodeIfPresent(Bool.self, forKey: .minimumEffectiveDose) ?? false
        items = try c.decodeIfPresent([PlannedItem].self, forKey: .items) ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        quests = try c.decodeIfPresent([Quest].self, forKey: .quests) ?? []
    }
}

/// What the planner needs to know about the person today.
public struct PlanningContext: Sendable {
    public var catalog: ExerciseCatalog
    public var gym: Gym
    public var profile: SharedProfile
    public var settings: LiftSettings
    public var trust: TrustState
    public var phase: NutritionPhase
    public var life: LifeModeEffects
    /// Every logged set by exercise, oldest first.
    public var history: [String: [LoggedSet]]
    public var bodyweightKg: Double?
    public var enduranceScore: Double?
    /// Planned sessions already done this week, to space rep-outs.
    public var sessionIndexInWeek: Int
    /// Past sauna and steam sessions, for today's time.
    public var heat: [HeatLog] = []

    public init(
        catalog: ExerciseCatalog, gym: Gym, profile: SharedProfile, settings: LiftSettings, trust: TrustState, phase: NutritionPhase,
        life: LifeModeEffects, history: [String: [LoggedSet]], bodyweightKg: Double?, enduranceScore: Double?, sessionIndexInWeek: Int
    ) {
        self.catalog = catalog
        self.gym = gym
        self.profile = profile
        self.settings = settings
        self.trust = trust
        self.phase = phase
        self.life = life
        self.history = history
        self.bodyweightKg = bodyweightKg
        self.enduranceScore = enduranceScore
        self.sessionIndexInWeek = sessionIndexInWeek
    }

    /// The gym for today: crunch mode turns the equipment down. The same every time it's asked for
    /// (its id and date come from the person's gym), so the Watch's copy only changes when it does.
    public var todaysGym: Gym {
        guard let access = life.equipment, access != gym.access else { return gym }
        var temporary = Gym.preset(access, unit: gym.unit)
        // Never salted with 0, which would give back the gym's own id.
        temporary.id = UUID(gym.id, salt: (EquipmentAccess.allCases.firstIndex(of: access) ?? 0) + 1)
        temporary.updatedAt = gym.updatedAt
        temporary.name = "\(access.label) (crunch)"
        return temporary
    }
}

public enum SessionPlanner {
    public static func plan(_ day: PlannedDay, of mesocycle: Mesocycle, on date: Day, context: PlanningContext) -> SessionPlan {
        let block = mesocycle.block
        let blockWeek = block.week(of: date)
        let assessment = block.kind == .assessment
        var deload = blockWeek == .deload
        let checkIn = deload && date.days(until: block.end) <= 2
        let life = context.life
        let med = life.minimumEffectiveDose || block.kind == .minimumEffective
        let light = life.lightOnly
        if light { deload = true }
        let week: Int =
            switch blockWeek {
            case .loading(let w): w
            case .before: 0
            case .after, .deload: block.loadingWeeks - 1
            }
        let firstWeek = !deload && (blockWeek == .loading(0) || blockWeek == .before)
        let gym = context.todaysGym
        let availability = gym.availability
        let catalog = context.catalog
        let experience = context.profile.experience

        var notes: [String] = []
        if assessment {
            notes.append(
                week < 2
                    ? "Assessment week \(week + 1): for anything new, pick a weight you think you can do for the reps shown, and rate it. The next set adjusts."
                    : "Assessment week \(week + 1): progressive sets to check your ratings and spot imbalances.")
        }
        if blockWeek == .deload && !light { notes.append("Deload: fewer sets, lighter, nowhere near failure. Mobility and Zone 2 stay.") }
        if checkIn { notes.append("Check-in: you're fresh, so rep-outs and tests land today.") }
        if med { notes.append("Crunch mode: the minimum effective dose. Short, few sets, the big lifts kept.") }
        if light { notes.append("Head cold: light work only. Stop if you feel worse.") }
        if life.reentry { notes.append("First week back: easing in.") }
        for injury in life.injuries { notes.append("\(injury.summary): exercises that load it are swapped or skipped.") }
        for ramp in life.injuryRamps {
            notes.append(
                "Ramping \(ramp.injury.parts.map(\.label).joined(separator: ", ").lowercased()) work back in at \(Int(ramp.loadFactor * 100))% of normal load."
            )
        }

        var items: [PlannedItem] = []
        var quests: [Quest] = []
        let droppedConditioning = med && day.blocks.contains { $0.kind == .conditioning }
        let slots = resolveSlots(day, med: med, light: light, availability: availability, context: context, notes: &notes)

        // Rep-outs: where and how many.
        let wantsRepOuts =
            (!deload || checkIn) && !med && !light && !life.reentry
            && FailurePolicy.wantsRepOut(
                trust: context.trust, assessment: assessment, checkIn: checkIn, sessionIndexInWeek: context.sessionIndexInWeek)
        let repOutCap = wantsRepOuts ? FailurePolicy.capPerSession(experience: experience, assessment: assessment || checkIn) : 0
        let repOutSlots = chooseRepOuts(slots, cap: repOutCap, checkIn: checkIn, hasSafeties: gym.hasSafeties, context: context)

        for resolved in slots {
            let slot = resolved.slot
            let exercise = resolved.exercise
            let substitutedFor = resolved.substitutedFor
            switch slot.role {
            case .main, .accessory:
                let rir: Double = assessment ? (week < 2 ? 3 : 2) : (med ? 2 : Progression.targetRIR(week: week, of: block.loadingWeeks))
                var sets = slot.sets(week: week)
                if med { sets = 2 }
                if life.reentry { sets = max(slot.role == .main ? 2 : 1, sets - 1) }
                let target = SlotTarget(
                    sets: sets, repRange: slot.repRange, targetRIR: rir, deload: deload,
                    repOut: repOutSlots.contains(slot.id), firstWeek: firstWeek)
                let progression = ProgressionContext(
                    exercise: exercise, increments: gym.increments(for: exercise), trust: context.trust,
                    phase: context.phase.effects, loadFactor: life.loadFactor(for: exercise) * (life.reentry ? 0.92 : 1),
                    bodyweightKg: context.bodyweightKg, history: context.history[exercise.id] ?? [])
                let prescription = Progression.prescribe(target, progression)
                let increments = gym.increments(for: exercise)
                var warmups: [SetPrescription] = []
                if let first = prescription.sets.first, first.kind != .findingWeight, let load = first.loadKg {
                    warmups = Warmup.sets(
                        to: load, reps: first.targetReps, targetRIR: first.targetRIR, exercise: exercise, role: slot.role,
                        increments: increments)
                } else if let first = prescription.sets.first, first.kind == .findingWeight,
                    let guess = StartingLoad.estimate(
                        exercise, reps: first.targetReps, bodyweightKg: context.bodyweightKg,
                        sex: context.profile.sex, experience: context.profile.experience)
                {
                    // No working weight yet: the lifts that climb still warm up, toward a guess at it, on the light side.
                    warmups = Warmup.sets(
                        to: increments.round(guess * 0.9, down: true), reps: first.targetReps, targetRIR: first.targetRIR,
                        exercise: exercise, role: slot.role, increments: increments, findingWeight: true)
                }
                let all = warmups + prescription.sets
                let rest = Rest.plan(
                    role: exercise.restRole, reps: prescription.sets.first?.targetReps ?? slot.repRange.middle,
                    defaultSeconds: slot.restSeconds, enduranceScore: context.enduranceScore,
                    hrGuidance: context.settings.heartRateGuidedRest)
                items.append(
                    PlannedItem(
                        id: UUID(slot.id, salt: date.ordinal), slotID: slot.id, block: resolved.block, exerciseID: exercise.id, role: slot.role,
                        sets: all,
                        repRange: slot.repRange, rest: rest, seconds: slot.seconds, supersetGroup: med ? nil : slot.supersetGroup,
                        restFiller: slot.restFiller, reason: slot.reason, note: prescription.reason, mode: prescription.mode,
                        substitutedFor: substitutedFor))
            case .mobility, .warmup, .stretch, .recovery:
                let count = max(1, slot.sets(week: week))
                let sets = (0..<count).map { _ in
                    SetPrescription(kind: .working, loadKg: nil, targetReps: slot.repRange.middle, targetRIR: 5, seconds: slot.seconds)
                }
                // Warm-ups, drills and stretches flow straight on: no rest timer.
                items.append(
                    PlannedItem(
                        id: UUID(slot.id, salt: date.ordinal), slotID: slot.id, block: resolved.block, exerciseID: exercise.id, role: slot.role,
                        sets: sets,
                        repRange: slot.repRange, rest: RestPlan(target: 0, minimum: 0, heartRateGuided: false),
                        seconds: slot.seconds, reason: slot.reason))
            case .conditioning:
                var plan = slot.conditioning ?? ConditioningPlan(minutes: 15, zones: 2...3, style: .steady)
                if deload {
                    // Zone 2 stays in a deload; intervals don't.
                    plan.style = .steady
                    plan.zones = 2...2
                    plan.workSeconds = nil
                    plan.restSeconds = nil
                }
                items.append(
                    PlannedItem(
                        id: UUID(slot.id, salt: date.ordinal), slotID: slot.id, block: .conditioning, exerciseID: exercise.id, role: .conditioning,
                        sets: [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 3, seconds: plan.minutes * 60)],
                        repRange: RepRange(1, 1), rest: RestPlan(target: 0, minimum: 0, heartRateGuided: false),
                        seconds: plan.minutes * 60, conditioning: plan, reason: slot.reason))
            }
        }

        // Heat afterwards where the gym has it: offered, never required, and not on a sick day.
        if !light, let room = Drills.recovery(in: catalog.all, availability: availability).first {
            // From the last session's heat and how it felt, at its temperature; today's reading adjusts it.
            let heat = HeatDose.plan(context.heat, room: room.id)
            let minutes = heat.minutes(at: heat.temperatureC, room: room.id)
            items.append(
                PlannedItem(
                    id: UUID(day.id, salt: date.ordinal + 7_000_000), slotID: nil, block: .recovery, exerciseID: room.id,
                    role: .recovery,
                    sets: [SetPrescription(kind: .working, loadKg: nil, targetReps: 1, targetRIR: 5, seconds: minutes * 60)],
                    repRange: RepRange(1, 1), rest: RestPlan(target: 0, minimum: 0, heartRateGuided: false),
                    seconds: minutes * 60,
                    reason: room.id == "sauna"
                        ? "Optional. Regular sauna use goes with better heart health. Read the thermometer and the time follows."
                        : "Optional: a warm, humid wind-down. Read the thermometer and the time follows."))
        }

        let questDay = date
        for overflow in day.overflow where !med || overflow.kind != .conditioning {
            quests.append(
                Quest(
                    id: "lift-\(questDay.iso)-\(overflow.kind.rawValue)", title: "\(overflow.title) this evening",
                    detail: "It didn't fit in today's session.", stat: overflow.stat, source: .liftTrack, minutes: overflow.minutes,
                    day: questDay, timeOfDay: .evening, priority: overflow.stat == .agility ? 2 : 1))
        }
        if droppedConditioning {
            quests.append(
                Quest(
                    id: "lift-\(questDay.iso)-conditioning", title: "A 20-minute walk", detail: "Conditioning is off the plan while things are busy.",
                    stat: .endurance, source: .liftTrack, minutes: 20, day: questDay, priority: 0.5))
        }

        // Shorter than the time set aside on purpose: say why, rather than leave an hour feeling short.
        let planned = SessionPlan(
            id: UUID(), day: date, title: "", mesocycleID: nil, dayID: nil, week: nil, deload: deload, checkIn: false,
            assessment: assessment, minimumEffectiveDose: med, items: items, notes: [], quests: []
        ).estimatedMinutes
        let budgetMinutes = mesocycle.minutesPerSession
        if !med, !light, !deload, planned <= budgetMinutes - 10 {
            let outside = context.profile.recurring.isEmpty ? "" : " Your training outside the gym spends the same recovery."
            notes.append(
                "About \(planned) minutes today, under your \(budgetMinutes): the lifting is what you can recover from this week.\(outside) Spare time is good for an easy walk, stretching or the sauna."
            )
        }

        var title = day.name
        if med { title += " · minimum dose" } else if blockWeek == .deload { title += " · deload" }
        return SessionPlan(
            id: UUID(day.id, salt: date.ordinal), day: date, title: title, mesocycleID: mesocycle.id, dayID: day.id,
            week: blockWeek == .deload ? nil : week,
            deload: deload, checkIn: checkIn, assessment: assessment, minimumEffectiveDose: med, items: items, notes: notes, quests: quests)
    }

    /// A slot and the exercise it gets today.
    struct ResolvedSlot {
        var block: SessionBlockKind
        var slot: SlotPlan
        var exercise: Exercise
        /// The planned exercise, when a stand-in replaced it.
        var substitutedFor: String?
    }

    /// Each slot's exercise for today, in order: the planned one, or the best stand-in when the gym,
    /// an injury or the avoid list rules it out (never one already used today). Blocks the day leaves
    /// out are skipped (all but the main lifts at the minimum dose; accessories and conditioning
    /// when ill), and so is a slot with nothing suitable, with a note saying so.
    static func resolveSlots(
        _ day: PlannedDay, med: Bool, light: Bool, availability: Availability, context: PlanningContext,
        notes: inout [String]
    ) -> [ResolvedSlot] {
        let catalog = context.catalog
        let life = context.life
        var used = Set<String>()
        var resolved: [ResolvedSlot] = []
        for planBlock in day.blocks {
            if med, planBlock.kind != .main { continue }
            if light, planBlock.kind == .conditioning || planBlock.kind == .accessory { continue }
            for slot in planBlock.slots {
                var exercise = catalog.resolve(slot.exerciseID)
                var substitutedFor: String?
                if !availability.allows(exercise) || life.excludes(exercise) || context.settings.avoid.contains(exercise.id) {
                    let options = Substitutions.candidates(
                        for: exercise, in: catalog.all, availability: availability, injuries: life.injuries,
                        avoid: context.settings.avoid.union(used))
                    guard let replacement = options.first else {
                        notes.append("\(exercise.name) skipped today: nothing suitable with this equipment.")
                        continue
                    }
                    substitutedFor = exercise.id
                    exercise = replacement
                }
                used.insert(exercise.id)
                resolved.append(ResolvedSlot(block: planBlock.kind, slot: slot, exercise: exercise, substitutedFor: substitutedFor))
            }
        }
        return resolved
    }

    /// Where today's rep-outs go, up to the cap: safe-to-fail anchors first, then scored lifts that
    /// have earned it (never deadlifts outside a check-in), and only on lifts with a history to test.
    /// Judged on the exercise actually done, so a stand-in that mustn't go to failure never gets one.
    static func chooseRepOuts(_ slots: [ResolvedSlot], cap: Int, checkIn: Bool, hasSafeties: Bool, context: PlanningContext) -> Set<UUID> {
        guard cap > 0 else { return [] }
        let ranked = slots.compactMap { resolved -> (UUID, Int)? in
            guard resolved.block == .main || resolved.block == .accessory else { return nil }
            let exercise = resolved.exercise
            guard FailurePolicy.allowsRepOut(exercise, trust: context.trust, experience: context.profile.experience, hasSafeties: hasSafeties),
                exercise.pattern != .hinge || checkIn, !exercise.timed, !(context.history[exercise.id] ?? []).isEmpty
            else { return nil }
            let rank = exercise.safetyTier == .safeToFail ? 0 : (resolved.block == .main ? 1 : 2)
            return (resolved.slot.id, rank)
        }.sorted { $0.1 < $1.1 }
        return Set(ranked.prefix(cap).map(\.0))
    }
}

extension UUID {
    /// A stable id derived from another and a number, so planning the same day twice gives the
    /// same ids (the Watch's copy only changes when the plan does).
    init(_ base: UUID, salt: Int) {
        var bytes = base.uuid
        withUnsafeMutableBytes(of: &bytes) { raw in
            var s = UInt64(bitPattern: Int64(salt)).littleEndian
            withUnsafeBytes(of: &s) { saltBytes in
                for i in 0..<8 { raw[8 + i] ^= saltBytes[i] }
            }
        }
        self.init(uuid: bytes)
    }
}
