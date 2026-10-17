#!/bin/zsh
# Usage: Scripts/publish-catalogs.sh
# Uploads the local catalogs listed in Scripts/catalogs.manifest, gzipped, as a new release on the
# GitHub repo, then rewrites the manifest with that release and each file's SHA-256. Commit the
# manifest afterwards so Xcode Cloud and GitHub Actions fetch the new catalogs. Needs a signed-in gh.
set -euo pipefail
cd "${0:A:h}/.."
REPO=${CATALOG_REPO:-swsvindland/the-system}
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

gh release create $TAG --repo $REPO --target main --latest=false --title "Catalogs $TAG" \
  --notes "The catalogs the apps bundle that aren't in git. Scripts/fetch-catalogs.sh downloads them." $WORK/*.gz
{ grep '^#' $MANIFEST; print "release $TAG"; print -l $lines } > $MANIFEST.new
mv -f $MANIFEST.new $MANIFEST
print "Published $TAG: commit Scripts/catalogs.manifest"
