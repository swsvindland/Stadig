import Foundation

/// A catalog's licence notice, as its `attribution` row has it. The Open Database License asks that
/// the notice say where the source, the licence and the derived database are, and an address shown
/// only as text can't be opened, so Settings lists each one as a link under the notice.
enum CatalogNotice {
    /// The web addresses in a notice, in the order written and once each, named for what they are.
    static func links(in notice: String) -> [CatalogLink] {
        // A detector for links can't fail to be made; if it ever did, the notice still reads as text.
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var links: [CatalogLink] = []
        for match in detector.matches(in: notice, range: NSRange(notice.startIndex..., in: notice)) {
            // The detector also finds email addresses, as mailto.
            guard let range = Range(match.range, in: notice), let found = match.url, let scheme = found.scheme?.lowercased(),
                scheme == "http" || scheme == "https"
            else { continue }
            let written = notice[range]
            // An address written bare ("dsld.od.nih.gov") is read as http.
            let url = written.contains("://") ? found : URL(string: "https://\(written)") ?? found
            guard !links.contains(where: { $0.url == url }) else { continue }
            links.append(CatalogLink(title: title(for: url, after: notice[..<range.lowerBound]), url: url))
        }
        return links
    }

    /// What an address is called: the sources and licences the catalogs name, where a derived
    /// database says it's published, and otherwise the address itself without its scheme.
    private static func title(for url: URL, after lead: Substring) -> String {
        let host = url.host()?.lowercased() ?? ""
        let path = url.path().lowercased()
        if host == "openfoodfacts.org" || host.hasSuffix(".openfoodfacts.org") { return "Open Food Facts" }
        if host == "opendatacommons.org", path.contains("/odbl") { return "Open Database License" }
        if host == "opendatacommons.org", path.contains("/dbcl") { return "Database Contents License" }
        if host == "dsld.od.nih.gov" { return "Dietary Supplement Label Database" }
        if lead.hasSuffix("published at ") { return "This database and how it's built" }
        let address = host + url.path()
        return address.hasSuffix("/") ? String(address.dropLast()) : address
    }
}
