import Foundation
import ExerciseLibrary
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
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, access: EquipmentAccess, unit: WeightUnit, barWeight: Double, plates: [Double],
                dumbbellStep: Double, dumbbellMax: Double, machineStep: Double, equipment: Set<Equipment>, apparatus: Set<Apparatus>,
                excluded: Set<String> = [], included: Set<String> = [], updatedAt: Date = Date()) {
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
        self.updatedAt = updatedAt
    }

    /// A gym of a kind, with plates and steps typical for the unit.
    public static func preset(_ access: EquipmentAccess, unit: WeightUnit) -> Gym {
        let availability = Availability(access: access)
        let kg = unit == .kg
        let cap = availability.dumbbellMaxKg.map { unit.fromKilograms($0).rounded() } ?? (kg ? 50 : 120)
        return Gym(name: access.label, access: access, unit: unit, barWeight: kg ? 20 : 45,
                   plates: kg ? [25, 20, 15, 10, 5, 2.5, 1.25] : [45, 35, 25, 10, 5, 2.5],
                   dumbbellStep: kg ? 2 : 5, dumbbellMax: max(kg ? 2 : 5, cap), machineStep: kg ? 5 : 10,
                   equipment: availability.equipment, apparatus: availability.apparatus)
    }

    public var availability: Availability {
        Availability(equipment: equipment, apparatus: apparatus, dumbbellMaxKg: unit.toKilograms(dumbbellMax),
                     excluded: excluded, included: included)
    }

    public var hasSafeties: Bool { apparatus.contains(.rack) }

    /// The loads this gym makes for one piece of equipment.
    public func increments(for equipment: Equipment) -> GymIncrements { GymIncrements(gym: self, equipment: equipment) }

    /// The gym moved to the other unit. Plates don't convert, so they become the typical ones.
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
}

/// A gym's makeable loads for one kind of equipment, in kg, for the core's progression maths.
public struct GymIncrements: LoadIncrements, Hashable {
    public var gym: Gym
    public var equipment: Equipment

    public init(gym: Gym, equipment: Equipment) {
        self.gym = gym
        self.equipment = equipment
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

    static func cents(_ value: Double) -> Int { Int((value * 100).rounded()) }

    /// Every load makeable up to a limit, ascending, in the gym's unit.
    public func loads(upTo limit: Double) -> [Double] {
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

    public func step(_ kg: Double, direction: Int) -> Double {
        let current = gym.unit.fromKilograms(max(kg, 0))
        let loads = [0] + self.loads(upTo: current + 100)
        let next = direction > 0 ? loads.first { $0 > current + 1e-9 } : loads.last { $0 < current - 1e-9 }
        return gym.unit.toKilograms(next ?? (direction > 0 ? current : 0))
    }

    /// Loads near a target, for the Watch's crown.
    public func around(_ kg: Double?, below: Int = 12, above: Int = 16) -> [Double] {
        let target = gym.unit.fromKilograms(max(kg ?? 0, 0))
        let loads = [0] + self.loads(upTo: max(target * 1.6, target + 60))
        let index = loads.firstIndex { $0 >= target - 1e-9 } ?? loads.count - 1
        let lo = max(0, index - below), hi = min(loads.count - 1, index + above)
        return loads[lo...hi].map { gym.unit.toKilograms($0) }
    }

    /// Plates for one side of the bar, heaviest first; nil when not plate-loaded or not makeable.
    public func platesPerSide(_ kg: Double) -> [Double]? {
        guard equipment.platePaired else { return nil }
        let perSide = Self.cents((gym.unit.fromKilograms(kg) - base) / 2)
        guard perSide >= 0 else { return nil }
        let sizes = gym.plates.map(Self.cents).sorted(by: >)
        var best: [Int: [Int]] = [0: []]
        if perSide > 0 {
            for total in 1...perSide {
                var choice: [Int]?
                for size in sizes {
                    if let rest = best[total - size], choice == nil || rest.count + 1 < choice!.count { choice = [size] + rest }
                }
                if let choice { best[total] = choice }
            }
        }
        return best[perSide].map { $0.sorted(by: >).map { Double($0) / 100 } }
    }
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
