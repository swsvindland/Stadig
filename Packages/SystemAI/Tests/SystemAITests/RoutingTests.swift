import Foundation
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
