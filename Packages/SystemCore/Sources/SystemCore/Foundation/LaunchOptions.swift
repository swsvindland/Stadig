import Foundation

/// How an app was launched, read in one place: by XCTest hosting the app's unit tests, by a UI test
/// (`-uiTesting`), or with the DEBUG launch arguments used to reach a screen quickly (each app's doc
/// lists them). Every app reads the same flags the same way.
public struct LaunchOptions: Sendable {
    public let arguments: [String]
    public let environment: [String: String]

    /// This process's options.
    public static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)

    public init(arguments: [String], environment: [String: String] = [:]) {
        self.arguments = arguments
        self.environment = environment
    }

    /// XCTest loaded the app's unit tests into this process: the app stays out of their way, with
    /// nothing on disk or in iCloud and nothing that prompts.
    public var isHostingTests: Bool { environment["XCTestConfigurationFilePath"] != nil }

    /// A UI test launched the app: an in-memory store, no permission prompts, no animations. DEBUG
    /// builds only, so a shipped app can't be put in this mode.
    public var isUITesting: Bool {
        #if DEBUG
        has("-uiTesting")
        #else
        false
        #endif
    }

    /// Keep nothing between launches: the store lives in memory and never syncs.
    public var usesInMemoryStore: Bool { isHostingTests || isUITesting || has("-inMemoryStore") }

    /// No Health, notification, camera or other permission prompts, and no system services that
    /// would show one.
    public var isQuiet: Bool { isHostingTests || isUITesting }

    /// Whether the flag (such as `-seedSampleData`) was passed.
    public func has(_ flag: String) -> Bool { arguments.contains(flag) }

    /// The argument after a flag, as in `-tab plan`; nil when the flag or its value is missing.
    public func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return value.hasPrefix("-") && Int(value) == nil ? nil : value
    }

    /// The whole number after a flag, as in `-steps 4`.
    public func number(after flag: String) -> Int? { value(after: flag).flatMap { Int($0) } }
}
