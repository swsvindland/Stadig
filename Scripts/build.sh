#!/bin/zsh
# Usage: Scripts/build.sh <command> [app]
#   lint           swift-format lint, strict (what CI runs)
#   format         swift-format every Swift file in place
#   test           swift test in every package (or name one: Scripts/build.sh test LiftEngine)
#   ios            Lift Track for iPhone/iPad with its widgets and Watch app
#   watch          Lift Track's Watch app and its complications (generic watchOS simulator)
#   macro          Macro Track for iPhone/iPad with its widgets
#   mind           Mind Track for iPhone/iPad
#   unit <app>     an app's unit and integration tests, and its packages' tests (its default test plan)
#   ui <app>       an app's UI tests, end to end (its UI test plan)
#   all            lint, every package's tests and every build above
#   simulator      print this checkout's test simulator's UDID (creating it if needed)
#   products       print where this checkout's simulator builds land (the .app files)
# <app> is lift, macro or mind. Builds print only errors and warnings, into a DerivedData folder of
# this checkout's own (/tmp/system-dd-<checkout>; DERIVED_DATA overrides it). Simulator work runs on
# this checkout's own simulator ("Stadig Tests <checkout>", created when missing), so sessions in other
# checkouts and worktrees never collide with it. SIMULATOR=<udid> uses another.
# STRICT=1 (as CI sets it) treats every warning as an error. SANITIZE=thread or address runs the
# package tests under that sanitizer.
set -u
cd "${0:A:h}/.."
WHAT=${1:-all}
# Short and stable per checkout, so two checkouts never share build products or a simulator.
CHECKOUT=$(print -r -- $PWD | shasum | cut -c1-6)
DD=${DERIVED_DATA:-/tmp/system-dd-$CHECKOUT}
STRICT=${STRICT:-0}
STATUS=0
PACKAGES=(Packages/*/Package.swift(:h:t))
SWIFT_SOURCES=(Apps Packages Scripts)

lint() {
  print "== swift-format lint"
  xcrun swift-format lint --strict --recursive --parallel $SWIFT_SOURCES || STATUS=1
}

format() {
  xcrun swift-format format --in-place --recursive --parallel $SWIFT_SOURCES || STATUS=1
}

run_tests() {
  local pkg flags=()
  (( STRICT )) && flags=(-Xswiftc -warnings-as-errors)
  [[ -n ${SANITIZE:-} ]] && flags+=(--sanitize=$SANITIZE)
  for pkg in ${@:-$PACKAGES}; do
    print "== $pkg"
    # pipefail keeps swift test's status through the filter, so a failing package fails the run.
    (cd Packages/$pkg && set -o pipefail && swift test $flags 2>&1 \
      | grep -E "error:|warning:|recorded an issue|Test run with|Executed .* tests") || STATUS=1
  done
}

# A simulator of our own: the newest "Pro" iPhone on the newest iOS runtime that has one.
test_simulator() {
  if [[ -n ${SIMULATOR:-} ]]; then print $SIMULATOR; return; fi
  local name="Stadig Tests $CHECKOUT" udid runtime type
  udid=$(xcrun simctl list devices available -j | jq -r --arg n $name '[.devices[][] | select(.name == $n)][0].udid // empty')
  if [[ -z $udid ]]; then
    read -r runtime type < <(xcrun simctl list runtimes available -j | jq -r '
      [.runtimes[] | select(.platform == "iOS") | {id: .identifier, types: [.supportedDeviceTypes[] | select(.productFamily == "iPhone")]}]
      | reverse | map(select(any(.types[]; .name | test("Pro$")))) | first
      | "\(.id) \([.types[] | select(.name | test("Pro$"))][0].identifier)"')
    udid=$(xcrun simctl create $name $type $runtime)
  fi
  print $udid
}

xcode() {
  local action=$1 project=$2 scheme=$3 dest=$4 log=$DD-$3-$1.log failed=0
  shift 4
  # Simulator builds sign to run locally, which needs no account, and hosted tests need the signature.
  local flags=()
  (( STRICT )) && flags+=(SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES)
  print "== $scheme $action $*"
  mkdir -p $DD-results
  xcodebuild $action -project $project -scheme $scheme -destination $dest -derivedDataPath $DD \
    -resultBundlePath $DD-results/$scheme-$action-$(date +%s).xcresult "$@" $flags > $log 2>&1 || failed=1
  grep -E "^/.*(error|warning):" $log | sort -u
  grep -E "Test run with|Executed [0-9]+ tests|\*\* (BUILD|TEST)" $log
  if (( failed )); then
    STATUS=1
    print "   full log: $log"
  fi
}

# The project and scheme of an app; exits the script for an unknown one.
APP_PROJECT= APP_SCHEME=
use_app() {
  case ${1:-} in
    lift) APP_PROJECT=Apps/LiftTrack/LiftTrack.xcodeproj APP_SCHEME=LiftTrack ;;
    macro) APP_PROJECT=Apps/MacroTrack/MacroTrack.xcodeproj APP_SCHEME=MacroTrack ;;
    mind) APP_PROJECT=Apps/MindTrack/MindTrack.xcodeproj APP_SCHEME=MindTrack ;;
    *) print -u2 "Unknown app '${1:-}': choose lift, macro or mind"; exit 2 ;;
  esac
}

app_tests() {
  local kind=$1
  use_app ${2:-}
  local plan=$APP_SCHEME
  [[ $kind == ui ]] && plan=${APP_SCHEME}UI
  xcode test $APP_PROJECT $APP_SCHEME "id=$(test_simulator)" -testPlan $plan
}

build_app() {
  use_app $1
  xcode build $APP_PROJECT $APP_SCHEME "id=$(test_simulator)"
}

build_watch() {
  xcode build Apps/LiftTrack/LiftTrack.xcodeproj LiftTrackWatch 'generic/platform=watchOS Simulator'
}

case $WHAT in
  lint) lint ;;
  format) format ;;
  test) shift; run_tests $@ ;;
  ios) build_app lift ;;
  watch) build_watch ;;
  macro) build_app macro ;;
  mind) build_app mind ;;
  unit|ui) app_tests $WHAT ${2:-} ;;
  all) lint; run_tests; build_app lift; build_watch; build_app macro; build_app mind ;;
  simulator) test_simulator ;;
  products) print $DD/Build/Products/Debug-iphonesimulator ;;
  *) print -u2 "Unknown command '$WHAT' (see the top of Scripts/build.sh)"; exit 2 ;;
esac
exit $STATUS
