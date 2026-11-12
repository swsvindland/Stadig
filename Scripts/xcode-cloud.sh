#!/bin/zsh
# Usage: Scripts/xcode-cloud.sh post-clone|pre-xcodebuild|post-xcodebuild <App>
# What Xcode Cloud runs around each build; every app's ci_scripts/ci_*.sh is one line calling this.
#   post-clone       fetch the catalogs the app bundles (they aren't in git; needs the CATALOG_TOKEN
#                    secret); the build fails rather than ship without them
#   pre-xcodebuild   before a Test action builds the unit test plan: run the tests of the packages the
#                    app links, so a workflow that tests the app tests its logic too (RUN_PACKAGE_TESTS=0
#                    skips them).
#   post-xcodebuild  after an archive: write TestFlight's "What to Test" from the commits that touched
#                    the app, so every TestFlight build says what changed
# See docs/ci-cd.md for the workflows themselves.
set -euo pipefail
STAGE=$1 APP=$2
ROOT=${CI_PRIMARY_REPOSITORY_PATH:-${0:A:h:h}}
cd $ROOT
PACKAGES=($(python3 Scripts/generate-project.py --packages $APP))

case $STAGE in
  post-clone)
    if grep -q "^Apps/$APP/" Scripts/catalogs.manifest; then
      Scripts/fetch-catalogs.sh Apps/$APP
    fi
    ;;

  pre-xcodebuild)
    action=${CI_XCODEBUILD_ACTION:-}
    # The UI plan's Test action runs on its own machine too; once per build is enough.
    if [[ $action == build-for-testing && ${CI_TEST_PLAN:-} != *UI && ${RUN_PACKAGE_TESTS:-1} != 0 ]]; then
      # Xcode Cloud's Macs are virtual, like GitHub's: no Neural Engine for real Vision OCR.
      NO_VISION_OCR=1 STRICT=1 Scripts/build.sh test $PACKAGES
    fi
    ;;

  post-xcodebuild)
    if [[ -n ${CI_APP_STORE_SIGNED_APP_PATH:-} ]]; then
      notes=Apps/$APP/TestFlight/WhatToTest.en-US.txt
      mkdir -p ${notes:h}
      # Xcode Cloud clones shallowly; a little history is enough for the latest changes.
      git fetch --deepen 30 --quiet 2>/dev/null || true
      {
        print "Build ${CI_BUILD_NUMBER:-?} from ${CI_BRANCH:-${CI_TAG:-unknown}} (${${CI_COMMIT:-unknown}[1,7]})"
        print
        git log -15 --no-merges --pretty='format:- %s' -- Apps/$APP ${PACKAGES/#/Packages/}
      } | head -c 3900 > $notes
    fi
    ;;

  *)
    print -u2 "Unknown stage '$STAGE': choose post-clone, pre-xcodebuild or post-xcodebuild"
    exit 2
    ;;
esac
