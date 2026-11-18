import ExerciseLibrary
import Foundation
import SystemCore

/// A gym: what it has and which loads it can make. Loads are stored in kg everywhere else; a gym
/// keeps its plates and steps in its own unit so 45 lb stays exactly 45.
public struct Gym: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var access: EquipmentAccess
    public var unit: WeightUnit
    public var barWeight: Double
    /// Plate sizes available, each assumed to come in pairs.
    public var plates: [Double]
    public var dumbbellStep: Double
    public var dumbbellMax: Double
    public var machineStep: Double
    public var equipment: Set<Equipment>
    public var apparatus: Set<Apparatus>
    /// Exercises this gym can't do although it has their equipment.
    public var excluded: Set<String>
    /// Exercises it can do although their equipment isn't listed.
    public var included: Set<String>
    /// The step one exercise's machine moves by here, in the gym's unit, where it isn't the gym's
    /// usual: a leg press whose sled takes 20 lb at a time, a cable stack with 5 lb plates. The
    /// person sets these, from the session or the gym's settings.
    public var exerciseSteps: [String: Double]
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), name: String, access: EquipmentAccess, unit: WeightUnit, barWeight: Double, plates: [Double],
        dumbbellStep: Double, dumbbellMax: Double, machineStep: Double, equipment: Set<Equipment>, apparatus: Set<Apparatus>,
        excluded: Set<String> = [], included: Set<String> = [], exerciseSteps: [String: Double] = [:], updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.access = access
        self.unit = unit
        self.barWeight = barWeight
        self.plates = plates
        self.dumbbellStep = dumbbellStep
        self.dumbbellMax = dumbbellMax
        self.machineStep = machineStep
        self.equipment = equipment
        self.apparatus = apparatus
        self.excluded = excluded
        self.included = included
        self.exerciseSteps = exerciseSteps
        self.updatedAt = updatedAt
    }

    /// A gym of a kind, with plates and steps typical for the unit.
    public static func preset(_ access: EquipmentAccess, unit: WeightUnit) -> Gym {
        let availability = Availability(access: access)
        let kg = unit == .kg
        let cap = availability.dumbbellMaxKg.map { unit.fromKilograms($0).rounded() } ?? (kg ? 50 : 120)
        return Gym(
            name: access.label, access: access, unit: unit, barWeight: kg ? 20 : 45,
            plates: kg ? [25, 20, 15, 10, 5, 2.5, 1.25] : [45, 35, 25, 10, 5, 2.5],
            dumbbellStep: kg ? 2 : 5, dumbbellMax: max(kg ? 2 : 5, cap), machineStep: kg ? 5 : 10,
            equipment: availability.equipment, apparatus: availability.apparatus)
    }

    public var availability: Availability {
        Availability(
            equipment: equipment, apparatus: apparatus, dumbbellMaxKg: unit.toKilograms(dumbbellMax),
            excluded: excluded, included: included)
    }

    public var hasSafeties: Bool { apparatus.contains(.rack) }

    /// The loads this gym makes for one piece of equipment.
    public func increments(for equipment: Equipment) -> GymIncrements { GymIncrements(gym: self, equipment: equipment) }

    /// The loads this gym makes for one exercise: its equipment's, or its own step where one is set.
    public func increments(for exercise: Exercise) -> GymIncrements {
        GymIncrements(gym: self, equipment: exercise.equipment, exerciseStep: step(for: exercise))
    }

    /// The step set for an exercise here, when it has one and can take one.
    public func step(for exercise: Exercise) -> Double? {
        guard GymIncrements.takesOwnStep(exercise), let step = exerciseSteps[exercise.id], step > 0 else { return nil }
        return step
    }

    /// The gym with an exercise's own step set, or cleared (nil, or the step its equipment already
    /// has here, so the setting follows the gym's if that changes later).
    public func setting(step: Double?, for exercise: Exercise) -> Gym {
        var gym = self
        let usual = GymIncrements(gym: self, equipment: exercise.equipment).usualStep
        if let step, step > 0, GymIncrements.takesOwnStep(exercise), abs(step - (usual ?? 0)) > 1e-9 {
            gym.exerciseSteps[exercise.id] = (step * 100).rounded() / 100
        } else {
            gym.exerciseSteps[exercise.id] = nil
        }
        return gym
    }

    /// The gym moved to the other unit. Plates don't convert, so they become the typical ones, and
    /// exercises' own steps go with them: 20 lb is no step a kg machine has.
    public func converted(to unit: WeightUnit) -> Gym {
        guard unit != self.unit else { return self }
        var gym = Gym.preset(access, unit: unit)
        gym.id = id
        gym.name = name
        gym.equipment = equipment
        gym.apparatus = apparatus
        gym.excluded = excluded
        gym.included = included
        let heaviest = unit.fromKilograms(self.unit.toKilograms(dumbbellMax))
        gym.dumbbellMax = max(gym.dumbbellStep, (heaviest / gym.dumbbellStep).rounded() * gym.dumbbellStep)
        return gym
    }

    /// The gym as another kind: that kind's equipment, plates and steps, but still this gym, with
    /// its name, its exercise exceptions and steps, and its sauna or steam room (no kind assumes either).
    public func switched(to access: EquipmentAccess) -> Gym {
        guard access != self.access else { return self }
        var gym = Gym.preset(access, unit: unit)
        gym.id = id
        gym.name = name
        gym.apparatus.formUnion(apparatus.filter(\.isRecovery))
        gym.excluded = excluded
        gym.included = included
        gym.exerciseSteps = exerciseSteps
        return gym
    }

    /// What a settings screen changed, from `original` (the copy it opened with) to `edited`, made on
    /// this gym, the latest copy: whatever the screen left alone keeps what synced in meanwhile.
    /// Equipment, fixtures and the exercise exceptions merge item by item, so a sauna added on another
    /// device survives a dumbbell rack added here. The unit and the loads go as one, since the loads
    /// are in the unit: half of a kg gym's steps under lb would be nonsense. Exercises' own steps
    /// merge exercise by exercise, unless the unit changed, which takes them all with it.
    public func applying(_ edited: Gym, from original: Gym) -> Gym {
        var gym = self
        if edited.name != original.name { gym.name = edited.name }
        if edited.access != original.access { gym.access = edited.access }
        if edited.loads != original.loads { gym.loads = edited.loads }
        gym.equipment = Self.merge(gym.equipment, edited.equipment, from: original.equipment)
        gym.apparatus = Self.merge(gym.apparatus, edited.apparatus, from: original.apparatus)
        gym.excluded = Self.merge(gym.excluded, edited.excluded, from: original.excluded)
        gym.included = Self.merge(gym.included, edited.included, from: original.included)
        if edited.unit != original.unit {
            gym.exerciseSteps = edited.exerciseSteps
        } else {
            for (id, step) in original.exerciseSteps where edited.exerciseSteps[id] != step {
                gym.exerciseSteps[id] = edited.exerciseSteps[id]
            }
            for (id, step) in edited.exerciseSteps where original.exerciseSteps[id] != step { gym.exerciseSteps[id] = step }
        }
        return gym
    }

    private static func merge<T>(_ latest: Set<T>, _ edited: Set<T>, from original: Set<T>) -> Set<T> {
        latest.subtracting(original.subtracting(edited)).union(edited.subtracting(original))
    }

    /// The unit and everything weighed in it.
    private struct Loads: Equatable {
        var unit: WeightUnit
        var barWeight: Double
        var plates: [Double]
        var dumbbellStep: Double
        var dumbbellMax: Double
        var machineStep: Double
    }

    private var loads: Loads {
        get {
            Loads(unit: unit, barWeight: barWeight, plates: plates, dumbbellStep: dumbbellStep, dumbbellMax: dumbbellMax, machineStep: machineStep)
        }
        set {
            unit = newValue.unit
            barWeight = newValue.barWeight
            plates = newValue.plates
            dumbbellStep = newValue.dumbbellStep
            dumbbellMax = newValue.dumbbellMax
            machineStep = newValue.machineStep
        }
    }
}

// Also in the Watch's copy of today and in backups, which an older version may have written: a gym
// from before exercises had their own steps reads as having none.
extension Gym {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        access = try c.decode(EquipmentAccess.self, forKey: .access)
        unit = try c.decode(WeightUnit.self, forKey: .unit)
        barWeight = try c.decode(Double.self, forKey: .barWeight)
        plates = try c.decode([Double].self, forKey: .plates)
        dumbbellStep = try c.decode(Double.self, forKey: .dumbbellStep)
        dumbbellMax = try c.decode(Double.self, forKey: .dumbbellMax)
        machineStep = try c.decode(Double.self, forKey: .machineStep)
        equipment = try c.decode(Set<Equipment>.self, forKey: .equipment)
        apparatus = try c.decode(Set<Apparatus>.self, forKey: .apparatus)
        excluded = try c.decodeIfPresent(Set<String>.self, forKey: .excluded) ?? []
        included = try c.decodeIfPresent(Set<String>.self, forKey: .included) ?? []
        exerciseSteps = try c.decodeIfPresent([String: Double].self, forKey: .exerciseSteps) ?? [:]
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// A gym's makeable loads for one kind of equipment, in kg, for the core's progression maths.
public struct GymIncrements: LoadIncrements, Hashable {
    public var gym: Gym
    public var equipment: Equipment
    /// The exercise's own step here, in the gym's unit (`Gym.exerciseSteps`): its loads are every
    /// multiple of it instead of what the equipment usually makes.
    public var exerciseStep: Double?

    public init(gym: Gym, equipment: Equipment, exerciseStep: Double? = nil) {
        self.gym = gym
        self.equipment = equipment
        self.exerciseStep = exerciseStep.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Whether an exercise on this equipment can have a step of its own. A bar's steps are its
    /// plates, set for the whole gym; stacks, sleds, dumbbells and belts vary machine to machine.
    public static func takesOwnStep(_ equipment: Equipment) -> Bool {
        switch equipment {
        case .barbell, .ezBar, .trapBar, .smith: false
        case .rower, .bike, .stairClimber, .treadmill: false
        default: true
        }
    }

    /// Whether an exercise can have a step of its own: loaded, untimed work on such equipment.
    public static func takesOwnStep(_ exercise: Exercise) -> Bool {
        exercise.loadBasis != .none && !exercise.timed && takesOwnStep(exercise.equipment)
    }

    /// The step the equipment moves by here before any exercise's own: the gym's stack or dumbbell
    /// step, or the smallest plate (a pair of them on a sled). Nil without plates to make one.
    public var usualStep: Double? {
        let smallest = gym.plates.filter { $0 > 0 }.min()
        switch equipment {
        case .dumbbell, .kettlebell: return gym.dumbbellStep
        case .machine, .cable: return gym.machineStep
        default: return smallest.map { equipment.platePaired ? $0 * 2 : $0 }
        }
    }

    /// Bars other than the gym's standard one, in the gym's unit.
    var base: Double {
        switch equipment {
        case .barbell: gym.barWeight
        case .ezBar: gym.unit == .kg ? 10 : 25
        case .trapBar: gym.unit == .kg ? 25 : 55
        default: 0
        }
    }

    /// The empty bar, in kg; nothing for equipment loaded without one (a Smith machine's bar isn't counted).
    public var barKg: Double { gym.unit.toKilograms(base) }

    static func cents(_ value: Double) -> Int { Int((value * 100).rounded()) }

    /// Past anything anyone lifts. A typed load over it is a slip (a few extra digits) and isn't
    /// taken: the set logger and the Watch check what's typed against it.
    public static let maximumLoadKg = 1_500.0

    /// Every load makeable up to a limit, ascending, in the gym's unit. The limit goes no higher than
    /// twice the most anyone lifts, whatever's asked: the tables behind it grow with the limit, and a
    /// slipped load in the history would otherwise ask for billions of entries.
    public func loads(upTo limit: Double) -> [Double] {
        // Bounded below too: every limit under nothing makes the same table, and one far under it
        // (minus infinity, say) would trap in the conversion to cents.
        let ceiling = gym.unit.fromKilograms(Self.maximumLoadKg) * 2
        let limit = limit.isNaN ? 0 : min(max(limit, -ceiling), ceiling)
        if let step = exerciseStep {
            switch equipment {
            case .dumbbell, .kettlebell: return steps(step, through: min(limit, gym.dumbbellMax))
            case .machine, .cable, .plateLoaded: return steps(step, through: limit + step)
            // Added load or assistance starts from none.
            default: return [0] + steps(step, through: limit + step)
            }
        }
        if equipment.platePaired {
            let perSide = plateSums(limit: max(0, Self.cents((limit - base) / 2)) + 1)
            return perSide.map { base + Double($0 * 2) / 100 }
        }
        switch equipment {
        case .dumbbell, .kettlebell:
            return steps(gym.dumbbellStep, through: min(limit, gym.dumbbellMax))
        case .machine, .cable:
            return steps(gym.machineStep, through: limit + gym.machineStep)
        default:
            // Added load on a belt or vest, or assistance: any stack of plates.
            return [0] + plateSums(limit: Self.cents(limit) + 1).filter { $0 > 0 }.map { Double($0) / 100 }
        }
    }

    private func steps(_ step: Double, through end: Double) -> [Double] {
        let step = step > 0 ? step : 1
        var loads: [Double] = []
        var w = step
        while w <= end + 1e-9 {
            loads.append((w * 100).rounded() / 100)
            w += step
        }
        return loads
    }

    private func plateSums(limit: Int) -> [Int] {
        guard limit >= 0 else { return [0] }
        return PlateSums.shared.sums(gym.plates.map(Self.cents).filter { $0 > 0 }, limit: limit)
    }

    public func round(_ kg: Double, down: Bool) -> Double {
        guard kg > 0 else { return 0 }
        let target = gym.unit.fromKilograms(kg)
        let loads = self.loads(upTo: target * 1.25 + 10)
        guard var best = loads.first else { return kg }
        for load in loads {
            if down {
                if load <= target + 1e-9 { best = load }
            } else if abs(load - target) < abs(best - target) - 1e-9 {
                best = load
            }
        }
        return gym.unit.toKilograms(best)
    }

    /// Every load up to a limit with nothing on the bar or the belt first. Belt and vest loads
    /// already start at 0; a second 0 would be a crown detent that does nothing.
    private func loadsFromZero(upTo limit: Double) -> [Double] {
        let loads = self.loads(upTo: limit)
        return loads.first == 0 ? loads : [0] + loads
    }

    public func step(_ kg: Double, direction: Int) -> Double {
        let current = gym.unit.fromKilograms(max(kg, 0))
        let loads = loadsFromZero(upTo: current + 100)
        let next = direction > 0 ? loads.first { $0 > current + 1e-9 } : loads.last { $0 < current - 1e-9 }
        return gym.unit.toKilograms(next ?? (direction > 0 ? current : 0))
    }

    /// Loads near a target, for the Watch's crown.
    public func around(_ kg: Double?, below: Int = 12, above: Int = 16) -> [Double] {
        let target = gym.unit.fromKilograms(max(kg ?? 0, 0))
        let loads = loadsFromZero(upTo: max(target * 1.6, target + 60))
        let index = loads.firstIndex { $0 >= target - 1e-9 } ?? loads.count - 1
        let lo = max(0, index - below)
        let hi = min(loads.count - 1, index + above)
        return loads[lo...hi].map { gym.unit.toKilograms($0) }
    }

    /// Plates for one side of the bar, heaviest first; nil when not plate-loaded, not makeable, or
    /// past the most anyone lifts. The fewest plates, found in steps of the plates' common divisor
    /// (every kg plate is a multiple of 1.25): a 180 kg squat is 64 totals to try rather than 8,000,
    /// on every redraw of the logger. Each total keeps only its count and its last plate, and the
    /// plates are read back from those.
    public func platesPerSide(_ kg: Double) -> [Double]? {
        guard equipment.platePaired, (0...Self.maximumLoadKg).contains(kg) else { return nil }
        let perSide = Self.cents((gym.unit.fromKilograms(kg) - base) / 2)
        guard perSide > 0 else { return perSide == 0 ? [] : nil }
        let sizes = gym.plates.map(Self.cents).filter { $0 > 0 }.sorted(by: >)
        let unit = sizes.reduce(0, Self.gcd)
        guard unit > 0, perSide % unit == 0 else { return nil }
        let steps = perSide / unit
        // Fewest plates for each total in steps (nil when it can't be made), and the plate added last.
        var count: [Int?] = Array(repeating: nil, count: steps + 1)
        var last = Array(repeating: 0, count: steps + 1)
        count[0] = 0
        for total in 1...steps {
            for size in sizes where size / unit <= total {
                if let rest = count[total - size / unit], rest + 1 < count[total] ?? .max {
                    count[total] = rest + 1
                    last[total] = size
                }
            }
        }
        guard count[steps] != nil else { return nil }
        var plates: [Int] = []
        var total = steps
        while total > 0 {
            plates.append(last[total])
            total -= last[total] / unit
        }
        return plates.sorted(by: >).map { Double($0) / 100 }
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

/// Every total a set of plates can make, computed once per plate set and reused: progression
/// asks for steps and roundings many times per session.
final class PlateSums: @unchecked Sendable {
    static let shared = PlateSums()
    private var tables: [[Int]: (limit: Int, sums: [Int])] = [:]
    private let lock = NSLock()

    func sums(_ sizes: [Int], limit: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        if let table = tables[sizes], table.limit >= limit {
            return Array(table.sums.prefix { $0 <= limit })
        }
        // Grow generously so later calls hit the cache.
        let span = max(limit, 60_000)
        var reachable = [Bool](repeating: false, count: span + 1)
        reachable[0] = true
        for total in 0...span where reachable[total] {
            for size in sizes where total + size <= span { reachable[total + size] = true }
        }
        let sums = reachable.indices.filter { reachable[$0] }
        tables[sizes] = (span, sums)
        return Array(sums.prefix { $0 <= limit })
    }
}
