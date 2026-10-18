import Testing
@testable import SystemCore

@Suite("Launch options")
struct LaunchOptionsTests {
    @Test func flagsAndValues() {
        let options = LaunchOptions(arguments: ["App", "-seedSampleData", "-tab", "plan", "-steps", "4", "-log"])
        #expect(options.has("-seedSampleData"))
        #expect(!options.has("-resetData"))
        #expect(options.value(after: "-tab") == "plan")
        #expect(options.number(after: "-steps") == 4)
        // A flag with nothing after it, or another flag after it, has no value.
        #expect(options.value(after: "-log") == nil)
        #expect(LaunchOptions(arguments: ["-tab", "-seedSampleData"]).value(after: "-tab") == nil)
        // Negative numbers are values, not flags.
        #expect(LaunchOptions(arguments: ["-offset", "-2"]).number(after: "-offset") == -2)
    }

    @Test func testsKeepEverythingInMemoryAndQuiet() {
        let plain = LaunchOptions(arguments: ["App"])
        #expect(!plain.usesInMemoryStore && !plain.isQuiet && !plain.isHostingTests)

        let memory = LaunchOptions(arguments: ["App", "-inMemoryStore"])
        #expect(memory.usesInMemoryStore && !memory.isQuiet)

        let hosting = LaunchOptions(arguments: ["App"], environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        #expect(hosting.isHostingTests && hosting.usesInMemoryStore && hosting.isQuiet)
    }

    #if DEBUG
    @Test func uiTestsKeepEverythingInMemoryAndQuiet() {
        let ui = LaunchOptions(arguments: ["App", "-uiTesting", "-seedSampleData"])
        #expect(ui.isUITesting && ui.usesInMemoryStore && ui.isQuiet && !ui.isHostingTests)
    }
    #endif
}
