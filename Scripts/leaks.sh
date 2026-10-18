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
# The same per-checkout DerivedData and simulator Scripts/build.sh uses.
CHECKOUT=$(print -r -- $PWD | shasum | cut -c1-6)
DD=${DERIVED_DATA:-/tmp/system-dd-$CHECKOUT}
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

udid=${SIMULATOR:-$(xcrun simctl list devices available -j | jq -r --arg n "Stadig Tests $CHECKOUT" '[.devices[][] | select(.name == $n)][0].udid // empty')}
[[ -n $udid ]] || { print -u2 "No simulator: run Scripts/build.sh unit $APP once, or set SIMULATOR"; exit 2 }
app=$DD/Build/Products/Debug-iphonesimulator/$name.app
[[ -d $app ]] || { print -u2 "No build at $app: run Scripts/build.sh first"; exit 2 }
xcrun simctl boot $udid 2>/dev/null
xcrun simctl install $udid $app || exit 1

# Which leaks are this code's: one whose allocation stack runs through the app's own code (its
# .debug.dylib, which holds the app and its packages in a Debug build), other than the entry point.
# The rest are the system's (dyld, SwiftUI, FoundationModels, or allocated before logging began).
CLASSIFY='
import re, sys
name, text = sys.argv[1], open(sys.argv[2]).read()
total = re.search(r"(\d+) leaks? for", text)
if not total:
    print("none 0"); sys.exit()
ours, shown = 0, []
for block in re.split(r"\n(?=STACK OF|NO STACK)", text):
    if "ROOT LEAK" not in block and "ROOT CYCLE" not in block:
        continue
    stack, _, tree = block.partition("====")
    frames = [l for l in stack.splitlines() if f"{name}.debug.dylib" in l or re.search(rf"\b{name}\b\s+0x", l)]
    # The entry point is in every stack (in a Debug build, __debug_main_executable_dylib_entry_point).
    frames = [l for l in frames if not re.search(r"\bmain\b|\$main|App\.main|_entry_point", l)]
    # dyld's image map is the system's whoever loaded the image (Metal loads one under SwiftUI).
    if frames and "map_images_nolock" not in tree:
        count = re.search(r"^\s*(\d+) \(", tree, re.M)
        ours += int(count.group(1)) if count else 1
        shown.append(tree.strip().splitlines()[0] + "\n" + "\n".join("      " + f.strip() for f in frames[:8]))
print(total.group(1), ours)
for s in shown:
    print(s, file=sys.stderr)
'

STATUS=0
report=$(mktemp)
trap 'rm -f $report' EXIT
# Quoted, so the plain launch ("") is checked too.
for screen in "${screens[@]}"; do
  pid=$(SIMCTL_CHILD_MallocStackLogging=1 xcrun simctl launch --terminate-running-process $udid $id \
    -uiTesting -seedSampleData ${=screen} | awk '{ print $NF }')
  sleep $SETTLE
  leaks --fullStacks $pid > $report 2>/dev/null
  read -r total ours < <(python3 -c $CLASSIFY $name $report 2>/dev/null)
  if [[ ${total:-none} == none ]]; then
    print "== ${screen:-launch}: leaks couldn't read the process (did it crash? try a longer SETTLE)"
    STATUS=1
  else
    print "== ${screen:-launch}: $ours leaks in this code ($total in all, the rest the system's)"
    if (( ours )); then
      STATUS=1
      python3 -c $CLASSIFY $name $report 2>&1 >/dev/null | head -40
    fi
  fi
  xcrun simctl terminate $udid $id 2>/dev/null
done
exit $STATUS
