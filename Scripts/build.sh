#!/bin/zsh
# Usage: Scripts/build.sh <command> [app]
#   lint           swift-format lint, strict (what CI runs)
#   format         swift-format every Swift file in place
#   test           swift test in every package (or name one: Scripts/build.sh test LiftEngine)
#   ios            Lift Track for iPhone/iPad with its widgets and Watch app
#   watch          Lift Track's Watch app and its complications (generic watchOS simulator)
#   macro          Macro Track for iPhone/iPad with its widgets
#   macro-watch    Macro Track's Watch app and its complications (generic watchOS simulator)
#   mind           Mind Track for iPhone/iPad
#   mac <app>      the app for the Mac, signed to run on this Mac (see mac_build below)
#   vision <app>   the app for Apple Vision Pro (generic visionOS simulator)
#   unit <app> [device]  an app's unit and integration tests (its default test plan); device is
#                  iphone (the default), ipad, vision or mac
#   ui <app> [device]    an app's UI tests, end to end (its UI test plan), on the same devices
#   all            lint, every package's tests and every build above
#   simulator [device]   print this checkout's test simulator's UDID (creating it if needed):
#                  iphone (the default), ipad or vision
#   products [mac] print where this checkout's simulator (or Mac) builds land (the .app files)
# <app> is lift, macro or mind. Builds print only errors and warnings, into a DerivedData folder of
# this checkout's own (/tmp/system-dd-<checkout>; DERIVED_DATA overrides it). Simulator work runs on
# this checkout's own simulators ("Stadig Tests <checkout>", "Stadig iPad <checkout>" and "Stadig
# Vision <checkout>", created when missing), so sessions in other checkouts and worktrees never
# collide with them. SIMULATOR=<udid> uses another.
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

# A simulator of our own: the newest "Pro" iPhone, the newest 13-inch iPad Pro or the Vision Pro, on
# the newest runtime that has one.
test_simulator() {
  if [[ -n ${SIMULATOR:-} ]]; then print $SIMULATOR; return; fi
  local device=${1:-iphone} name platform family pattern udid runtime type
  case $device in
    iphone) name="Stadig Tests $CHECKOUT" platform=iOS family=iPhone pattern='Pro$' ;;
    ipad) name="Stadig iPad $CHECKOUT" platform=iOS family=iPad pattern='^iPad Pro 13-inch' ;;
    vision) name="Stadig Vision $CHECKOUT" platform=xrOS family='Apple Vision' pattern='Vision Pro' ;;
    *) print -u2 "Unknown device '$device': choose iphone, ipad or vision"; exit 2 ;;
  esac
  udid=$(xcrun simctl list devices available -j | jq -r --arg n $name '[.devices[][] | select(.name == $n)][0].udid // empty')
  if [[ -z $udid ]]; then
    read -r runtime type < <(xcrun simctl list runtimes available -j | jq -r --arg p $platform --arg f $family --arg r $pattern '
      [.runtimes[] | select(.platform == $p) | {id: .identifier, types: [.supportedDeviceTypes[] | select(.productFamily == $f)]}]
      | reverse | map(select(any(.types[]; .name | test($r)))) | first
      | "\(.id) \([.types[] | select(.name | test($r))][0].identifier)"')
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

# The Mac build signs to run on this Mac alone (ad hoc), which needs no developer account, so it keeps
# only the entitlements that need no provisioning profile: the sandbox and its file, network and
# microphone access. iCloud, push and the App Group need the team's profile: without them the app keeps
# its data on this Mac (Settings says "This device only") and shares through a folder of its own.
# Archives and Xcode's own Mac builds sign with the team and the full entitlements.
MAC_SIGNING=()
mac_signing() {
  local app=$1 local_entitlements=$DD-$1-local-macOS.entitlements key
  cp Apps/$app/Config/$app-macOS.entitlements $local_entitlements
  for key in com.apple.developer.aps-environment com.apple.developer.icloud-container-identifiers \
    com.apple.developer.icloud-services com.apple.security.application-groups; do
    plutil -remove $key $local_entitlements > /dev/null 2>&1
  done
  MAC_SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
    CODE_SIGN_ENTITLEMENTS=$local_entitlements)
}

# Where an app's tests run: a simulator of this checkout's, or this Mac.
destination() {
  case ${1:-iphone} in
    mac) print 'platform=macOS,arch=arm64' ;;
    *) print "id=$(test_simulator $1)" ;;
  esac
}

app_tests() {
  local kind=$1 device=${3:-iphone}
  use_app ${2:-}
  local plan=$APP_SCHEME
  [[ $kind == ui ]] && plan=${APP_SCHEME}UI
  MAC_SIGNING=()
  [[ $device == mac ]] && mac_signing ${APP_PROJECT:h:t}
  xcode test $APP_PROJECT $APP_SCHEME "$(destination $device)" -testPlan $plan $MAC_SIGNING
}

build_app() {
  use_app $1
  xcode build $APP_PROJECT $APP_SCHEME "id=$(test_simulator)"
}

build_mac() {
  use_app ${1:-}
  mac_signing ${APP_PROJECT:h:t}
  xcode build $APP_PROJECT $APP_SCHEME 'platform=macOS,arch=arm64' $MAC_SIGNING
}

build_vision() {
  use_app ${1:-}
  xcode build $APP_PROJECT $APP_SCHEME 'generic/platform=visionOS Simulator'
}

build_watch() {
  xcode build Apps/LiftTrack/LiftTrack.xcodeproj LiftTrackWatch 'generic/platform=watchOS Simulator'
}

build_macro_watch() {
  xcode build Apps/MacroTrack/MacroTrack.xcodeproj MacroTrackWatch 'generic/platform=watchOS Simulator'
}

case $WHAT in
  lint) lint ;;
  format) format ;;
  test) shift; run_tests $@ ;;
  ios) build_app lift ;;
  watch) build_watch ;;
  macro) build_app macro ;;
  macro-watch) build_macro_watch ;;
  mind) build_app mind ;;
  mac) build_mac ${2:-} ;;
  vision) build_vision ${2:-} ;;
  unit|ui) app_tests $WHAT ${2:-} ${3:-} ;;
  all)
    lint; run_tests
    build_app lift; build_watch; build_app macro; build_macro_watch; build_app mind
    for app in lift macro mind; do build_mac $app; build_vision $app; done
    ;;
  simulator) test_simulator ${2:-} ;;
  products) [[ ${2:-} == mac ]] && print $DD/Build/Products/Debug || print $DD/Build/Products/Debug-iphonesimulator ;;
  *) print -u2 "Unknown command '$WHAT' (see the top of Scripts/build.sh)"; exit 2 ;;
esac
exit $STATUS
