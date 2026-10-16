#!/bin/zsh
# Usage: Scripts/build.sh [test|ios|watch|macro|all]
#   test   swift test for every package
#   ios    Lift Track for iPhone/iPad with its widgets and Watch app (iPhone 18 Pro simulator)
#   watch  Lift Track's Watch app and its complications (generic watchOS simulator)
#   macro  Macro Track for iPhone/iPad with its widgets (iPhone 18 Pro simulator)
#   all    everything above
# Builds into a throwaway DerivedData and prints only errors and warnings.
set -u
cd "${0:A:h}/.."
WHAT=${1:-all}
DD=${DERIVED_DATA:-/tmp/system-dd}
STATUS=0

run_tests() {
  for pkg in SystemCore ExerciseLibrary SystemStore HealthBridge LiftEngine NutritionEngine FoodDatabase FoodIntelligence MealPlanner; do
    print "== $pkg"
    (cd Packages/$pkg && swift test 2>&1 | grep -E "error:|warning:|recorded an issue|Test run with|Executed .* tests") || true
  done
}

build() {
  local project=$1 scheme=$2 dest=$3
  print "== $scheme"
  xcodebuild -project $project -scheme $scheme -destination "$dest" -derivedDataPath "$DD" build > "$DD-$scheme.log" 2>&1 || STATUS=1
  grep -E "^/.*(error|warning):" "$DD-$scheme.log" | sort -u
  grep -E "\*\* BUILD" "$DD-$scheme.log"
}

LIFT=Apps/LiftTrack/LiftTrack.xcodeproj
MACRO=Apps/MacroTrack/MacroTrack.xcodeproj
PHONE='platform=iOS Simulator,name=iPhone 18 Pro'

case $WHAT in
  test) run_tests ;;
  ios) build $LIFT LiftTrack $PHONE ;;
  watch) build $LIFT LiftTrackWatch 'generic/platform=watchOS Simulator' ;;
  macro) build $MACRO MacroTrack $PHONE ;;
  all) run_tests; build $LIFT LiftTrack $PHONE; build $LIFT LiftTrackWatch 'generic/platform=watchOS Simulator'; build $MACRO MacroTrack $PHONE ;;
esac
exit $STATUS
