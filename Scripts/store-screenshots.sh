#!/bin/zsh
# The App Store screenshots: captures each app's store screens on simulators of this checkout's own
# (and on this Mac) and imports them into its storeassets projects (Store/<app>…), which frame and
# export them.
#
#   Scripts/store-screenshots.sh [lift|macro ...]    (both when none is named)
#   DEVICES=duo,mac Scripts/store-screenshots.sh     (only those: iphone, ipad, watch, duo, mac and
#                                                    vision, all by default)
#
# The iPhone (6.9"), iPad (13") and iPhone Duo screens come from the app's StoreScreenshots UI test:
# the iPhone and iPad at once over sample data, then the Duo folded (its outer display) and unfolded
# (its inner one), as `duo_fold` below folds it through SpringBoard. The Watch, Vision Pro and Mac
# screens come from the apps' DEBUG launch arguments: the Watch and Vision Pro apps on simulators, the
# Mac app on this Mac, launched in the background and captured by its window (it needs Screen
# Recording for the terminal). The simulators are "Stadig
# Shots iPhone|iPad|Watch|Duo|Vision <checkout>", created when missing, in light mode with a 9:41
# status bar. Then, per project: `storeassets -C Store/lift preview`, `validate` and `export`
# (Store/README.md). STOREASSETS names the binary if it isn't on PATH.
set -u
cd "${0:A:h}/.."
CHECKOUT=$(print -r -- $PWD | shasum | cut -c1-6)
DD=${DERIVED_DATA:-/tmp/system-dd-$CHECKOUT}
STOREASSETS=${STOREASSETS:-storeassets}
OUT=$DD-store-screenshots
STATUS=0
DEVICES=(${(s:,:)${DEVICES:-iphone,ipad,watch,duo,mac,vision}})
# A whole-hour time zone where it's now 1 PM, for the screens that read the hour (Stadig Macro's
# Today: lunch and breakfast logged, not one food of a morning): Etc/GMT+N is N hours behind UTC.
offset=$(( 10#$(date -u +%H) - 13 ))
STORE_TZ=Etc/GMT$( (( offset >= 0 )) && print +$offset || print $offset )

if ! command -v $STOREASSETS > /dev/null; then
  print -u2 "storeassets isn't on PATH: cargo install --locked --git https://github.com/swsvindland/screenshot storeassets-cli, or set STOREASSETS"
  exit 2
fi

wanted() { (( ${DEVICES[(Ie)$1]} )) }

# A screenshot simulator: the newest device type matching the pattern, on the newest runtime that has
# it. The Watch is an Ultra 3, whose 422×514 screen is a size App Store Connect takes; the Vision Pro
# the 4K one, whose screenshots are App Store Connect's 3840×2160.
shots_simulator() {
  local kind=$1 name="Stadig Shots $1 $CHECKOUT" platform pattern udid runtime type
  case $kind in
    iPhone) platform=iOS pattern='^iPhone [0-9]+ Pro Max$' ;;
    iPad) platform=iOS pattern='^iPad Pro 13-inch' ;;
    Watch) platform=watchOS pattern='^Apple Watch Ultra 3 ' ;;
    Duo) platform=iOS pattern='^iPhone Duo$' ;;
    Vision) platform=xrOS pattern='^Apple Vision Pro$' ;;
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
  if [[ $platform != watchOS ]]; then
    xcrun simctl ui $udid appearance light
  fi
  [[ $platform == iOS ]] && clean_status_bar $udid
  print $udid
}

# 9:41, full bars, and discharging at 100%, which draws a full battery without the charging bolt.
clean_status_bar() {
  xcrun simctl status_bar $1 override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
}

# Leaves an app's screens out of the next capture: a folder of old ones would be imported again.
fresh() { rm -rf $OUT/$1; mkdir -p $OUT/$1 }

# Imports a folder of captures into a project, as one device class.
import_class() {
  local project=$1 class=$2 folder=$3
  if [[ -n $(print -l $folder/*.png(N)) ]]; then
    $STOREASSETS -C Store/$project capture import $folder/*.png --class $class | tail -1
  else
    STATUS=1
    print "   no $class screenshots"
  fi
}

# The iPhone and iPad screens, from the app's StoreScreenshots UI test (which builds the app), on
# whichever of the two DEVICES names.
capture_devices() {
  local app=$1 project=$2 scheme=$3 folder=$OUT/$1 log=$DD-$3-store-screenshots.log destinations=() classes=()
  wanted iphone && { destinations+=(-destination id=$PHONE); classes+=(phone) }
  wanted ipad && { destinations+=(-destination id=$PAD); classes+=(tablet) }
  (( $#destinations )) || return
  print "== $scheme: ${(j: and :)classes}"
  # An app left in front would put its "◂ Stadig …" back link in the first screenshot's status bar.
  local device bundle class
  for device in ${destinations:#-destination}; do
    for bundle in dev.svindland.stadig.{lift,macro}; do xcrun simctl terminate ${device#id=} $bundle 2> /dev/null; done
  done
  for class in $classes; do rm -rf $folder/$class; done
  TEST_RUNNER_STORE_SCREENSHOTS=$folder TEST_RUNNER_STORE_TZ=$STORE_TZ xcodebuild test -project $project -scheme $scheme -testPlan ${scheme}UI \
    -only-testing:${scheme}UITests/StoreScreenshots $destinations -parallel-testing-enabled NO -derivedDataPath $DD > $log 2>&1 \
    || { STATUS=1; print "   failed, full log: $log"; }
  for class in $classes; do import_class $app $class $folder/$class; done
}

# Folds or unfolds the iPhone Duo simulator, which has no control for it without the Simulator app:
# a helper run on the simulator asks SpringBoard's display tool service for the swap a hand would
# make, with the entitlements its own tools carry (a simulator reads them from the binary's
# __entitlements section). `duo_fold open|closed`.
duo_fold() {
  local helper=$DD/duo-fold
  if [[ ! -x $helper ]]; then
    mkdir -p $DD/duo-fold-src
    cat > $DD/duo-fold-src/fold.m <<'EOF'
// fold [-position=open|closed|book|0.0-1.0] [-deviceOrientation=portrait|…] [-wait]: SpringBoard's own
// parser reads the arguments into its SBFDisplayToolSwapSettings ({q d q q B q d d}), which this only
// passes on.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>

typedef struct { unsigned char bytes[64]; } SwapSettings;

int main(int argc, char **argv) {
  @autoreleasepool {
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SpringBoardFoundation.framework/SpringBoardFoundation", RTLD_NOW);
    BOOL (*parse)(NSArray *, SwapSettings *, NSError **) = dlsym(RTLD_DEFAULT, "SBFDisplayToolSwapSettingsFromArguments");
    Class serviceClass = NSClassFromString(@"SBSDisplayToolService");
    if (!parse || !serviceClass) { fprintf(stderr, "fold: this runtime has no display tool service\n"); return 1; }
    NSMutableArray *args = [NSMutableArray array];
    for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
    SwapSettings settings = {0};
    NSError *error = nil;
    if (!parse(args, &settings, &error)) { fprintf(stderr, "fold: %s\n", error.localizedDescription.UTF8String); return 2; }
    id service = [[serviceClass alloc] init];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    // The reply carries a result struct this doesn't read: its words are taken without retaining them.
    void (^completion)(uintptr_t, uintptr_t) = ^(uintptr_t result, uintptr_t unused) { dispatch_semaphore_signal(done); };
    ((void (*)(id, SEL, SwapSettings, id))objc_msgSend)(service, NSSelectorFromString(@"swapDisplayWithSettings:completion:"), settings, completion);
    long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
    ((void (*)(id, SEL))objc_msgSend)(service, NSSelectorFromString(@"invalidate"));
    if (timedOut) { fprintf(stderr, "fold: SpringBoard didn't answer\n"); return 3; }
  }
  return 0;
}
EOF
    cat > $DD/duo-fold-src/entitlements.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.springboard.displaytool</key><true/>
<key>com.apple.springboard.sbdisplay</key><true/>
<key>com.apple.springboard.sbdisplay.service</key><true/>
<key>com.apple.springboard.testautomation</key><true/>
</dict></plist>
EOF
    xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=18.0 -fobjc-arc -framework Foundation \
      $DD/duo-fold-src/fold.m -o $helper -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements \
      -Xlinker $DD/duo-fold-src/entitlements.plist && codesign -s - -f $helper 2> /dev/null || return 1
  fi
  # Unfolded with the phone upright, the inner display is landscape, as a person opens it.
  xcrun simctl spawn $DUO $helper -position=$1 -deviceOrientation=portrait -wait || return 1
  sleep 3
  if [[ $1 == closed ]]; then
    # Folded shut, the phone sleeps with both displays dark, and nothing XCTest does wakes it. A
    # restart brings it up as it was left, folded, with the outer display lit.
    xcrun simctl shutdown $DUO && xcrun simctl boot $DUO && xcrun simctl bootstatus $DUO -b > /dev/null || return 1
    clean_status_bar $DUO
    sleep 10
  fi
}

# The iPhone Duo's screens: the StoreScreenshots UI test folded and then unfolded. XCTest can't take
# the inner display's screenshot (its main screen stays the outer one), so the test asks for each
# with a `<name>.wanted` file beside it and this takes it from the display the app is on: 1 is the
# outer (1398×2034), 3 the inner (2007×2853, landscape as it's held).
capture_duo() {
  local app=$1 project=$2 scheme=$3 folder state class display watcher request bundle log
  wanted duo || return
  for state class display in closed foldable-outer 1 open foldable-inner 3; do
    folder=$OUT/$app/$class log=$DD-$scheme-store-screenshots-$class.log
    print "== $scheme: iPhone Duo $state"
    rm -rf $folder && mkdir -p $folder
    duo_fold $state || { STATUS=1; print "   couldn't fold the iPhone Duo $state"; continue }
    for bundle in dev.svindland.stadig.{lift,macro}; do xcrun simctl terminate $DUO $bundle 2> /dev/null; done
    {
      while true; do
        for request in $folder/*.wanted(N); do
          xcrun simctl io $DUO screenshot --display=$display ${request:r}.png > /dev/null 2>&1
          rm -f $request
        done
        sleep 0.3
      done
    } &
    watcher=$!
    TEST_RUNNER_STORE_SCREENSHOTS=$OUT/$app TEST_RUNNER_STORE_CLASS=$class TEST_RUNNER_STORE_TZ=$STORE_TZ xcodebuild test \
      -project $project -scheme $scheme -testPlan ${scheme}UI -only-testing:${scheme}UITests/StoreScreenshots \
      -destination id=$DUO -derivedDataPath $DD > $log 2>&1 || { STATUS=1; print "   failed, full log: $log"; }
    kill $watcher 2> /dev/null
    import_class $app $class $folder
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

# Builds an app for Vision Pro and installs it on the Vision Pro simulator.
vision_app() {
  local app=$1 scheme=$2
  VISION=${VISION:-$(shots_simulator Vision)}
  Scripts/build.sh vision $app || { STATUS=1; return 1; }
  xcrun simctl install $VISION $DD/Build/Products/Debug-xrsimulator/$scheme.app
}

# One Vision Pro screen: the app launched fresh in the simulator's room, given time to settle, then
# captured and cropped to the window and the room just around it (the middle 70%, still 16:9: the
# window opens at its default size in the same place each launch), so the window isn't lost in the room.
vision_screen() {
  local project=$1 bundle=$2 name=$3 folder=$OUT/$1/xr
  shift 3
  mkdir -p $folder
  SIMCTL_CHILD_TZ=$STORE_TZ xcrun simctl launch --terminate-running-process $VISION $bundle -uiTesting "$@" > /dev/null
  sleep 14
  xcrun simctl io $VISION screenshot --type=png $folder/$name.png 2> /dev/null
  sips -c 1512 2688 --cropOffset 432 576 $folder/$name.png > /dev/null || STATUS=1
}

# Builds an app for the Mac.
mac_app() {
  Scripts/build.sh mac $1 || { STATUS=1; return 1; }
}

# One Mac screen: the app launched in the background, light whatever the Mac's appearance, given time
# to settle, its window captured (as it opens: Stadig Lift 1240×820, its session 1080×760, Stadig
# Macro 1280×820 points), then quit. The window and the quit go by the launched copy's process, not
# the app's name or bundle id (as `Scripts/window-shot.swift` and `quit app id` would), so a copy the
# person has open, from the App Store or TestFlight, is neither captured nor quit.
mac_screen() {
  local project=$1 scheme=$2 name=$3 folder=$OUT/$1/desktop binary=$DD/Build/Products/Debug/$2.app/Contents/MacOS/$2 pid window
  shift 3
  mkdir -p $folder
  if [[ ! -f $DD/window-of.swift ]]; then
    cat > $DD/window-of.swift <<'EOF'
// window-of <pid>: the number of that process's frontmost on-screen window, for `screencapture -l`.
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1]) ?? 0
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
guard let window = windows.first(where: { $0[kCGWindowOwnerPID as String] as? Int == pid && $0[kCGWindowLayer as String] as? Int == 0 }),
    let number = window[kCGWindowNumber as String] as? Int
else { exit(1) }
print(number)
EOF
  fi
  open -g -n --env TZ=$STORE_TZ ${binary:h:h:h} --args -NSTreatUnknownArgumentsAsOpen NO -NSRequiresAquaSystemAppearance YES -uiTesting "$@"
  sleep 10
  # By its real path: /tmp is a link to /private/tmp, which the process list shows.
  pid=$(pgrep -n -f "^${binary:A}")
  if window=$(swift $DD/window-of.swift ${pid:-0}); then
    screencapture -x -o -l$window $folder/$name.png
  else
    STATUS=1
    print "   no $scheme window for $name"
  fi
  [[ -n $pid ]] && kill $pid
  sleep 2
}

(( $# )) || set -- lift macro
wanted iphone && PHONE=$(shots_simulator iPhone)
wanted ipad && PAD=$(shots_simulator iPad)
wanted duo && DUO=$(shots_simulator Duo)
WATCH=${WATCH:-}
VISION=${VISION:-}
L=dev.svindland.stadig.lift
M=dev.svindland.stadig.macro
MACRO_SEED=(-inMemoryStore -seedSampleData -seedPlan -seedSupplements)
# Stadig Macro on the Mac and Vision Pro: the sample person with the plan started and today eaten as
# yesterday was up to 1 PM, so every screen's sidebar has the calories left that Today shows.
MACRO_DESK=(-seedSampleData -seedPlan -seedToday)
for app in $@; do
  case $app in
    lift)
      capture_devices lift Apps/LiftTrack/LiftTrack.xcodeproj LiftTrack
      capture_duo lift Apps/LiftTrack/LiftTrack.xcodeproj LiftTrack
      if wanted watch && watch_app LiftTrackWatch watch; then
        watch_screen lift-watch $L.watchkitapp set -sampleContext -sampleScreen set
        watch_screen lift-watch $L.watchkitapp rating -sampleContext -sampleScreen rating
        watch_screen lift-watch $L.watchkitapp rest -sampleContext -sampleScreen rest
        watch_screen lift-watch $L.watchkitapp conditioning -sampleContext -sampleScreen conditioning
        watch_screen lift-watch $L.watchkitapp home -sampleContext -sampleScreen home
      fi
      # The same five screens as the iPad's: a set waiting for its rating, Today, the program desk with
      # the bench press in the inspector, Progress and Body.
      if wanted vision && vision_app lift LiftTrack; then
        print "== LiftTrack: Vision Pro"
        fresh lift/xr
        vision_screen lift $L session -seedSampleData -startSession -sessionAt set
        vision_screen lift $L today -seedSampleData
        vision_screen lift $L plan -seedSampleData -tab program -programLift barbell-bench-press
        vision_screen lift $L progress -seedSampleData -tab progress
        vision_screen lift $L body -seedSampleData -tab body
        import_class lift xr $OUT/lift/xr
      fi
      if wanted mac && mac_app lift; then
        print "== LiftTrack: Mac"
        fresh lift/desktop
        mac_screen lift LiftTrack session -seedSampleData -startSession -sessionAt set
        mac_screen lift LiftTrack today -seedSampleData
        mac_screen lift LiftTrack plan -seedSampleData -tab program -programLift barbell-bench-press
        mac_screen lift LiftTrack progress -seedSampleData -tab progress
        mac_screen lift LiftTrack body -seedSampleData -tab body
        import_class lift desktop $OUT/lift/desktop
      fi
      ;;
    macro)
      capture_devices macro Apps/MacroTrack/MacroTrack.xcodeproj MacroTrack
      capture_duo macro Apps/MacroTrack/MacroTrack.xcodeproj MacroTrack
      if wanted watch && watch_app MacroTrackWatch macro-watch; then
        watch_screen macro-watch $M.watchkitapp today $MACRO_SEED
        watch_screen macro-watch $M.watchkitapp log-again $MACRO_SEED -page logAgain
        watch_screen macro-watch $M.watchkitapp water $MACRO_SEED -page water
        watch_screen macro-watch $M.watchkitapp supplements $MACRO_SEED -page supplements
        watch_screen macro-watch $M.watchkitapp weigh $MACRO_SEED -page weigh
      fi
      # The iPad's screens but the scan, the phone's (neither has a camera to scan a label with), in a
      # project of their own (Store/macro-mac-vision); Foods shows the catalog with its first food in
      # the inspector, as it opens.
      if wanted vision && vision_app macro MacroTrack; then
        print "== MacroTrack: Vision Pro"
        fresh macro-mac-vision/xr
        vision_screen macro-mac-vision $M today $MACRO_DESK
        vision_screen macro-mac-vision $M log $MACRO_DESK -tab log -daysAgo 1
        vision_screen macro-mac-vision $M search $MACRO_DESK -tab foods
        vision_screen macro-mac-vision $M plan $MACRO_DESK -tab plan
        vision_screen macro-mac-vision $M progress $MACRO_DESK -tab progress
        vision_screen macro-mac-vision $M meal-prep $MACRO_DESK -seedMealPlan -tab mealplan
        import_class macro-mac-vision xr $OUT/macro-mac-vision/xr
      fi
      if wanted mac && mac_app macro; then
        print "== MacroTrack: Mac"
        fresh macro-mac-vision/desktop
        mac_screen macro-mac-vision MacroTrack today $MACRO_DESK
        mac_screen macro-mac-vision MacroTrack log $MACRO_DESK -tab log -daysAgo 1
        mac_screen macro-mac-vision MacroTrack search $MACRO_DESK -tab foods
        mac_screen macro-mac-vision MacroTrack plan $MACRO_DESK -tab plan
        mac_screen macro-mac-vision MacroTrack progress $MACRO_DESK -tab progress
        mac_screen macro-mac-vision MacroTrack meal-prep $MACRO_DESK -seedMealPlan -tab mealplan
        import_class macro-mac-vision desktop $OUT/macro-mac-vision/desktop
      fi
      ;;
    *) print -u2 "Unknown app '$app': choose lift or macro"; exit 2 ;;
  esac
done
exit $STATUS
