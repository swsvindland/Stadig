#!/usr/bin/env python3
"""Checks Stadig Mind's writing prompts against their schema and house style.

    python3 Scripts/check-writing-prompts.py              # checks the bundled writing-prompts.json
    python3 Scripts/check-writing-prompts.py other.json

Prints every problem it finds and exits 1, or prints the counts and exits 0. Standard library only.

Schema: {"prompts": [...]}, each prompt exactly {id, exercise, kind, text}, plus "source" on a
practical task (the original to rewrite, 40-160 words) and "minutes" on a benchmark. Exercise and
kind pair up as prompt/creative, argument/argument and practical/practical; a benchmark takes any
kind, and there is exactly one per kind, with the id benchmark-<kind>. Other ids are kebab-case and
start with their kind. The app appends the length itself, so prompt text never mentions one.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

DEFAULT_PATH = (Path(__file__).resolve().parent.parent
                / "Packages/MindEngine/Sources/MindEngine/Resources/writing-prompts.json")

KINDS = ("creative", "practical", "argument")
KIND_FOR_EXERCISE = {"prompt": "creative", "argument": "argument", "practical": "practical"}
EXERCISES = (*KIND_FOR_EXERCISE, "benchmark")
REQUIRED_KEYS = {"id", "exercise", "kind", "text"}
EXTRA_KEYS = {"practical": {"source"}, "benchmark": {"minutes"}}
SOURCE_WORDS = range(40, 161)
MINUTES = range(1, 61)
MAX_IMAGINE_OPENERS = 2

KEBAB_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)+$")
# The app adds "Write one paragraph." or similar, so the prompt itself must not set a length.
LENGTH_TALK = re.compile(
    r"\bparagraphs?\b|\bword[- ]?counts?\b|\bwords? long\b|\blength\b"
    r"|\b(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|twenty|fifty|hundred)\s+words\b",
    re.IGNORECASE)
AMERICAN_SPELLING = re.compile(
    r"\b(?:colors?|colored|favorites?|favors?|flavors?|honors?|humors?|labors?|neighbors?"
    r"|behaviors?|centers?|theaters?|jewelry|gray|mom"
    r"|\w*(?:organiz|realiz|apologiz|recogniz|analyz|prioritiz|emphasiz|minimiz)\w*"
    r"|traveled|traveling|canceled|canceling|labeled|labeling)\b",
    re.IGNORECASE)
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿️]")


def word_count(s):
    return sum(1 for token in s.split() if any(c.isalnum() for c in token))


def style_problems(field, value):
    problems = []
    if "'" in value or '"' in value:
        problems.append(f"{field} has a straight quote or apostrophe; use ’ “ ”")
    if value.count("“") != value.count("”"):
        problems.append(f"{field} has unbalanced “ ” quotes")
    if "!" in value:
        problems.append(f"{field} has an exclamation mark")
    if EMOJI.search(value):
        problems.append(f"{field} has an emoji")
    for match in AMERICAN_SPELLING.finditer(value):
        problems.append(f"{field} uses American spelling “{match.group(0)}”")
    if value != value.strip():
        problems.append(f"{field} has leading or trailing whitespace")
    return problems


def check(data):
    problems = []
    if not isinstance(data, dict):
        return ["top level must be an object with a \"prompts\" array"]
    for key in sorted(set(data) - {"prompts"}):
        problems.append(f"unknown top-level key {key!r}")
    prompts = data.get("prompts")
    if not isinstance(prompts, list) or not prompts:
        return problems + ["\"prompts\" must be a non-empty array"]

    ids = Counter()
    benchmarks = Counter()
    imagine_openers = []
    for index, prompt in enumerate(prompts):
        where = f"prompts[{index}]"
        if not isinstance(prompt, dict):
            problems.append(f"{where} is not an object")
            continue
        pid = prompt.get("id")
        if isinstance(pid, str) and pid:
            where = f"{where} ({pid})"
            ids[pid] += 1
        exercise, kind = prompt.get("exercise"), prompt.get("kind")

        for key in sorted(REQUIRED_KEYS - set(prompt)):
            problems.append(f"{where} is missing {key!r}")
        allowed = REQUIRED_KEYS | EXTRA_KEYS.get(exercise, set())
        for key in sorted(set(prompt) - allowed):
            if key in {"source", "minutes"}:
                owner = "practical tasks" if key == "source" else "benchmarks"
                problems.append(f"{where} has {key!r}, which only {owner} take")
            else:
                problems.append(f"{where} has unknown key {key!r}")

        if exercise not in EXERCISES:
            problems.append(f"{where} has unknown exercise {exercise!r}")
        if kind not in KINDS:
            problems.append(f"{where} has unknown kind {kind!r}")
        if exercise in KIND_FOR_EXERCISE and kind in KINDS and kind != KIND_FOR_EXERCISE[exercise]:
            problems.append(f"{where} pairs exercise {exercise!r} with kind {kind!r}; "
                            f"it must be {KIND_FOR_EXERCISE[exercise]!r}")

        if not isinstance(pid, str) or not pid:
            problems.append(f"{where} needs a non-empty string id")
        elif not KEBAB_ID.match(pid):
            problems.append(f"{where} id is not kebab-case")
        elif exercise == "benchmark":
            if kind in KINDS and pid != f"benchmark-{kind}":
                problems.append(f"{where} benchmark id must be 'benchmark-{kind}'")
        elif kind in KINDS and not pid.startswith(f"{kind}-"):
            problems.append(f"{where} id must start with '{kind}-'")

        text = prompt.get("text")
        if not isinstance(text, str) or not text.strip():
            problems.append(f"{where} has empty text")
        else:
            problems += style_problems(f"{where} text", text)
            if LENGTH_TALK.search(text):
                problems.append(f"{where} text mentions length (“{LENGTH_TALK.search(text).group(0)}”); "
                                "the app adds that")
            if text.lstrip().lower().startswith("imagine"):
                imagine_openers.append(pid)

        if exercise == "practical":
            source = prompt.get("source")
            if not isinstance(source, str) or not source.strip():
                problems.append(f"{where} is a practical task without a source")
            else:
                problems += style_problems(f"{where} source", source)
                words = word_count(source)
                if words not in SOURCE_WORDS:
                    problems.append(f"{where} source is {words} words; it must be "
                                    f"{SOURCE_WORDS.start}-{SOURCE_WORDS.stop - 1}")

        if exercise == "benchmark":
            if kind in KINDS:
                benchmarks[kind] += 1
            minutes = prompt.get("minutes")
            if isinstance(minutes, bool) or not isinstance(minutes, int):
                problems.append(f"{where} benchmark needs whole-number minutes")
            elif minutes not in MINUTES:
                problems.append(f"{where} minutes {minutes} is outside "
                                f"{MINUTES.start}-{MINUTES.stop - 1}")

    for pid, count in sorted(ids.items()):
        if count > 1:
            problems.append(f"id {pid!r} is used {count} times")
    for kind in KINDS:
        if benchmarks[kind] != 1:
            problems.append(f"there must be exactly one {kind} benchmark, found {benchmarks[kind]}")
    if len(imagine_openers) > MAX_IMAGINE_OPENERS:
        problems.append(f"{len(imagine_openers)} prompts open with “Imagine” "
                        f"(at most {MAX_IMAGINE_OPENERS}): {', '.join(imagine_openers)}")
    return problems


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        sys.exit(f"FAIL: cannot read {path}: {error}")

    problems = check(data)
    if problems:
        print(f"FAIL: {len(problems)} problem(s) in {path}", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        sys.exit(1)

    counts = Counter(p["exercise"] for p in data["prompts"])
    summary = ", ".join(f"{counts[e]} {e}" for e in EXERCISES)
    sources = [word_count(p["source"]) for p in data["prompts"] if p["exercise"] == "practical"]
    span = f"; practical sources {min(sources)}-{max(sources)} words" if sources else ""
    print(f"OK: {len(data['prompts'])} prompts in {path.name} ({summary}){span}")


if __name__ == "__main__":
    main()
