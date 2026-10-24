import ExerciseLibrary
import Foundation
import SystemCore

/// What the iPhone keeps the Watch up to date with, so the Watch can run today's session on its
/// own (phone in a locker): the plan, the gym's loads, and enough history to adjust sets.
public struct PhoneContext: Codable, Hashable, Sendable {
    public var plan: SessionPlan?
    /// The session after `plan` in the program, for when the Watch has done `plan` and hasn't heard
    /// from the phone since (it was left at home): the Watch carries on with the program.
    public var following: SessionPlan?
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
    /// Injuries in force and exercises set aside, so a swap on the Watch offers what the phone's would.
    public var injuries: [Injury]?
    public var avoid: Set<String>?
    public var sentAt: Date

    public init(
        plan: SessionPlan?, upNext: String?, gym: Gym, trust: TrustState, phase: PhaseEffects, bodyweightKg: Double?,
        history: [String: [LoggedSet]], enduranceScore: Double?, heartRateGuidedRest: Bool, zones: HeartRateZones,
        units: UnitPreference, startingLoads: [String: Double]? = nil, following: SessionPlan? = nil, sentAt: Date = Date()
    ) {
        self.plan = plan
        self.following = following
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

    /// What an exercise could be swapped for in this gym, as the phone's session offers it: none that
    /// an injury rules out or the person set aside, closest first.
    public func swaps(for exercise: Exercise, catalog: ExerciseCatalog, limit: Int = 12) -> [Exercise] {
        Substitutions.candidates(
            for: exercise, in: catalog.all, availability: gym.availability, injuries: injuries ?? [], avoid: avoid ?? [], limit: limit)
    }
}

/// What the Watch and the iPhone say while the phone runs the session: the Watch measures heart rate
/// and logs into the phone's session, and the phone sends the session back after every change. Most
/// messages go by both routes there are (the mirrored workout, and WatchConnectivity while the other
/// side is reachable) and none is waited on, since a send over a workout can hang: the Watch's
/// changes are numbered and taken once, in order, and the Watch drops a copy older than the one it has.
public enum MirrorMessage: Codable, Sendable {
    /// A reading, Watch to phone.
    case heartRate(bpm: Double, date: Date)
    /// Phone to Watch: the session is over: save the workout under the session's id.
    case finish(id: UUID, title: String)
    /// Phone to Watch: throw the workout away. The session was thrown away, or `saved` without the
    /// Watch's workout (Save to Health is off, or the phone saved the workout itself).
    case discard(id: UUID, saved: Bool)
    /// Watch to phone: the Watch is ready to show the session, and asks for it.
    case join
    /// Phone to Watch: the session as it stands, without its heart rate, stamped by the phone's clock.
    /// The context (the gym, loads and zones) comes with the first one after the Watch joins.
    case session(LiveSession, context: PhoneContext?, sentAt: Date)
    /// Watch to phone: every change made on the Watch the phone hasn't taken yet, oldest first.
    case changes([SessionChange])
    /// Watch to phone: the person ended the session on the Watch; save it with this feedback.
    case finishFromWatch(id: UUID, feedback: SessionFeedback?)
    /// Watch to phone: the person threw the session away on the Watch.
    case discardFromWatch(id: UUID)

    /// The message as it goes over the link: JSON, compressed when that's worth it (a session runs to
    /// tens of kilobytes and goes again after every set, while a reading is a few dozen bytes).
    public func encoded() -> Data? {
        guard let json = try? JSONEncoder().encode(self) else { return nil }
        return json.count > 1024 ? LinkData.compressed(json) : json
    }

    /// A message from the link, compressed or not; nil for anything else, or one from a build that
    /// says things this one doesn't.
    public init?(encoded data: Data) {
        guard let message = LinkData.decode(MirrorMessage.self, from: data, with: JSONDecoder()) else { return nil }
        self = message
    }
}

/// zlib for what goes between the phone and the Watch: a session copy, the day's context.
public enum LinkData {
    public static func compressed(_ data: Data) -> Data {
        (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
    }

    /// The value from data compressed or not. Plain JSON can happen to inflate into something, so
    /// it's read as plain whenever the inflated bytes don't decode.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data, with decoder: JSONDecoder) -> T? {
        if let inflated = try? (data as NSData).decompressed(using: .zlib) as Data, let value = try? decoder.decode(type, from: inflated) {
            return value
        }
        return try? decoder.decode(type, from: data)
    }
}

/// Messages between the Watch and the iPhone.
public enum LinkMessage: Codable, Sendable {
    /// A session finished on the Watch, for the phone to keep.
    case finished(SessionRecord)
    /// The phone asks for a fresh context to be sent (or the Watch asks the phone).
    case requestContext
}
