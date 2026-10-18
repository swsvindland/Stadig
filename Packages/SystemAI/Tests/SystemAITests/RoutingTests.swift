import Foundation
import Synchronization
import Testing
@testable import SystemAI

@Suite("AI routing")
struct RoutingTests {
    @Test("light jobs stay on the device; heavy ones prefer Private Cloud Compute when it's allowed")
    func engines() {
        let both = AIAvailability(onDevice: true, privateCloud: true)
        #expect(AIRouting.engine(.light, in: both) == .onDevice)
        #expect(AIRouting.engine(.heavy, in: both) == .privateCloud)
        let device = AIAvailability(onDevice: true, privateCloud: false)
        #expect(AIRouting.engine(.heavy, in: device) == .onDevice)
        let cloud = AIAvailability(onDevice: false, privateCloud: true)
        #expect(AIRouting.engine(.light, in: cloud) == .privateCloud)
        #expect(AIRouting.engine(.light, in: AIAvailability(onDevice: false, privateCloud: false, reason: "No")) == nil)
    }

    @Test("a failure falls back to the other engine only when it might succeed")
    func fallbacks() {
        let both = AIAvailability(onDevice: true, privateCloud: true)
        #expect(AIRouting.fallback(after: .network, from: .privateCloud, in: both) == .onDevice)
        #expect(AIRouting.fallback(after: .quotaReached(nil), from: .privateCloud, in: both) == .onDevice)
        #expect(AIRouting.fallback(after: .tooLong, from: .onDevice, in: both) == .privateCloud)
        #expect(AIRouting.fallback(after: .refused, from: .onDevice, in: both) == nil, "a refusal isn't retried elsewhere")
        #expect(AIRouting.fallback(after: .network, from: .privateCloud, in: AIAvailability(onDevice: false, privateCloud: true)) == nil)
    }

    @Test("every failure has words for the person")
    func messages() {
        for error in [AIError.busy, .network, .quotaReached(nil), .tooLong, .refused, .unavailable("x"), .failed("y")] {
            #expect(!error.message.isEmpty)
        }
    }
}

/// Time-limited: before each engine was capped at one try, two failing engines looped forever.
@Suite("Answering with fallbacks", .timeLimit(.minutes(1)))
struct RespondTests {
    static let both = AIAvailability(onDevice: true, privateCloud: true)

    @Test("when both engines fail, each is asked once and the second's error is thrown")
    func bothFailing() async {
        let log = CallLog()
        let ai = SystemAI(allowCloud: true, availability: always(Self.both)) { engine, _, _, _ in
            log.append(engine)
            throw engine == .privateCloud ? AIError.network : AIError.tooLong
        }
        await #expect(throws: AIError.tooLong) {
            try await ai.respond(instructions: "", prompt: "A long piece", weight: .heavy)
        }
        #expect(log.calls.withLock { $0 } == [.privateCloud, .onDevice])

        let failing = CallLog()
        let alwaysFailed = SystemAI(allowCloud: true, availability: always(Self.both)) { engine, _, _, _ in
            failing.append(engine)
            throw AIError.failed("Nope")
        }
        await #expect(throws: AIError.failed("Nope")) {
            try await alwaysFailed.respond(instructions: "", prompt: "Notes", weight: .light)
        }
        #expect(failing.calls.withLock { $0 } == [.onDevice, .privateCloud])
    }

    @Test("a failure the other engine might not share falls back once and returns its answer")
    func fallbackAnswers() async throws {
        let log = CallLog()
        let ai = SystemAI(allowCloud: true, availability: always(Self.both)) { engine, _, prompt, _ in
            log.append(engine)
            if engine == .privateCloud { throw AIError.quotaReached(nil) }
            return "Device: \(prompt)"
        }
        #expect(try await ai.respond(instructions: "", prompt: "Compare", weight: .heavy) == "Device: Compare")
        #expect(log.calls.withLock { $0 } == [.privateCloud, .onDevice])
    }

    @Test("a refusal isn't retried, and nothing available says why")
    func refusalAndUnavailable() async {
        let log = CallLog()
        let ai = SystemAI(allowCloud: true, availability: always(Self.both)) { engine, _, _, _ in
            log.append(engine)
            throw AIError.refused
        }
        await #expect(throws: AIError.refused) { try await ai.respond(instructions: "", prompt: "", weight: .light) }
        #expect(log.calls.withLock { $0 } == [.onDevice])

        let off = AIAvailability(onDevice: false, privateCloud: false, reason: "Off")
        let none = SystemAI(allowCloud: false, availability: always(off)) { _, _, _, _ in
            Issue.record("nothing should be asked")
            return ""
        }
        await #expect(throws: AIError.unavailable("Off")) { try await none.respond(instructions: "", prompt: "", weight: .heavy) }
    }

    @Test("a cancelled request stops instead of falling back")
    func cancellation() async {
        let log = CallLog()
        let ai = SystemAI(allowCloud: true, availability: always(Self.both)) { engine, _, _, _ in
            log.append(engine)
            withUnsafeCurrentTask { $0?.cancel() }
            throw AIError.busy
        }
        // Its own task, cancelled from inside the first request.
        let request = Task { try await ai.respond(instructions: "", prompt: "", weight: .heavy) }
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(log.calls.withLock { $0 } == [.privateCloud])
    }
}

/// The engines a test's SystemAI asked, in order.
final class CallLog: Sendable {
    let calls = Mutex<[AIEngine]>([])

    func append(_ engine: AIEngine) { calls.withLock { $0.append(engine) } }
}

/// Availability that never changes, for a test's SystemAI.
func always(_ availability: AIAvailability) -> @Sendable (Bool) -> AIAvailability {
    { _ in availability }
}
