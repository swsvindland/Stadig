#!/usr/bin/env python3
"""Builds writing-passages.json for Stadig Mind: short prose passages to imitate, offline.

    python3 Scripts/build-writing-passages.py            # writes Packages/MindEngine/.../Resources/writing-passages.json
    python3 Scripts/build-writing-passages.py --cache DIR --out x.json

The passages feed two writing exercises. The Franklin method: read a passage, note the sense of each sentence in a
few words, rewrite it from the notes a few days later and compare with the original (what Franklin did with the
Spectator). Scene rewrites: retell a creative passage from another point of view, in another tense or in another mood.

Source: Project Gutenberg (https://www.gutenberg.org), one plain-text UTF-8 ebook per book, downloaded once into
~/Library/Caches/MindTrack/gutenberg (not the repo), with a pause between downloads. Every work here was first
published before 1929, and Project Gutenberg texts are in the public domain in the USA; the Gutenberg header, footer,
licence and trademark are removed and only short passages are kept.

Each passage is cut from its book between a start phrase and an end phrase (exact text, matched with whitespace
normalised). Hard line breaks are unwrapped and paragraphs kept, _italic_ underscores and footnote markers dropped,
double hyphens made dashes and quotes made curly. The build fails, listing every problem, if a book's title line isn't
the one expected, a phrase isn't found exactly once, or a passage isn't 110–230 words of whole sentences.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.expanduser("~/Library/Caches/MindTrack/gutenberg")
RESOURCES = os.path.join(ROOT, "Packages/MindEngine/Sources/MindEngine/Resources")
URL = "https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt"
USER_AGENT = "MindTrack-build-writing-passages/1.0 (one-off build script; each book fetched once, then cached)"
DELAY = 2  # seconds between downloads
MIN_WORDS, MAX_WORDS = 110, 230
KINDS = ("creative", "practical", "argument")

# Gutenberg ebook number: how its "Title:" line starts, so a wrong number fails instead of cutting the wrong book.
BOOKS = {
    8: "Abraham Lincoln's Second Inaugural Address",
    71: "On the Duty of Civil Disobedience",
    84: "Frankenstein",
    120: "Treasure Island",
    202: "My Bondage and My Freedom",
    205: "Walden",
    289: "The Wind in the Willows",
    345: "Dracula",
    944: "The Voyage of the Beagle",
    1184: "The Count of Monte Cristo",
    1260: "Jane Eyre",
    1342: "Pride and Prejudice",
    1400: "Great Expectations",
    1408: "The Natural History of Selborne",
    2554: "Crime and Punishment",
    2701: "Moby Dick",
    2944: "Essays — First Series",
    3020: "Table Talk",
    10060: "Discourses: Biological & Geological",
    10136: "The Book of Household Management",
    12030: "The Spectator, Volumes 1, 2 and 3",
    14474: "The Chemical History of a Candle",
    20203: "Autobiography of Benjamin Franklin",
    34901: "On Liberty",
    64317: "The Great Gatsby",
    71865: "Mrs. Dalloway",
}

# title is the work the passage comes from: the essay, paper or speech when the ebook is a collection.
# book is the reading ladder's id (ladder.json) or None; tier is on the ladder's 1–10 scale.
PASSAGES = [
    # Creative: a scene with a character, a place and something happening; two rewrites each.
    dict(id="austen-walk-to-netherfield", gutenberg=1342, title="Pride and Prejudice", author="Jane Austen", year=1813,
         book="pride-and-prejudice", kinds=["creative"], tier=5,
         start="In Meryton they parted", end="The latter was thinking only of his breakfast.",
         twists=["Rewrite it from Miss Bingley's point of view, watching Elizabeth come into the breakfast parlour.",
                 "Tell it as a letter Elizabeth writes to her mother that evening, leaving out the dirty stockings."]),
    dict(id="bronte-rider-on-the-ice", gutenberg=1260, title="Jane Eyre", author="Charlotte Brontë", year=1847,
         book="jane-eyre", kinds=["creative"], tier=5,
         start="It was very near, but not yet in sight", end="slipped on the sheet of ice which glazed the causeway.",
         twists=["Rewrite it from the rider's point of view: a tired man taking a short cut who barely notices the girl "
                 "on the stile until his horse goes down.",
                 "Tell it in the present tense, close on Jane, as if it were happening now."]),
    dict(id="shelley-the-creature-wakes", gutenberg=84, title="Frankenstein", author="Mary Shelley", year=1818,
         book="frankenstein", kinds=["creative"], tier=5,
         start="It was on a dreary night of November", end="his shrivelled complexion and straight black lips.",
         twists=["Rewrite it from the creature's point of view, opening its eyes for the first time.",
                 "Tell the same moment in half the words, keeping the rain, the candle and the eye."]),
    dict(id="stoker-count-on-the-wall", gutenberg=345, title="Dracula", author="Bram Stoker", year=1897,
         book="dracula", kinds=["creative"], tier=4,
         start="What I saw was the Count's head coming out from the window.",
         end="just as a lizard moves along a wall.",
         twists=["Rewrite it from the Count's point of view as he climbs down the wall, wondering whether his guest "
                 "is awake.",
                 "Tell it as a letter Jonathan Harker writes to Mina, trying not to frighten her."]),
    dict(id="fitzgerald-gatsbys-parties", gutenberg=64317, title="The Great Gatsby", author="F. Scott Fitzgerald",
         year=1925, book="the-great-gatsby", kinds=["creative"], tier=4,
         start="There was music from my neighbour's house", end="pressed two hundred times by a butler's thumb.",
         twists=["Rewrite it from the point of view of one of the eight servants, starting work on a Monday morning.",
                 "Change the season: the same house on a wet weekend in late September, after the guests have stopped "
                 "coming."]),
    dict(id="dumas-thrown-into-the-sea", gutenberg=1184, title="The Count of Monte Cristo", author="Alexandre Dumas",
         year=1844, book="the-count-of-monte-cristo", kinds=["creative"], tier=3,
         start="They ascended five or six more steps", end="The sea is the cemetery of the Château d'If.",
         twists=["Rewrite it from the point of view of one of the grave-diggers, who thinks the sack holds a dead "
                 "old priest.",
                 "Tell it in the first person, as Dantès, in the present tense."]),
    dict(id="dostoevsky-hot-evening", gutenberg=2554, title="Crime and Punishment", author="Fyodor Dostoevsky",
         year=1866, book="crime-and-punishment", kinds=["creative"], tier=6,
         start="On an exceptionally hot evening early in July", end="and was afraid of meeting her.",
         twists=["Rewrite it from the landlady's point of view, listening from her open kitchen door as he creeps past.",
                 "Move it to a bitter January morning and tell it in the present tense, close on the young man."]),
    dict(id="melville-call-me-ishmael", gutenberg=2701, title="Moby-Dick", author="Herman Melville", year=1851,
         book="moby-dick", kinds=["creative"], tier=8,
         start="Call me Ishmael.", end="cherish very nearly the same feelings towards the ocean with me.",
         twists=["Rewrite it in the third person and the present tense: show Ishmael on a drizzly November street "
                 "deciding to go to sea, rather than having him explain himself.",
                 "Change the mood: he goes to sea out of high spirits, not gloom. Keep the run of \"whenever\" clauses."]),
    dict(id="woolf-big-ben", gutenberg=71865, title="Mrs Dalloway", author="Virginia Woolf", year=1925,
         book="mrs-dalloway", kinds=["creative"], tier=7,
         start="For having lived in Westminster", end="life; London; this moment of June.",
         twists=["Rewrite it from the point of view of a neighbour who sees her waiting to cross Victoria Street as "
                 "Big Ben strikes.",
                 "Retell it as a plain past-tense account in half the words, keeping only what Clarissa sees and hears."]),
    dict(id="dickens-churchyard", gutenberg=1400, title="Great Expectations", author="Charles Dickens", year=1861,
         book=None, kinds=["creative"], tier=4,
         start="Ours was the marsh country", end="or I'll cut your throat!\"",
         twists=["Rewrite it from the convict's point of view, hiding among the graves as the boy comes into the "
                 "churchyard.",
                 "Change the weather and the mood: a warm, bright summer morning, and the voice that starts up is a "
                 "friendly one."]),
    dict(id="stevenson-apple-barrel", gutenberg=120, title="Treasure Island", author="Robert Louis Stevenson",
         year=1883, book=None, kinds=["creative"], tier=2,
         start="In I got bodily into the apple barrel", end="depended upon me alone.",
         twists=["Rewrite it from Long John Silver's point of view, sitting down against the barrel without knowing "
                 "anyone is inside.",
                 "Tell it in the present tense in no more than half the words."]),
    dict(id="grahame-mole-spring-cleaning", gutenberg=289, title="The Wind in the Willows", author="Kenneth Grahame",
         year=1908, book=None, kinds=["creative"], tier=2,
         start="The Mole had been working very hard all the morning",
         end="rolling in the warm grass of a great meadow.",
         twists=["Rewrite it from the point of view of a lark in the meadow that sees the Mole's snout pop out of the "
                 "grass.",
                 "Change the season: a wet November afternoon, the Mole longs to stay indoors, but something drives "
                 "him out."]),

    # Argument: essays and speeches that make a case in a short span.
    dict(id="addison-philosophy-in-coffee-houses", gutenberg=12030, title="The Spectator, No. 10",
         author="Joseph Addison", year=1711, book=None, kinds=["argument"], tier=6,
         start="Since I have raised to myself so great an Audience", end="at Tea-tables, and in Coffee-houses.",
         twists=[]),
    dict(id="steele-longing-for-retirement", gutenberg=12030, title="The Spectator, No. 27",
         author="Richard Steele", year=1711, book=None, kinds=["argument"], tier=6,
         start="There is scarce a thinking Man in the World", end="when he has a mind to go to Sleep.",
         twists=[]),
    dict(id="emerson-self-reliance", gutenberg=2944, title="Self-Reliance", author="Ralph Waldo Emerson", year=1841,
         book=None, kinds=["argument"], tier=6,
         start="To believe your own thought", end="come back to us with a certain alienated majesty.",
         twists=[]),
    dict(id="thoreau-civil-disobedience", gutenberg=71, title="On the Duty of Civil Disobedience",
         author="Henry David Thoreau", year=1849, book=None, kinds=["argument"], tier=5,
         start="I heartily accept the motto", end="the people would not have consented to this measure.",
         twists=[]),
    dict(id="mill-silencing-an-opinion", gutenberg=34901, title="On Liberty", author="John Stuart Mill", year=1859,
         book=None, kinds=["argument"], tier=7,
         start="If all mankind minus one, were of one opinion", end="produced by its collision with error.",
         twists=[]),
    dict(id="hazlitt-familiar-style", gutenberg=3020, title="On Familiar Style", author="William Hazlitt", year=1822,
         book=None, kinds=["argument"], tier=5,
         start="It is not easy to write a familiar style.", end="setting aside all pedantic and oratorical flourishes.",
         twists=[]),
    dict(id="douglass-fourth-of-july", gutenberg=202, title="What to the Slave Is the Fourth of July?",
         author="Frederick Douglass", year=1852, book=None, kinds=["argument"], tier=4,
         start="What to the American slave is your Fourth of July?", end="America reigns without a rival.",
         twists=[]),
    dict(id="lincoln-second-inaugural", gutenberg=8, title="Second Inaugural Address", author="Abraham Lincoln",
         year=1865, book=None, kinds=["argument"], tier=4,
         start="One-eighth of the whole population were colored slaves",
         end="that of neither has been answered fully.",
         twists=[]),

    # Practical: prose that explains, instructs or reports.
    dict(id="franklin-learning-from-the-spectator", gutenberg=20203, title="The Autobiography of Benjamin Franklin",
         author="Benjamin Franklin", year=1791, book=None, kinds=["practical"], tier=4,
         start="About this time I met with an odd volume of the", end="discovered some of my faults, and corrected them.",
         twists=[]),
    dict(id="darwin-galapagos-tortoises", gutenberg=944, title="The Voyage of the Beagle", author="Charles Darwin",
         year=1839, book=None, kinds=["practical"], tier=4,
         start="The tortoise is very fond of water", end="at the rate of about ten in a minute.",
         twists=[]),
    dict(id="huxley-burning-chalk", gutenberg=10060, title="On a Piece of Chalk", author="Thomas Henry Huxley",
         year=1868, book=None, kinds=["practical"], tier=4,
         start="We all know that if we", end="chalk is almost wholly composed of \"carbonate of lime.\"",
         twists=[]),
    dict(id="thoreau-borrowing-an-axe", gutenberg=205, title="Walden", author="Henry David Thoreau", year=1854,
         book="walden", kinds=["practical"], tier=6,
         start="Near the end of March, 1845, I borrowed an axe", end="come to commence another year with us.",
         twists=[]),
    dict(id="beeton-making-tea", gutenberg=10136, title="The Book of Household Management", author="Isabella Beeton",
         year=1861, book=None, kinds=["practical"], tier=3,
         start="There is very little art in making good tea", end="fresh tea made in the usual manner.",
         twists=[]),
    dict(id="faraday-the-candle-cup", gutenberg=14474, title="The Chemical History of a Candle",
         author="Michael Faraday", year=1861, book=None, kinds=["practical"], tier=3,
         start="You see, then, in the first instance, that a beautiful cup is formed.",
         end="which keeps the exterior of the candle cool.",
         twists=[]),
    dict(id="white-the-old-tortoise", gutenberg=1408, title="The Natural History of Selborne", author="Gilbert White",
         year=1789, book=None, kinds=["practical"], tier=5,
         start="A land-tortoise, which has been kept for thirty years",
         end="An instance of vast longevity in such a poor reptile!",
         twists=[]),
]


def fetch(cache, ids):
    os.makedirs(cache, exist_ok=True)
    downloaded = False
    for book in sorted(ids):
        path = os.path.join(cache, f"pg{book}.txt")
        if os.path.exists(path) and os.path.getsize(path) > 0:
            continue
        if downloaded:
            time.sleep(DELAY)
        url = URL.format(id=book)
        print(f"Downloading {url}")
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=60) as response, open(path + ".part", "wb") as f:
            f.write(response.read())
        os.replace(path + ".part", path)
        downloaded = True


def curly(text):
    """Straight quotes to curly ones; a quote opens after a space, a bracket, a dash or another opening quote."""
    text = re.sub(r'(?<=—)"(?=[\w‘\'])', "“", text)
    text = re.sub(r'(^|[\s(\[{‘])"', r"\1“", text).replace('"', "”")
    # Elisions such as 'tis and 'em take an apostrophe, not an opening quote.
    text = re.sub(r"(^|[\s(\[{“—])'(?=(?:tis|twas|twere|twill|twould|em|neath|gainst)\b)", r"\1’", text, flags=re.I)
    text = re.sub(r"(?<=—)'(?=\w)", "‘", text)
    return re.sub(r"(^|[\s(\[{“])'", r"\1‘", text).replace("'", "’")


def clean(paragraph):
    p = re.sub(r"\s+", " ", paragraph.replace(" ", " ")).strip()
    p = re.sub(r"\s*\[\d{1,3}\]", "", p)            # footnote markers: Spectator.[18]
    p = re.sub(r"(?<=[\w.,;:!?’”'\"])\(\d{1,2}\)", "", p)  # and mother-tongue.(1)
    p = re.sub(r"(?<=[\w.,;:!?’”'\"])\*+", "", p)    # and crib,’*
    p = re.sub(r"_([^_]+)_", r"\1", p).replace("_", "")
    p = re.sub(r"-{2,}", "—", p)
    return curly(p)


def book_text(cache, book):
    """The ebook between its START and END lines, one cleaned paragraph per block, paragraphs joined by blank lines."""
    with open(os.path.join(cache, f"pg{book}.txt"), encoding="utf-8-sig") as f:
        raw = f.read().replace("\r\n", "\n").replace("\r", "\n")
    title = re.search(r"^Title:\s*(.+)$", raw, re.M)
    if not title or not title.group(1).strip().startswith(BOOKS[book]):
        raise ValueError(f"Gutenberg #{book} is titled {title.group(1).strip() if title else '(none)'!r}, "
                         f"expected {BOOKS[book]!r}")
    start = re.search(r"^\*\*\* ?START OF.*$", raw, re.M)
    end = re.search(r"^\*\*\* ?END OF.*$", raw, re.M)
    if not start or not end or end.start() < start.end():
        raise ValueError(f"Gutenberg #{book} has no START/END lines")
    blocks = re.split(r"\n[ \t]*\n", raw[start.end():end.start()])
    return "\n\n".join(c for c in (clean(b) for b in blocks) if c)


def phrase_pattern(phrase):
    """Matches the phrase with any run of whitespace for a space and either curly quote for a straight one."""
    parts = []
    for ch in re.sub(r"\s+", " ", phrase.strip()):
        parts.append(r"\s+" if ch == " " else "[‘’]" if ch in "'‘’" else "[“”]" if ch in '"“”' else re.escape(ch))
    return re.compile("".join(parts))


def cut(text, start, end):
    starts = list(phrase_pattern(start).finditer(text))
    if len(starts) != 1:
        raise ValueError(f"start phrase {start!r} found {len(starts)} times")
    finish = phrase_pattern(end).search(text, starts[0].end())
    if not finish:
        raise ValueError(f"end phrase {end!r} not found after the start")
    return text[starts[0].start():finish.end()]


def check(p, text, ladder):
    """Problems with one passage, as messages; none means it's fine."""
    problems = []
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", p["id"]):
        problems.append("id isn't kebab-case")
    words = len(text.split())
    if not MIN_WORDS <= words <= MAX_WORDS:
        problems.append(f"{words} words, outside {MIN_WORDS}–{MAX_WORDS}")
    if not re.match(r"[A-Z“‘]", text) or not re.search(r"[.!?][”’]?$", text):
        problems.append("doesn't start and end on a whole sentence")
    if re.search(r"[\[\]_*\"']|--", text):
        problems.append("leftover markup, a straight quote or a double hyphen")
    for para in text.split("\n\n"):
        if para.isupper() or re.match(r"(CHAPTER|Chapter|BOOK|LETTER|ESSAY|No\. \d)", para):
            problems.append(f"looks like a heading: {para[:40]!r}")
    if not p["kinds"] or any(k not in KINDS for k in p["kinds"]):
        problems.append(f"kinds {p['kinds']} aren't from {KINDS}")
    if not 1 <= p["tier"] <= 10:
        problems.append(f"tier {p['tier']} isn't 1–10")
    if p["book"] is not None and p["book"] not in ladder:
        problems.append(f"book {p['book']!r} isn't on the reading ladder")
    elif p["book"] is not None and abs(ladder[p["book"]] - p["tier"]) > 1:
        problems.append(f"tier {p['tier']} is far from the ladder's {ladder[p['book']]}")
    if not isinstance(p["year"], int) or p["year"] >= 1929:
        problems.append(f"year {p['year']} isn't before 1929")
    if "creative" in p["kinds"]:
        if len(p["twists"]) != 2:
            problems.append("a creative passage needs two twists")
    elif p["twists"]:
        problems.append("only creative passages have twists")
    return problems


def build(cache, out):
    ids = [p["id"] for p in PASSAGES]
    duplicates = {i for i in ids if ids.count(i) > 1}
    if duplicates:
        sys.exit(f"Duplicate passage ids: {', '.join(sorted(duplicates))}")
    fetch(cache, {p["gutenberg"] for p in PASSAGES})
    with open(os.path.join(RESOURCES, "ladder.json"), encoding="utf-8") as f:
        ladder = {b["id"]: b["tier"] for b in json.load(f)["books"]}

    texts, passages, problems = {}, [], []
    for p in PASSAGES:
        try:
            if p["gutenberg"] not in texts:
                texts[p["gutenberg"]] = book_text(cache, p["gutenberg"])
            text = cut(texts[p["gutenberg"]], p["start"], p["end"])
        except ValueError as e:
            problems.append(f"{p['id']}: {e}")
            continue
        problems += [f"{p['id']}: {m}" for m in check(p, text, ladder)]
        passages.append({
            "id": p["id"], "title": p["title"], "author": p["author"], "year": p["year"],
            "gutenberg": p["gutenberg"], "book": p["book"], "kinds": p["kinds"], "tier": p["tier"],
            "text": text, "twists": [curly(t) for t in p["twists"]],
        })
        print(f"  {p['id']:40} {len(text.split()):3} words, tier {p['tier']}, {'/'.join(p['kinds'])}")
    if problems:
        sys.exit("Passages that need fixing:\n  " + "\n  ".join(problems))

    passages.sort(key=lambda p: p["id"])
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"passages": passages}, f, ensure_ascii=False, indent=2)
        f.write("\n")
    kinds = {k: sum(k in p["kinds"] for p in passages) for k in KINDS}
    print(f"Wrote {out}: {len(passages)} passages ({', '.join(f'{n} {k}' for k, n in kinds.items())}) "
          f"from {len({p['gutenberg'] for p in passages})} books")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cache", default=CACHE, help="where downloaded ebooks are kept (default: %(default)s)")
    parser.add_argument("--out", default=os.path.join(RESOURCES, "writing-passages.json"))
    args = parser.parse_args()
    build(os.path.expanduser(args.cache), args.out)
