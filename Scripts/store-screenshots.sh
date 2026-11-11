#!/bin/zsh
# The App Store screenshots: captures each app's store screens on simulators of this checkout's own
# and imports them into its storeassets project (Store/<app>), which frames and exports them.
#
#   Scripts/store-screenshots.sh [lift|macro ...]    (both when none is named)
#
# The iPhone (6.9") and iPad (13") screens come from the app's StoreScreenshots UI test, run on both
# at once over sample data; the Watch screens (Stadig Lift and Stadig Macro) from the Watch app's
# DEBUG launch arguments. The simulators are "Stadig Shots iPhone|iPad|Watch <checkout>", created
# when missing, in light mode with a 9:41 status bar. Then, per project: `storeassets -C Store/lift
# preview`, `validate` and `export` (Store/README.md). STOREASSETS names the binary if it isn't on PATH.
set -u
cd "${0:A:h}/.."
CHECKOUT=$(print -r -- $PWD | shasum | cut -c1-6)
DD=${DERIVED_DATA:-/tmp/system-dd-$CHECKOUT}
STOREASSETS=${STOREASSETS:-storeassets}
OUT=$DD-store-screenshots
STATUS=0

if ! command -v $STOREASSETS > /dev/null; then
  print -u2 "storeassets isn't on PATH: cargo install --locked --git https://github.com/swsvindland/screenshot storeassets-cli, or set STOREASSETS"
  exit 2
fi

# A screenshot simulator: the newest device type matching the pattern, on the newest runtime that has
# it. The Watch is an Ultra 3, whose 422×514 screen is a size App Store Connect takes.
shots_simulator() {
  local kind=$1 name="Stadig Shots $1 $CHECKOUT" platform pattern udid runtime type
  case $kind in
    iPhone) platform=iOS pattern='^iPhone [0-9]+ Pro Max$' ;;
    iPad) platform=iOS pattern='^iPad Pro 13-inch' ;;
    Watch) platform=watchOS pattern='^Apple Watch Ultra 3 ' ;;
  esac
  udid=$(xcrun simctl list devices available -j | jq -r --arg n $name '[.devices[][] | select(.name == $n)][0].udid // empty')
  if [[ -z $udid ]]; then
    read -r runtime type < <(xcrun simctl list runtimes available -j | jq -r --arg p $platform --arg r $pattern '
      [.runtimes[] | select(.platform == $p) | {id: .identifier, types: [.supportedDeviceTypes[] | select(.name | test($r))]}]
      | map(select(.types | length > 0)) | last
      | "\(.id) \(.types | sort_by(.name) | last | .identifier)"')
    udid=$(xcrun simctl create $name $type $runtime)
  fi
  xcrun simctl boot $udid 2> /dev/null
  xcrun simctl bootstatus $udid -b > /dev/null
  if [[ $platform == iOS ]]; then
    xcrun simctl ui $udid appearance light
    # Discharging at 100% draws a full battery without the charging bolt.
    xcrun simctl status_bar $udid override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
  fi
  print $udid
}

# The iPhone and iPad screens, from the app's StoreScreenshots UI test (which builds the app).
capture_devices() {
  local app=$1 project=$2 scheme=$3 folder=$OUT/$1 log=$DD-$3-store-screenshots.log
  rm -rf $folder $OUT/$1-watch
  print "== $scheme: iPhone and iPad"
  # An app left in front would put its "◂ Stadig …" back link in the first screenshot's status bar.
  local device bundle
  for device in $PHONE $PAD; do
    for bundle in dev.svindland.stadig.{lift,macro}; do xcrun simctl terminate $device $bundle 2> /dev/null; done
  done
  TEST_RUNNER_STORE_SCREENSHOTS=$folder xcodebuild test -project $project -scheme $scheme -testPlan ${scheme}UI \
    -only-testing:${scheme}UITests/StoreScreenshots -destination id=$PHONE -destination id=$PAD \
    -parallel-testing-enabled NO -derivedDataPath $DD > $log 2>&1 || { STATUS=1; print "   failed, full log: $log"; }
  local class
  for class in phone tablet; do
    if [[ -d $folder/$class ]]; then
      $STOREASSETS -C Store/$app capture import $folder/$class/*.png --class $class | tail -1
    else
      STATUS=1
      print "   no $class screenshots"
    fi
  done
}

# One Watch screen: the app launched fresh with the arguments, given time to settle, then captured.
watch_screen() {
  local project=$1 bundle=$2 name=$3 folder=$OUT/$1
  shift 3
  mkdir -p $folder
  xcrun simctl launch --terminate-running-process $WATCH $bundle "$@" > /dev/null
  sleep 6
  xcrun simctl io $WATCH screenshot --type=png $folder/$name.png 2> /dev/null
  $STOREASSETS -C Store/$project capture import $folder/$name.png --class watch > /dev/null || STATUS=1
}

# Builds a Watch app and installs it on the Watch simulator.
watch_app() {
  local scheme=$1 what=$2
  WATCH=${WATCH:-$(shots_simulator Watch)}
  Scripts/build.sh $what || { STATUS=1; return 1; }
  xcrun simctl install $WATCH $DD/Build/Products/Debug-watchsimulator/$scheme.app
}

(( $# )) || set -- lift macro
PHONE=$(shots_simulator iPhone)
PAD=$(shots_simulator iPad)
WATCH=${WATCH:-}
L=dev.svindland.stadig.lift.watchkitapp
M=dev.svindland.stadig.macro.watchkitapp
MACRO_SEED=(-inMemoryStore -seedSampleData -seedPlan -seedSupplements)
for app in $@; do
  case $app in
    lift)
      capture_devices lift Apps/LiftTrack/LiftTrack.xcodeproj LiftTrack
      if watch_app LiftTrackWatch watch; then
        watch_screen lift-watch $L set -sampleContext -sampleScreen set
        watch_screen lift-watch $L rating -sampleContext -sampleScreen rating
        watch_screen lift-watch $L rest -sampleContext -sampleScreen rest
        watch_screen lift-watch $L conditioning -sampleContext -sampleScreen conditioning
        watch_screen lift-watch $L home -sampleContext -sampleScreen home
      fi
      ;;
    macro)
      capture_devices macro Apps/MacroTrack/MacroTrack.xcodeproj MacroTrack
      if watch_app MacroTrackWatch macro-watch; then
        watch_screen macro-watch $M today $MACRO_SEED
        watch_screen macro-watch $M log-again $MACRO_SEED -page logAgain
        watch_screen macro-watch $M water $MACRO_SEED -page water
        watch_screen macro-watch $M supplements $MACRO_SEED -page supplements
        watch_screen macro-watch $M weigh $MACRO_SEED -page weigh
      fi
      ;;
    *) print -u2 "Unknown app '$app': choose lift or macro"; exit 2 ;;
  esac
done
exit $STATUS
