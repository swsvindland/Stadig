import ExerciseLibrary
import Foundation
import SystemCore

/// One thing done on the Watch to a session the iPhone runs. The Watch makes the change to its own
/// copy at once and numbers it; it sends every change the phone hasn't taken yet, in order, and the
/// phone takes them in that order, each once, and sends the session back. Items go by id, since "Do
/// This Now" on either device reorders them; sets go by their place in the item, since adding a set
/// or swapping an exercise makes new sets on each device separately.
public struct SessionChange: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case log(item: UUID, set: Int, reps: Int, loadKg: Double?, rating: SetRating?, seconds: Int?, heartRatePeak: Double?)
        case skipSet(item: UUID, set: Int)
        case skip(item: UUID)
        case addSet(item: UUID)
        /// "Do This Now": the item goes next, and the rest running ends.
        case doNext(item: UUID)
        case swap(item: UUID, to: String)
        case endRest
        case extendRest(seconds: Int)
        case logConditioning(item: UUID, minutes: Int, averageHeartRate: Double?, zoneMinutes: [Int: Double])
    }

    public var kind: Kind
    /// The session it was made to.
    public var session: UUID
    /// Its place among the changes the Watch made to this session, from 1.
    public var sequence: Int
    /// When it was done, by the Watch's clock.
    public var date: Date

    public init(_ kind: Kind, session: UUID, sequence: Int, date: Date) {
        self.kind = kind
        self.session = session
        self.sequence = sequence
        self.date = date
    }
}

extension LiveSession {
    /// Makes a change on the device it's made on. Returns false, changing nothing, when what it names
    /// is gone or there's nothing for it to do (no rest to end, an exercise already done). Logging a set
    /// that's already logged (both devices logged it) corrects it instead, so its adjustment isn't made twice.
    @discardableResult
    public mutating func apply(_ kind: SessionChange.Kind, environment: SessionEnvironment, now: Date = Date()) -> Bool {
        switch kind {
        case .log(let id, let set, let reps, let loadKg, let rating, let seconds, let peak):
            guard let index = item(id), items[index].sets.indices.contains(set) else { return false }
            if items[index].sets[set].logged != nil {
                edit(item: index, set: set, reps: reps, loadKg: loadKg, rating: rating, environment: environment, now: now)
            } else {
                items[index].sets[set].skipped = false
                log(
                    item: index, set: set, reps: reps, loadKg: loadKg, rating: rating, seconds: seconds, heartRatePeak: peak,
                    environment: environment, now: now)
            }
            // Undo is for the device the set was logged on: the phone doesn't take back the Watch's
            // set (the Watch, still showing it logged until a copy says otherwise, would log on from
            // it), and a set logged on the Watch is the next set, so the phone's last one stays put.
            undo = nil
        case .skipSet(let id, let set):
            guard let index = item(id), items[index].sets.indices.contains(set), items[index].sets[set].isOpen else { return false }
            skipSet(item: index, set: set, now: now)
        case .skip(let id):
            guard let index = item(id), !items[index].isDone else { return false }
            skip(item: index, now: now)
        case .addSet(let id):
            guard let index = item(id), items[index].takesMoreSets else { return false }
            addSet(item: index, now: now)
        case .doNext(let id):
            guard let index = item(id), !items[index].isDone else { return false }
            doNext(item: index, now: now)
            endRest(now: now)
        case .swap(let id, let exerciseID):
            guard let index = item(id), let exercise = environment.catalog[exerciseID], items[index].exerciseID != exerciseID else { return false }
            swap(item: index, to: exercise, environment: environment, now: now)
        case .endRest:
            guard rest != nil else { return false }
            endRest(now: now)
        case .extendRest(let seconds):
            guard rest != nil else { return false }
            extendRest(by: seconds, now: now)
        case .logConditioning(let id, let minutes, let average, let zoneMinutes):
            guard let index = item(id) else { return false }
            logConditioning(item: index, minutes: minutes, averageHeartRate: average, zoneMinutes: zoneMinutes, now: now)
        }
        return true
    }

    /// Takes a change the Watch made, in the Watch's order: only the next one. One already taken, one
    /// made to another session, or one ahead of a change still on its way does nothing and returns
    /// false; the Watch sends every change not yet taken, in order, so the missing one comes. A change
    /// whose item or set is gone is taken all the same, changing nothing, so the ones after it can be.
    @discardableResult
    public mutating func take(_ change: SessionChange, environment: SessionEnvironment) -> Bool {
        guard change.session == id, change.sequence == takenChanges + 1 else { return false }
        takenChanges = change.sequence
        apply(change.kind, environment: environment, now: change.date)
        return true
    }

    /// Where an item is in the session now.
    public func item(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    /// The session as it's sent to the other device: without the heart rate, which the Watch
    /// measures and keeps itself, and which would make every message thousands of readings long;
    /// and without Undo, which only the device that logged the set offers. An undo there reaches
    /// the other device as any change does, in the next copy.
    public var withoutHeartRate: LiveSession {
        var copy = self
        copy.heartRateSamples = []
        copy.undo = nil
        return copy
    }
}

/// The Watch's copy of a session the iPhone runs. What it shows is the phone's latest copy with the
/// changes made on the Watch that the phone hasn't taken yet made on top, so a set logged on the
/// Watch stays logged while a copy the phone sent before it is still on its way. A copy older than
/// the one held (by the phone's clock) is dropped, since copies can arrive out of order.
public struct MirroredSession: Sendable {
    /// What the Watch shows and logs into.
    public private(set) var session: LiveSession
    /// Changes made here the phone hasn't taken yet, in order: all of them go each time, until it has.
    public private(set) var pending: [SessionChange] = []
    /// When the phone sent the copy this is built on.
    public private(set) var sentAt: Date

    /// Built on a copy from the phone, so the Watch's changes are numbered on from those the phone has
    /// already taken (the Watch app may have been restarted since it made them).
    public init(_ session: LiveSession, sentAt: Date) {
        self.session = session
        self.sentAt = sentAt
    }

    /// Makes a change here, numbered next, to be sent to the phone. Returns it, or nil when it changed
    /// nothing, which needn't be sent (and so takes no number).
    public mutating func make(_ kind: SessionChange.Kind, environment: SessionEnvironment, now: Date = Date()) -> SessionChange? {
        var next = session
        guard next.apply(kind, environment: environment, now: now) else { return nil }
        next.takenChanges += 1
        let change = SessionChange(kind, session: session.id, sequence: next.takenChanges, date: now)
        session = next
        pending.append(change)
        return change
    }

    /// A copy from the phone: shown, with what's still pending made on top. The heart rate measured
    /// here stays, since the phone sends none. Returns false for a copy older than the one held, or
    /// one of another session (that's a new session, not a copy of this one).
    @discardableResult
    public mutating func receive(_ copy: LiveSession, sentAt: Date, environment: SessionEnvironment) -> Bool {
        guard copy.id == session.id, sentAt > self.sentAt else { return false }
        self.sentAt = sentAt
        pending.removeAll { $0.sequence <= copy.takenChanges }
        var shown = copy
        shown.heartRateSamples = session.heartRateSamples
        for change in pending { shown.take(change, environment: environment) }
        session = shown
        return true
    }

    /// A reading from the Watch's own sensor, for zone minutes and the like. The phone decides what
    /// heart rate ends, from the readings the Watch sends it.
    public mutating func record(heartRate bpm: Double, zones: HeartRateZones, now: Date = Date()) {
        session.record(heartRate: bpm, zones: zones, now: now)
    }
}
