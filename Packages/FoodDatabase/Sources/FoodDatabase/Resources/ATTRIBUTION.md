# Food catalog sources

## USDA — `usda.db`

USDA SR Legacy, April 2018, and from FNDDS 2021–2023 (the Food and Nutrient Database for Dietary
Studies, October 2024) its fast-food and restaurant foods and the foods it files chains' menu items
under, with FNDDS's names for those items; both from
[FoodData Central](https://fdc.nal.usda.gov/download-datasets/). USDA describes its data as
[public domain / CC0](https://fdc.nal.usda.gov/api-guide/).

## Open Food Facts — `off.db`

Contains information from [Open Food Facts](https://world.openfoodfacts.org), which is made available
here under the [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
Individual contents are available under the
[Database Contents License (DbCL) 1.0](https://opendatacommons.org/licenses/dbcl/1-0/).

`off.db` is a derivative database: a filtered, worldwide subset of the full
[Open Food Facts JSONL export](https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz),
downloaded November 6, 2026. It is distributed under the ODbL 1.0, and is publicly offered with
the method that made it:

- `off.db` — the derivative database exactly as the app ships it: the `off.db.gz` asset on the
  [GitHub release](https://github.com/swsvindland/Stadig/releases) that `Scripts/catalogs.manifest`
  names. It's about 600 MB, so it isn't in git.
- `Scripts/build-catalogs.py` with `food_catalog.py` and `food_energy.py` — the complete
  transformation recipe, which rebuilds `off.db` (and `usda.db`) from the source exports.
- `Packages/FoodDatabase/catalog-manifest.json` — source URLs, source and recipe SHA-256 hashes,
  filtering counts and sizes.

Each database also carries its own `license`, `attribution` and `source` rows in `catalog_meta`, so
the notice stays with the file when it is copied out of the app.

No product images are included (Open Food Facts images are under a separate CC BY-SA license). This
is not a verified or comprehensive catalog; only records with a valid barcode, complete core
macros, and an explicit g/ml (or oz/fl oz) basis are included. Stadig Macro is not affiliated
with or endorsed by Open Food Facts.

## What each public release must keep doing (ODbL 4.2, 4.3, 4.6)

1. **Notice in the app.** Settings → _Food data_ names each catalog with its licence and its
   attribution row, and carries the ODbL notice. Under the notice is a row for each address it
   names, which opens it: Open Food Facts, the ODbL, the DbCL, and where this database and its
   recipe are published.
2. **Per-food source.** A packaged food names Open Food Facts as its source where it's logged and
   where its numbers are corrected.
3. **Public access to the derivative.** Keep the `off.db` that matches each shipped build publicly
   reachable, with its recipe: the release above, and the scripts in `Scripts/` at that release's
   tag. `Scripts/publish-catalogs.sh` makes a new release for a new catalog; keep the older releases
   while builds that bundle them are in use. If the repository ever goes private, publish the same
   files elsewhere and update the notices.

   A catalog's own `attribution` row says where it's published (`RECIPE_URL` in
   `Scripts/food_catalog.py`): this repository's releases, for every catalog built since
   2026-11-21. The one in Stadig Macro 1.0 (`catalogs-20261107-0100`) was built before this
   repository was public and names an earlier repository; its foods are the same, row for row, as
   the first catalog built since.
4. **Keep notices intact.** Don't strip `catalog_meta` or this file from redistributed copies.

The personal diary is not part of either catalog. Foods logged from `off.db` into the person's own
diary or Apple Health stay private to them and are not public use of the database.

## Transformations

The builder uses only values printed on the label, not ones Open Food Facts estimates from the
ingredients; it retains source calories unless they disagree with the macros by more than 10% and the
mistake can be named (the label's own kilojoules agree, kilojoules were entered as calories, or a
serving's calories sit beside per-100 values), and marks the rest of such foods as suspect without
changing them; it rejects incomplete core macros and ambiguous portion bases,
converts sodium and micronutrients to their label units (mg or µg), drops micronutrient values above
twice the richest USDA food's (unit slips) or larger than their whole (saturated fat over total fat),
keeps an Open Food Facts zero only for nutrients a US label must list, rounds values to four
significant figures, and never equates a missing nutrient with zero. Nutrition values are estimates;
check product labels for the foods you consume.

Each food also carries a NOVA processing group and a fermented flag. For Open Food Facts these are
the product's own `nova_group` (computed by Open Food Facts from its ingredients) or, without one, the
group nearly every product in one of its categories shares; fermented means a live-cultures label,
a fermented category (yogurt, kefir, kimchi…), live cultures in the ingredients or a fermented food's
name, excluding aged cheese (skyr, quark and fromage blanc count), chocolate, snacks and baked, frozen
or heat-treated products. For USDA both are estimated from
each food's group and name. They guide; they don't certify.

## NIH Dietary Supplement Label Database — `supplements.db`

From the [Dietary Supplement Label Database](https://dsld.od.nih.gov) of the NIH Office of Dietary
Supplements, a US government work in the public domain. Use of the data doesn't suggest endorsement
by the NIH or ODS. `supplements.db` keeps one label per barcode (the one on the market, else the
newest) and labels without one while on the market; it's built by `Scripts/build-catalogs.py`.
