import FoodDatabase
import SwiftUI

/// Settings' rows under a catalog's notice: each address the notice names, to open in the browser.
/// The notice itself only shows them as text, and the Open Database License asks that the source, the
/// licence and the derived database can be reached from the app.
struct CatalogLinkRows: View {
    let links: [CatalogLink]

    var body: some View {
        ForEach(links) { link in
            Link(destination: link.url) {
                Label(link.title, systemImage: "arrow.up.right")
            }
            .accessibilityIdentifier("settings.foodDataLink")
        }
    }
}
