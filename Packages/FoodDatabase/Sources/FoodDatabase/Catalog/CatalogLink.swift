import Foundation

/// An address from a catalog's licence notice, with the name Settings shows for it.
public struct CatalogLink: Hashable, Sendable, Identifiable {
    public var title: String
    public var url: URL

    public var id: URL { url }

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}
