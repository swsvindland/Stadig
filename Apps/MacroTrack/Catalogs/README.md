# Bundled food catalogs

`off.db` (Open Food Facts, about 555 MB) is bundled with the app from this folder but is not in
git. Install it with:

    Scripts/install-food-catalogs.sh

It clones `../macro-track/assets/food/off.db` (an APFS clone: instant, no extra space). Without it
the app still works with the USDA catalog bundled in `Packages/FoodDatabase`.

Open Food Facts data is under the ODbL: keep the in-app notice, per-food attribution and public
access to the matching database and its build recipe (see `ATTRIBUTION.md` in FoodDatabase).
