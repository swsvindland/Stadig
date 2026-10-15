#!/bin/zsh
# Usage: Scripts/build.sh [test|ios|watch|all]
#   test   swift test for every package
#   ios    the iPhone/iPad app with its widgets and Watch app (iPhone 18 Pro simulator)
#   watch  the Watch app and its complications (generic watchOS simulator)
#   all    everything above
# Builds into a throwaway DerivedData and prints only errors and warnings.
set -u
cd "${0:A:h}/.."
WHAT=${1:-all}
DD=${DERIVED_DATA:-/tmp/lifttrack-dd}
STATUS=0

run_tests() {
  for pkg in SystemCore ExerciseLibrary SystemStore HealthBridge LiftEngine; do
    print "== $pkg"
    (cd Packages/$pkg && swift test 2>&1 | grep -E "error:|warning:|recorded an issue|Test run with") || true
  done
}

build() {
  local scheme=$1 dest=$2
  print "== $scheme"
  xcodebuild -project Apps/LiftTrack/LiftTrack.xcodeproj -scheme $scheme -destination "$dest" -derivedDataPath "$DD" build > "$DD-$scheme.log" 2>&1 || STATUS=1
  grep -E "^/.*(error|warning):" "$DD-$scheme.log" | sort -u
  grep -E "\*\* BUILD" "$DD-$scheme.log"
}

case $WHAT in
  test) run_tests ;;
  ios) build LiftTrack 'platform=iOS Simulator,name=iPhone 18 Pro' ;;
  watch) build LiftTrackWatch 'generic/platform=watchOS Simulator' ;;
  all) run_tests; build LiftTrack 'platform=iOS Simulator,name=iPhone 18 Pro'; build LiftTrackWatch 'generic/platform=watchOS Simulator' ;;
esac
exit $STATUS
