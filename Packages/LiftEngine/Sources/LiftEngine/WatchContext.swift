import ExerciseLibrary
import Foundation
import SystemCore

/// What the iPhone keeps the Watch up to date with, so the Watch can run today's session on its
/// own (phone in a locker): the plan, the gym's loads, and enough history to adjust sets.
public struct PhoneContext: Codable, Hashable, Sendable {
    public var plan: SessionPlan?
    /// "Upper A on Thursday", when today isn't a training day.
    public var upNext: String?
    public var gym: Gym
    public var trust: TrustState
    public var phase: PhaseEffects
    public var bodyweightKg: Double?
    /// Recent sets for the plan's exercises (and their likely swaps), oldest first.
    public var history: [String: [LoggedSet]]
    public var enduranceScore: Double?
    public var heartRateGuidedRest: Bool
    public var zones: HeartRateZones
    public var units: UnitPreference
    /// A first guess at the working weight for exercises with no history, kg by exercise id.
    public var startingLoads: [String: Double]?
    public var sentAt: Date

    public init(
        plan: SessionPlan?, upNext: String?, gym: Gym, trust: TrustState, phase: PhaseEffects, bodyweightKg: Double?,
        history: [String: [LoggedSet]], enduranceScore: Double?, heartRateGuidedRest: Bool, zones: HeartRateZones,
        units: UnitPreference, startingLoads: [String: Double]? = nil, sentAt: Date = Date()
    ) {
        self.plan = plan
        self.upNext = upNext
        self.gym = gym
        self.trust = trust
        self.phase = phase
        self.bodyweightKg = bodyweightKg
        self.history = history
        self.enduranceScore = enduranceScore
        self.heartRateGuidedRest = heartRateGuidedRest
        self.zones = zones
        self.units = units
        self.startingLoads = startingLoads
        self.sentAt = sentAt
    }

    public func environment(catalog: ExerciseCatalog) -> SessionEnvironment {
        SessionEnvironment(
            catalog: catalog, gym: gym, trust: trust, phase: phase, bodyweightKg: bodyweightKg, history: history,
            enduranceScore: enduranceScore, heartRateGuidedRest: heartRateGuidedRest)
    }
}

/// What the Watch and the iPhone say over a mirrored workout, while the phone runs the session
/// and the Watch only measures heart rate.
public enum MirrorMessage: Codable, Sendable {
    /// A reading, Watch to phone.
    case heartRate(bpm: Double, date: Date)
    /// The phone's session is over: save the workout under the session's id.
    case finish(id: UUID, title: String)
    /// The phone's session was thrown away: so is the workout.
    case discard
}

/// Messages between the Watch and the iPhone.
public enum LinkMessage: Codable, Sendable {
    /// A session finished on the Watch, for the phone to keep.
    case finished(SessionRecord)
    /// The phone asks for a fresh context to be sent (or the Watch asks the phone).
    case requestContext
}
