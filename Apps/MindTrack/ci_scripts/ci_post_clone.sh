#!/bin/zsh
# Xcode Cloud runs this after cloning. The catalogs this app bundles aren't in git, so fetch them
# from the release named in Scripts/catalogs.manifest; the build fails rather than ship without them.
# Needs the workflow's secret CATALOG_TOKEN (a token that can read this repo's releases).
set -eu
"${CI_PRIMARY_REPOSITORY_PATH:-${0:A:h}/../../..}/Scripts/fetch-catalogs.sh" Apps/MindTrack
