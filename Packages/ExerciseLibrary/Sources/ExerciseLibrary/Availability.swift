import Foundation
import SystemCore

/// What a place to train has: equipment, fixtures, the heaviest dumbbell, and the person's own
/// overrides for exercises it can or can't do despite the list.
public struct Availability: Hashable, Sendable {
    public var equipment: Set<Equipment>
    public var apparatus: Set<Apparatus>
    /// The heaviest dumbbell in kg; nil when there's no practical limit.
    public var dumbbellMaxKg: Double?
    /// Exercises it can't do even though the equipment is there.
    public var excluded: Set<String>
    /// Exercises it can do even though the equipment list says otherwise.
    public var included: Set<String>

    public init(
        equipment: Set<Equipment>, apparatus: Set<Apparatus>, dumbbellMaxKg: Double? = nil,
        excluded: Set<String> = [], included: Set<String> = []
    ) {
        self.equipment = equipment
        self.apparatus = apparatus
        self.dumbbellMaxKg = dumbbellMaxKg
        self.excluded = excluded
        self.included = included
    }

    /// The typical setup for an equipment dial position.
    public init(access: EquipmentAccess) {
        let apparatus: Set<Apparatus> =
            switch access {
            // A sauna or steam room is the person's to say: plenty of full gyms have neither.
            case .fullGym: Set(Apparatus.allCases.filter { !$0.isRecovery })
            case .homeGym: [.rack, .bench, .pullUpBar, .box, .landmine]
            case .hotelGym: [.bench, .box]
            case .bodyweightOnly: [.box]
            }
        self.init(equipment: access.equipment, apparatus: apparatus, dumbbellMaxKg: access.dumbbellCapKg)
    }

    /// A rack with pins or safety arms: barbell lifts can be failed safely.
    public var hasSafeties: Bool { apparatus.contains(.rack) }

    /// Whether the exercise can be done here: an inclusion always wins, an exclusion always loses,
    /// otherwise the equipment and every fixture it needs must be present.
    public func allows(_ exercise: Exercise) -> Bool {
        if included.contains(exercise.id) { return true }
        if excluded.contains(exercise.id) { return false }
        return equipment.contains(exercise.equipment) && exercise.apparatus.allSatisfy(apparatus.contains)
    }
}
