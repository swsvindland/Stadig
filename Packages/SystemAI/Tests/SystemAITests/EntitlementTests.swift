#if canImport(FoundationModels)
import Synchronization
import Testing

@testable import SystemAI

/// Private Cloud Compute stops an app that lacks Apple's entitlement, so without it the cloud is
/// never asked, let alone used, even with the setting on.
@Suite("Private Cloud Compute entitlement")
struct EntitlementTests {
    @Test @available(macOS 27.0, iOS 27.0, *)
    func theCloudNeedsTheEntitlement() {
        let asked = Mutex(0)
        let up = { () -> Bool in
            asked.withLock { $0 += 1 }
            return true
        }
        #expect(!FoundationBackend.availability(allowCloud: true, entitled: false, cloud: up).privateCloud)
        #expect(asked.withLock { $0 } == 0)
        #expect(FoundationBackend.availability(allowCloud: true, entitled: true, cloud: up).privateCloud)
        #expect(!FoundationBackend.availability(allowCloud: false, entitled: true, cloud: up).privateCloud)
        // The test runner declares nothing, like the apps until Apple grants the entitlement.
        #expect(!SystemAI.privateCloudEntitled)
    }
}
#endif
