import Foundation
import ExerciseLibrary
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
    public var sentAt: Date

    public init(plan: SessionPlan?, upNext: String?, gym: Gym, trust: TrustState, phase: PhaseEffects, bodyweightKg: Double?,
                history: [String: [LoggedSet]], enduranceScore: Double?, heartRateGuidedRest: Bool, zones: HeartRateZones,
                units: UnitPreference, sentAt: Date = Date()) {
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
        self.sentAt = sentAt
    }

    public func environment(catalog: ExerciseCatalog) -> SessionEnvironment {
        SessionEnvironment(catalog: catalog, gym: gym, trust: trust, phase: phase, bodyweightKg: bodyweightKg, history: history,
                           enduranceScore: enduranceScore, heartRateGuidedRest: heartRateGuidedRest)
    }
}

/// Messages between the Watch and the iPhone.
public enum LinkMessage: Codable, Sendable {
    /// A session finished on the Watch, for the phone to keep.
    case finished(SessionRecord)
    /// The phone asks for a fresh context to be sent (or the Watch asks the phone).
    case requestContext
}
