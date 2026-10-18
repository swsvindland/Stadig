"""Reads a `leaks --fullStacks` report and says which leaks are this app's own.

Usage: python3 Scripts/classify-leaks.py <AppName> <report>
Prints "<leaks in all> <leaks in this code>" (or "none 0" when the report has no count, meaning
leaks couldn't read the process), and the stacks of this code's leaks on stderr.

A leak is this code's when its allocation stack runs through the app's own code (its
<AppName>.debug.dylib, which holds the app and its packages in a Debug build), other than the entry
point. The rest are the system's: dyld, SwiftUI, FoundationModels, or allocated before malloc stack
logging began (NO STACK).
"""
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
    # dyld image maps belong to the system, whoever loaded the image (Metal loads one under SwiftUI).
    if frames and "map_images_nolock" not in tree:
        count = re.search(r"^\s*(\d+) \(", tree, re.M)
        ours += int(count.group(1)) if count else 1
        shown.append(tree.strip().splitlines()[0] + "\n" + "\n".join("      " + f.strip() for f in frames[:8]))
print(total.group(1), ours)
for s in shown:
    print(s, file=sys.stderr)
