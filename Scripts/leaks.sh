#!/bin/zsh
# Usage: Scripts/leaks.sh lift|macro|mind [launch arguments...]
# Launches the app on the test simulator with seeded data (and any extra DEBUG launch arguments, such
# as -tab plan or -startSession), lets it settle, and runs `leaks` on the running process. With no
# extra arguments it walks a set of screens for that app. Exits non-zero if any launch leaks.
# Build the app first (Scripts/build.sh ios|macro|mind); SIMULATOR picks a simulator as there.
set -u
cd "${0:A:h}/.."
APP=${1:?lift, macro or mind}
shift
DD=${DERIVED_DATA:-/tmp/system-dd}
SETTLE=${SETTLE:-10}

case $APP in
  lift) name=LiftTrack id=dev.svindland.stadig.lift
        screens=("" "-tab plan" "-tab progress" "-tab body" "-startSession") ;;
  macro) name=MacroTrack id=dev.svindland.stadig.macro
         screens=("" "-tab plan" "-tab progress" "-log search" "-seedSupplements -showSupplements" "-showSettings") ;;
  mind) name=MindTrack id=dev.svindland.stadig.mind
        screens=("" "-tab plan" "-tab progress" "-startSession" "-showShelf" "-showSettings") ;;
  *) print -u2 "Unknown app '$APP'"; exit 2 ;;
esac
(( $# )) && screens=("$*")

udid=${SIMULATOR:-$(xcrun simctl list devices available -j | jq -r '[.devices[][] | select(.name == "Stadig Tests")][0].udid // empty')}
[[ -n $udid ]] || { print -u2 "No simulator: run Scripts/build.sh unit $APP once, or set SIMULATOR"; exit 2 }
app=$DD/Build/Products/Debug-iphonesimulator/$name.app
[[ -d $app ]] || { print -u2 "No build at $app: run Scripts/build.sh first"; exit 2 }
xcrun simctl boot $udid 2>/dev/null
xcrun simctl install $udid $app || exit 1

# Leaks that come from the system, not this code: dyld's image map in the simulator.
SYSTEM_LEAKS='map_images_nolock'

STATUS=0
for screen in $screens; do
  pid=$(SIMCTL_CHILD_MallocStackLogging=1 xcrun simctl launch --terminate-running-process $udid $id \
    -uiTesting -seedSampleData ${=screen} | awk '{ print $NF }')
  sleep $SETTLE
  report=$(leaks $pid 2>/dev/null)
  # Each "ROOT LEAK"/"ROOT CYCLE" block counts its leaks on its first line; blocks naming a system
  # allocation are left out of ours.
  read -r total ours < <(print -r -- $report | awk -v system="$SYSTEM_LEAKS" '
    /leaks for/ { total = $3 }
    /ROOT (LEAK|CYCLE):/ { if (block != "" && block !~ system) ours += count; block = $0; count = $1; next }
    block != "" && /^ +[0-9]+ \(/ { block = block "\n" $0 }
    END { if (block != "" && block !~ system) ours += count; print (total == "" ? "none" : total), ours + 0 }')
  if [[ $total == none ]]; then
    print "== ${screen:-launch}: leaks couldn't read the process (did it crash? try a longer SETTLE)"
    STATUS=1
    continue
  fi
  print "== ${screen:-launch}: $ours leaks in this code ($total in all, the rest the system's)"
  if (( ours )); then
    STATUS=1
    print -r -- $report | grep -E 'ROOT (LEAK|CYCLE)|^ +[0-9]+ \(' | grep -v -E $SYSTEM_LEAKS | head -30
  fi
  xcrun simctl terminate $udid $id 2>/dev/null
done
exit $STATUS
