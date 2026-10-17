#!/bin/zsh
# Usage: Scripts/fetch-catalogs.sh [Apps/MacroTrack ...]
# Downloads the catalogs in Scripts/catalogs.manifest that are missing or out of date from the GitHub
# release it names, and checks each against its SHA-256. With folders, only the catalogs under them.
# Reading the release needs a token: CATALOG_TOKEN (the Xcode Cloud secret), GH_TOKEN or GITHUB_TOKEN
# (GitHub Actions), or else a signed-in gh.
set -euo pipefail
cd "${0:A:h}/.."
REPO=${CATALOG_REPO:-swsvindland/the-system}
MANIFEST=Scripts/catalogs.manifest
API=https://api.github.com/repos/$REPO

wanted=()
while read -r file sum; do
  [[ -z $file || $file == \#* || $file == release ]] && continue
  if (( $# )); then
    keep=0
    for folder in "$@"; do [[ $file == ${folder%/}/* ]] && keep=1; done
    (( keep )) || continue
  fi
  if [[ -f $file && $(shasum -a 256 $file | cut -d' ' -f1) == $sum ]]; then
    print "$file is up to date"
  else
    wanted+=("$file $sum")
  fi
done < $MANIFEST
(( ${#wanted} )) || exit 0

tag=$(awk '$1 == "release" { print $2 }' $MANIFEST)
[[ $tag != catalogs-unpublished ]] || { print -u2 "The catalogs haven't been published yet: run Scripts/publish-catalogs.sh"; exit 1 }
token=${CATALOG_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}
[[ -n $token ]] || token=$(gh auth token 2>/dev/null) || true
[[ -n $token ]] || { print -u2 "No token to read $REPO's releases: set CATALOG_TOKEN or sign in with gh"; exit 1 }

release=$(curl -fsSL --retry 3 -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" $API/releases/tags/$tag)
for entry in $wanted; do
  file=${entry% *} sum=${entry##* } asset=${${entry% *}:t}.gz
  id=$(print -r -- $release | jq -r --arg name $asset '.assets[] | select(.name == $name) | .id')
  [[ -n $id ]] || { print -u2 "Release $tag has no $asset"; exit 1 }
  print "Downloading $asset from $tag"
  mkdir -p ${file:h}
  # curl drops the Authorization header when GitHub redirects to its storage host, as that host wants.
  curl -fsSL --retry 3 -H "Authorization: Bearer $token" -H "Accept: application/octet-stream" \
    $API/releases/assets/$id | gunzip -c > $file.part
  got=$(shasum -a 256 $file.part | cut -d' ' -f1)
  [[ $got == $sum ]] || { rm -f $file.part; print -u2 "$file came down with SHA-256 $got, not $sum"; exit 1 }
  mv -f $file.part $file
  print "Installed $file ($(du -h $file | cut -f1))"
done
