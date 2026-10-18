import Testing

@testable import MealPlanner

/// Private Cloud Compute stops an app that lacks Apple's entitlement, so the request reader turns
/// to it only when the device's model can't answer, the setting allows it, and the app is entitled.
@Suite("The request reader's model")
struct AssistantModelTests {
    @Test func theCloudNeedsTheEntitlement() {
        #expect(PlanAssistant.reader(deviceAvailable: true, allowCloud: true, entitled: true) == .device)
        #expect(PlanAssistant.reader(deviceAvailable: false, allowCloud: true, entitled: true) == .cloud)
        #expect(PlanAssistant.reader(deviceAvailable: false, allowCloud: true, entitled: false) == .words)
        #expect(PlanAssistant.reader(deviceAvailable: false, allowCloud: false, entitled: true) == .words)
        // The test runner declares nothing, like the apps until Apple grants the entitlement.
        #expect(PlanAssistant.reader(deviceAvailable: false, allowCloud: true) == .words)
    }
}
