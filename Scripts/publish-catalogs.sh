#!/bin/zsh
# Usage: Scripts/publish-catalogs.sh
# Uploads the local catalogs listed in Scripts/catalogs.manifest, gzipped, as a new release on the
# GitHub repo, then rewrites the manifest with that release and each file's SHA-256. Commit the
# manifest afterwards so Xcode Cloud and GitHub Actions fetch the new catalogs. Needs a signed-in gh.
#
# The release is how off.db is offered under the ODbL: the file, and as GitHub's source archive at the
# release's tag, the scripts that built it. So the tag has to sit on a commit that holds those scripts:
# main by default, or CATALOG_TARGET (a pushed branch or a commit) when they aren't merged yet.
set -euo pipefail
cd "${0:A:h}/.."
REPO=${CATALOG_REPO:-swsvindland/the-system}
TARGET=${CATALOG_TARGET:-main}
MANIFEST=Scripts/catalogs.manifest
TAG=catalogs-$(date -u +%Y%m%d-%H%M)
WORK=$(mktemp -d)
trap 'rm -rf $WORK' EXIT

lines=()
for file in ${(f)"$(awk '$1 !~ /^#/ && $1 != "release" && NF == 2 { print $1 }' $MANIFEST)"}; do
  [[ -f $file ]] || { print -u2 "No $file: build it first (see the README next to it)"; exit 1 }
  print "Compressing $file"
  lines+=("$file $(shasum -a 256 $file | cut -d' ' -f1)")
  gzip -c $file > $WORK/${file:t}.gz
done

# The notice travels with the files: each catalog also carries it in its own catalog_meta.
cat > $WORK/notes.md <<'NOTES'
The catalogs Stadig Macro bundles that aren't in git. `Scripts/fetch-catalogs.sh` downloads them.

- **`off.db`** contains information from [Open Food Facts](https://world.openfoodfacts.org), made available here under the [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Individual contents are under the [Database Contents License (DbCL) 1.0](https://opendatacommons.org/licenses/dbcl/1-0/). It's a derivative database: a filtered subset of the Open Food Facts export, built by the scripts in `Scripts/` at this tag. The file carries its own licence, attribution and source rows in `catalog_meta`.
- **`supplements.db`** is from the NIH Office of Dietary Supplements' [Dietary Supplement Label Database](https://dsld.od.nih.gov), a US government work in the public domain. Use of the data doesn't suggest endorsement by the NIH or ODS.

Neither file is covered by the repository's GPL-3.0 licence, which is for the code.
NOTES
gh release create $TAG --repo $REPO --target $TARGET --latest=false --title "Catalogs $TAG" --notes-file $WORK/notes.md $WORK/*.gz
{ grep '^#' $MANIFEST; print "release $TAG"; print -l $lines } > $MANIFEST.new
mv -f $MANIFEST.new $MANIFEST
print "Published $TAG: commit Scripts/catalogs.manifest"
