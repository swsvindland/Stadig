import Foundation

public struct LifeModeRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var period: LifeModePeriod
    public var updatedAt: Date

    public init(_ period: LifeModePeriod) {
        id = period.id
        self.period = period
        updatedAt = period.updatedAt
    }
}

/// The shared setup answers, kept in each app's own synced store too so another device of the
/// same person gets them even before the shared container is filled there.
public struct ProfileRecord: Codable, Hashable, Sendable, Identifiable {
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000F11E")!

    public var id: UUID
    public var profile: SharedProfile
    public var updatedAt: Date

    public init(_ profile: SharedProfile) {
        id = Self.singletonID
        self.profile = profile
        updatedAt = profile.updatedAt
    }
}
