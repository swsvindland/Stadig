#!/bin/zsh
# Usage: Scripts/leaks.sh lift|macro [launch arguments...]
# Launches the app on the test simulator with seeded data (and any extra DEBUG launch arguments, such
# as -tab plan or -startSession), lets it settle, and runs `leaks` on the running process. With no
# extra arguments it walks a set of screens for that app. Exits non-zero if any launch leaks.
# Build the app first (Scripts/build.sh ios|macro); SIMULATOR picks a simulator as there.
set -u
cd "${0:A:h}/.."
APP=${1:?lift or macro}
shift
# The same per-checkout DerivedData and simulator Scripts/build.sh uses.
CHECKOUT=$(print -r -- $PWD | shasum | cut -c1-6)
DD=${DERIVED_DATA:-/tmp/system-dd-$CHECKOUT}
SETTLE=${SETTLE:-10}

case $APP in
  lift) name=LiftTrack id=dev.svindland.stadig.lift
        screens=("" "-tab plan" "-tab progress" "-tab body" "-startSession") ;;
  macro) name=MacroTrack id=dev.svindland.stadig.macro
         screens=("" "-tab plan" "-tab progress" "-log search" "-seedSupplements -showSupplements" "-showSettings") ;;
  *) print -u2 "Unknown app '$APP'"; exit 2 ;;
esac
(( $# )) && screens=("$*")

udid=${SIMULATOR:-$(xcrun simctl list devices available -j | jq -r --arg n "Stadig Tests $CHECKOUT" '[.devices[][] | select(.name == $n)][0].udid // empty')}
[[ -n $udid ]] || { print -u2 "No simulator: run Scripts/build.sh unit $APP once, or set SIMULATOR"; exit 2 }
app=$DD/Build/Products/Debug-iphonesimulator/$name.app
[[ -d $app ]] || { print -u2 "No build at $app: run Scripts/build.sh first"; exit 2 }
xcrun simctl boot $udid 2>/dev/null
xcrun simctl install $udid $app || exit 1

# Which leaks are this code's: Scripts/classify-leaks.py reads the report.
CLASSIFY=${0:A:h}/classify-leaks.py

STATUS=0
report=$(mktemp)
trap 'rm -f $report' EXIT
# Quoted, so the plain launch ("") is checked too.
for screen in "${screens[@]}"; do
  pid=$(SIMCTL_CHILD_MallocStackLogging=1 xcrun simctl launch --terminate-running-process $udid $id \
    -uiTesting -seedSampleData ${=screen} | awk '{ print $NF }')
  sleep $SETTLE
  leaks --fullStacks $pid > $report 2>/dev/null
  read -r total ours < <(python3 $CLASSIFY $name $report 2>/dev/null)
  if [[ ${total:-none} == none ]]; then
    print "== ${screen:-launch}: leaks couldn't read the process (did it crash? try a longer SETTLE)"
    STATUS=1
  else
    print "== ${screen:-launch}: $ours leaks in this code ($total in all, the rest the system's)"
    if (( ours )); then
      STATUS=1
      python3 $CLASSIFY $name $report 2>&1 >/dev/null | head -40
    fi
  fi
  xcrun simctl terminate $udid $id 2>/dev/null
done
exit $STATUS
