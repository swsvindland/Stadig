# Bundled food catalogs

`Scripts/build-catalogs.py` builds all of Stadig Macro's catalogs. `off.db` (Open Food Facts, about
600 MB) and `supplements.db` (the NIH Dietary Supplement Label Database, about 43 MB, public domain)
are bundled from this folder but aren't in git. `usda.db` (SR Legacy, plus FNDDS's fast-food and
restaurant foods, its drinks, its dishes and its sweets and snacks) is in `Packages/FoodDatabase`,
in git.

    python3 Scripts/build-catalogs.py update              # what's newer upstream
    python3 Scripts/build-catalogs.py update --download   # fetch it (Open Food Facts is about 13 GB)
    python3 Scripts/build-catalogs.py build               # all three, about four minutes on a 10-core Mac
    python3 Scripts/build-catalogs.py build usda          # or some: usda, off, supplements

Sources are cached in `~/Library/Caches/SystemFoodCatalog`, and `--usda`, `--fndds`, `--off` and
`--dsld` build from another file. Each food catalog is checked before it replaces the old one, and
`Packages/FoodDatabase/catalog-manifest.json` records every catalog's sources, hashes and counts.
`--output DIR` builds elsewhere and leaves all of that alone, to compare a change against what's
installed. After changing `off.db` or `supplements.db`, run `Scripts/publish-catalogs.sh` and commit
the manifest it rewrites, or CI and Xcode Cloud keep fetching the old ones.

For a quick start, `Scripts/fetch-catalogs.sh` downloads the published catalogs. Without them the app
still works, with the USDA catalog, and supplements are added from a photo of the label or typed in.

The build repairs Open Food Facts calories only where the mistake can be named, and marks other foods
more than 10% from their macros as suspect, in any source (`Scripts/food_energy.py`). USDA's numbers
are never changed. Check a built catalog, and list what doesn't add up, with:

    python3 Scripts/build-catalogs.py validate --report calories.csv

Open Food Facts data is under the ODbL: keep the in-app notice, per-food attribution and public
access to the matching database and its build recipe (see `ATTRIBUTION.md` in FoodDatabase).
