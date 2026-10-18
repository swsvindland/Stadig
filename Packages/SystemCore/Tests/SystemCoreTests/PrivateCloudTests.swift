import Testing

@testable import SystemCore

/// Private Cloud Compute stops an app that hasn't been granted its entitlement, so it's off unless
/// the app's Info.plist says otherwise.
@Suite("Private Cloud Compute")
struct PrivateCloudTests {
    @Test func offUnlessTheAppDeclaresTheEntitlement() {
        #expect(!PrivateCloud.isEntitled(nil))
        #expect(!PrivateCloud.isEntitled([:]))
        #expect(!PrivateCloud.isEntitled(["SystemAIPrivateCloud": false]))
        #expect(!PrivateCloud.isEntitled(["SystemAIPrivateCloud": "YES"]), "a string isn't a declaration")
        #expect(PrivateCloud.isEntitled(["SystemAIPrivateCloud": true]))
        // The test runner declares nothing, like the apps until Apple grants the entitlement.
        #expect(!PrivateCloud.isEntitled)
    }
}
