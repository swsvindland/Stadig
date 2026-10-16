#!/bin/zsh
# Clones the Open Food Facts catalog from the React Native macro-track repo into
# Apps/MacroTrack/Catalogs, where the Macro Track app bundles it. APFS clone: instant, no extra space.
# That catalog predates processing and fermented data; Scripts/build-food-catalog.py builds one with it.
set -eu
cd "${0:A:h}/.."
SOURCE=${1:-../macro-track/assets/food/off.db}
DEST=Apps/MacroTrack/Catalogs/off.db
[[ -f $SOURCE ]] || { print "No catalog at $SOURCE (pass a path, or build one with Scripts/build-food-catalog.py)"; exit 1; }
rm -f $DEST
cp -c $SOURCE $DEST 2>/dev/null || cp $SOURCE $DEST
print "Installed $(du -h $DEST | cut -f1) catalog at $DEST"
