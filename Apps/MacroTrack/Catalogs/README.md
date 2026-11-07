# Bundled food catalogs

`off.db` (Open Food Facts, about 590 MB) is bundled with the app from this folder but is not in
git. Build it from the Open Food Facts export (about 13 GB to download, then about four minutes to build on a 10-core Mac):

    curl -LO https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz
    curl -LO https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip
    curl -LO https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip
    python3 Scripts/build-food-catalog.py --usda FoodData_Central_sr_legacy_food_json_2018-04.zip \
        --fndds FoodData_Central_survey_food_json_2024-10-31.zip --off openfoodfacts-products.jsonl.gz

That also rebuilds `usda.db` in `Packages/FoodDatabase` (SR Legacy, plus FNDDS's fast-food and
restaurant foods) and records both in `Packages/FoodDatabase/catalog-manifest.json`. Leave out
`--off` to rebuild only `usda.db` (about 17 MB to download, seconds to build), or `--usda` and `--fndds`
to rebuild only `off.db`. For a quick start, `Scripts/install-food-catalogs.sh`
clones an older catalog from `../macro-track` instead; it works, but has no processing or
fermented data. Without either the app still works with the USDA catalog.

The build repairs Open Food Facts calories only where the mistake can be named, and marks the other
foods more than 10% from their macros as suspect (`Scripts/food_energy.py`). Check a built catalog,
and list what doesn't add up, with:

    python3 Scripts/validate-food-catalog.py --report calories.csv

Open Food Facts data is under the ODbL: keep the in-app notice, per-food attribution and public
access to the matching database and its build recipe (see `ATTRIBUTION.md` in FoodDatabase).

`supplements.db` (the NIH Dietary Supplement Label Database, about 43 MB, public domain) is bundled
from here too and isn't in git either. Build it with:

    python3 Scripts/build-supplement-catalog.py

That downloads the database's CSV export once (about 90 MB, cached in
`~/Library/Caches/SystemFoodCatalog/dsld`) and builds in about ten seconds. Without it the app still
works: supplements are added from a photo of the label or typed in.
