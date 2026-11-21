import Foundation
import Testing

@testable import FoodDatabase

@Suite("Catalog notices")
struct CatalogNoticeTests {
    /// The notice `Scripts/food_catalog.py` writes into `off.db`, with where this repository publishes it.
    static let openFoodFacts =
        "Contains information from Open Food Facts (https://world.openfoodfacts.org), which is made available here under the Open Database "
        + "License (ODbL) 1.0 (https://opendatacommons.org/licenses/odbl/1-0/). Individual contents are available under the Database "
        + "Contents License (https://opendatacommons.org/licenses/dbcl/1-0/). This derived database and the recipe that builds it are "
        + "published at https://github.com/swsvindland/the-system/releases."

    @Test func theOpenFoodFactsNoticeLinksItsSourceItsLicencesAndWhereItsPublished() {
        let links = CatalogNotice.links(in: Self.openFoodFacts)
        #expect(links.map(\.title) == ["Open Food Facts", "Open Database License", "Database Contents License", "This database and how it's built"])
        // As written: the brackets and the sentence's full stop aren't part of an address.
        #expect(
            links.map(\.url.absoluteString) == [
                "https://world.openfoodfacts.org", "https://opendatacommons.org/licenses/odbl/1-0/",
                "https://opendatacommons.org/licenses/dbcl/1-0/", "https://github.com/swsvindland/the-system/releases",
            ])
    }

    @Test func aNoticeWithoutAddressesHasNoLinks() {
        let usda =
            "USDA FoodData Central: SR Legacy (April 2018), and the fast-food and restaurant foods of FNDDS 2021-2023 (October 2024). "
            + "Public domain (CC0 1.0)."
        #expect(CatalogNotice.links(in: usda).isEmpty)
        #expect(CatalogNotice.links(in: "").isEmpty)
    }

    @Test func anAddressWrittenWithoutASchemeOpensOverHTTPS() {
        let nih = "NIH Office of Dietary Supplements, Dietary Supplement Label Database (dsld.od.nih.gov)"
        let links = CatalogNotice.links(in: nih)
        #expect(links.map(\.title) == ["Dietary Supplement Label Database"])
        #expect(links.map(\.url.absoluteString) == ["https://dsld.od.nih.gov"])
    }

    @Test func anAddressItDoesntKnowIsNamedByWhereItGoes() {
        let links = CatalogNotice.links(in: "From the Example Food Board, https://data.example.org/foods/. Thanks to them.")
        #expect(links.map(\.title) == ["data.example.org/foods"])
        #expect(links.map(\.url.absoluteString) == ["https://data.example.org/foods/"])
    }

    @Test func whereADerivedDatabaseIsPublishedIsNamedWhereverThatIs() {
        // The catalog in Stadig Macro 1.0 names an earlier repository.
        let links = CatalogNotice.links(in: "It and its recipe are published at https://github.com/swsvindland/macro-track/tree/main/assets/food.")
        #expect(links.map(\.title) == ["This database and how it's built"])
        #expect(links.first?.url.absoluteString == "https://github.com/swsvindland/macro-track/tree/main/assets/food")
    }

    @Test func anAddressIsListedOnceAndEmailIsNotALink() {
        let notice = "See https://world.openfoodfacts.org and, again, https://world.openfoodfacts.org. Write to someone@example.com."
        #expect(CatalogNotice.links(in: notice).map(\.url.absoluteString) == ["https://world.openfoodfacts.org"])
    }
}
