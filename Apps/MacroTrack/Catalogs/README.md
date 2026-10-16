# Bundled food catalogs

`off.db` (Open Food Facts, about 590 MB) is bundled with the app from this folder but is not in
git. Build it from the Open Food Facts export (about 13 GB to download, then about four minutes to build on a 10-core Mac):

    curl -LO https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz
    curl -LO https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip
    python3 Scripts/build-food-catalog.py --usda FoodData_Central_sr_legacy_food_json_2018-04.zip \
        --off openfoodfacts-products.jsonl.gz

That also rebuilds `usda.db` in `Packages/FoodDatabase` and records both in
`Packages/FoodDatabase/catalog-manifest.json`. For a quick start, `Scripts/install-food-catalogs.sh`
clones an older catalog from `../macro-track` instead; it works, but has no processing or
fermented data. Without either the app still works with the USDA catalog.

Open Food Facts data is under the ODbL: keep the in-app notice, per-food attribution and public
access to the matching database and its build recipe (see `ATTRIBUTION.md` in FoodDatabase).
