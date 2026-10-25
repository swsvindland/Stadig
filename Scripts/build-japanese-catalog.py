#!/usr/bin/env python3
"""Builds japanese.db for Stadig Mind: words, kanji and example sentences, offline.

    python3 Scripts/build-japanese-catalog.py            # writes Apps/MindTrack/Catalogs/japanese.db
    python3 Scripts/build-japanese-catalog.py --out x.db

Sources, downloaded once (about 45 MB) into ~/Library/Caches/SystemJapaneseCatalog:
- JMdict (English) and KANJIDIC2 from the Electronic Dictionary Research and Development Group,
  under CC BY-SA 4.0 (https://www.edrdg.org/edrdg/licence.html).
- Tatoeba's Japanese sentences, their English translations and the Japanese indices (the Tanaka
  corpus word links), under CC BY 2.0 FR (https://tatoeba.org/en/terms_of_use).

Word order is how common a word is in everyday sentences: how many Tatoeba sentences use it, with
JMdict's newspaper and ichimango frequency marks as a tiebreak. Particles, the copula and other
grammar words aren't vocabulary cards; they're free in sentences. A sentence is kept when every
word in it is in the deck, and its level is its rarest word's rank.
"""
import argparse
import bz2
import gzip
import math
import os
import re
import sqlite3
import sys
import tarfile
import time
import urllib.request
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.expanduser("~/Library/Caches/SystemJapaneseCatalog")
SOURCES = {
    "JMdict_e.gz": "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz",
    "kanjidic2.xml.gz": "http://www.edrdg.org/kanjidic/kanjidic2.xml.gz",
    "jpn_indices.tar.bz2": "https://downloads.tatoeba.org/exports/jpn_indices.tar.bz2",
    "jpn_sentences.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/jpn/jpn_sentences.tsv.bz2",
    "eng_sentences.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2",
    "jpn-eng_links.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/jpn/jpn-eng_links.tsv.bz2",
}

WORD_LIMIT = 20000
SENTENCE_MAX_CHARS = 40
# Parts of speech that are grammar, not vocabulary: free in sentences, never a card.
GRAMMAR_POS = ("particle", "copula", "auxiliary", "prefix", "suffix", "counter")
# Set phrases built from particles and the copula: grammar too.
GRAMMAR_WORDS = {"には", "では", "とは", "である", "について", "として", "によって", "による", "にとって", "に対して",
                 "のに", "ので", "けど", "けれど", "けれども", "だろう", "でしょう", "かもしれない", "かも知れない",
                 "なければならない", "ではない", "じゃない", "という", "と言う", "ている", "てる", "ておく", "てしまう",
                 "ですか", "のです", "んです", "のだ", "んだ", "ません", "ましょう"}
USUALLY_KANA = "word usually written using kana alone"
# Senses JMdict marks as archaic, obsolete or rare don't make the short meaning.
SKIP_MISC = ("archaic", "obsolete", "rare term", "obscure term")
# Words whose first JMdict sense isn't the one a learner meets first: ため is "for the sake of", not "good".
MEANING_OVERRIDES = {"ため": "for the sake of", "よう": "like; as if", "はず": "should be (expected)", "わけ": "reason",
                     "つもり": "intention", "ほう": "side; direction", "まま": "as it is", "ところ": "place", "とき": "time; when"}
TOKEN = re.compile(r"^(?P<head>[^(\[{~]+)(?:\((?P<reading>[^)]+)\))?(?:\[(?P<sense>\d+)\])?(?:\{(?P<surface>[^}]+)\})?~?$")


def fetch():
    os.makedirs(CACHE, exist_ok=True)
    for name, url in SOURCES.items():
        path = os.path.join(CACHE, name)
        if os.path.exists(path) and os.path.getsize(path) > 0:
            continue
        print(f"Downloading {url}")
        urllib.request.urlretrieve(url, path + ".part")
        os.replace(path + ".part", path)


def text(el, tag):
    return [c.text or "" for c in el.findall(tag)]


def pos_kind(pos):
    """A coarse part of speech, for picking believable wrong answers, from the first one listed
    (勉強 is a noun that takes する, not a verb)."""
    p = (pos[0] if pos else "").lower()
    if "pre-noun" in p:
        return "pre-noun"
    if "verb" in p and "adverb" not in p and "auxiliary" not in p:
        return "verb"
    if "adjective (keiyoushi)" in p or "yoi/ii" in p:
        return "i-adjective"
    if "adjectival nouns" in p or "quasi-adjectives" in p:
        return "na-adjective"
    if "adverb" in p:
        return "adverb"
    if "expressions" in p:
        return "expression"
    if "interjection" in p:
        return "interjection"
    if "conjunction" in p:
        return "conjunction"
    if "pronoun" in p:
        return "pronoun"
    if "noun" in p:
        return "noun"
    return "other"


def is_grammar(entry):
    pos = entry["senses"][0][0] if entry["senses"] else []
    # By the first part of speech listed: と is a particle first and a conjunction second.
    if pos and pos[0].lower().startswith(GRAMMAR_POS):
        return True
    return any(k[0] in GRAMMAR_WORDS for k in entry["kebs"]) or (not entry["kebs"] and entry["rebs"][0][0] in GRAMMAR_WORDS)


def usually_kana(entry):
    return bool(entry["senses"]) and any(USUALLY_KANA in m for m in entry["senses"][0][1])


def parse_jmdict():
    entries = {}
    with gzip.open(os.path.join(CACHE, "JMdict_e.gz"), "rb") as f:
        for _, el in ET.iterparse(f, events=("end",)):
            if el.tag != "entry":
                continue
            seq = int(el.findtext("ent_seq"))
            kebs = [(k.findtext("keb"), set(text(k, "ke_pri")), text(k, "ke_inf")) for k in el.findall("k_ele")]
            rebs = [(r.findtext("reb"), set(text(r, "re_pri")), r.find("re_nokanji") is not None, text(r, "re_restr"),
                     text(r, "re_inf")) for r in el.findall("r_ele")]
            senses = []
            pos = []
            for s in el.findall("sense"):
                pos = text(s, "pos") or pos  # pos carries over to following senses
                senses.append((pos, text(s, "misc"), text(s, "gloss")))
            entries[seq] = {"kebs": kebs, "rebs": rebs, "senses": senses}
            el.clear()
    return entries


def priority(entry):
    pri = set()
    for k in entry["kebs"]:
        pri |= k[1]
    for r in entry["rebs"]:
        pri |= r[1]
    common = bool(pri & {"news1", "ichi1", "spec1", "spec2", "gai1"})
    nf = min([int(p[2:]) for p in pri if p.startswith("nf")] or [99])
    return common, nf


def forms(entry):
    """(display, kana, kanji): what to show, its reading, and the kanji spelling if there is one."""
    kebs = [k for k in entry["kebs"] if not any("search-only" in i or "irregular" in i or "rarely" in i for i in k[2])]
    keb = (sorted(kebs, key=lambda k: not k[1]) or [None])[0]
    kanji = keb[0] if keb else None

    def fits(r):
        return not r[2] and (not r[3] or (kanji in r[3]))

    rebs = [r for r in entry["rebs"] if not any("search-only" in i for i in r[4])]
    candidates = [r for r in rebs if fits(r)] if kanji else rebs
    reb = sorted(candidates or rebs or entry["rebs"], key=lambda r: not r[1])[0]
    kana = reb[0]
    display = kana if (usually_kana(entry) or not kanji) else kanji
    return display, kana, kanji


def short_meaning(entry):
    for pos, misc, glosses in entry["senses"]:
        if glosses and not any(any(s in m for s in SKIP_MISC) for m in misc):
            return clip(glosses[0])
    return clip(entry["senses"][0][2][0]) if entry["senses"] and entry["senses"][0][2] else ""


def clip(gloss, limit=40):
    # "cat (esp. the domestic cat, Felis catus)" is "cat" as an answer choice; the full senses stay in `meanings`.
    bare = gloss
    while re.search(r"\([^()]*\)", bare):
        bare = re.sub(r"\s*\([^()]*\)", "", bare)
    bare = bare.strip()
    gloss = bare or gloss.strip()
    return gloss if len(gloss) <= limit else gloss[: limit - 1].rstrip() + "…"


def long_meaning(entry):
    parts = []
    for pos, misc, glosses in entry["senses"]:
        if any(any(s in m for s in SKIP_MISC) for m in misc) and parts:
            continue
        parts.append(", ".join(glosses[:3]))
        if len(parts) == 3:
            break
    return "; ".join(parts)


def parse_indices(entries):
    """Maps each indexed sentence to JMdict entries and counts how often each entry is used."""
    by_keb, by_reb = {}, {}
    for seq, e in entries.items():
        for k in e["kebs"]:
            by_keb.setdefault(k[0], []).append(seq)
        for r in e["rebs"]:
            by_reb.setdefault(r[0], []).append(seq)

    def resolve(head, reading):
        if head in by_keb:
            seqs = by_keb[head]
        else:
            # A headword in kana means the kana spelling: は is the particle, not 葉 (leaf).
            candidates = by_reb.get(head, [])
            grammar = [s for s in candidates if is_grammar(entries[s])]
            if grammar and len(head) <= 2:
                seqs = grammar  # の, と and たい in a sentence are the particles and the auxiliary
            else:
                seqs = [s for s in candidates if not entries[s]["kebs"] or usually_kana(entries[s])] or candidates
        if reading:
            narrowed = [s for s in seqs if any(r[0] == reading for r in entries[s]["rebs"])]
            seqs = narrowed or seqs
        if not seqs:
            return None
        return sorted(seqs, key=lambda s: (not priority(entries[s])[0], priority(entries[s])[1], s))[0]

    counts = {}
    sentences = []
    with tarfile.open(os.path.join(CACHE, "jpn_indices.tar.bz2"), "r:bz2") as tar:
        member = next(m for m in tar.getmembers() if m.name.endswith(".csv"))
        for raw in tar.extractfile(member):
            parts = raw.decode("utf-8").rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            jpn_id, eng_id, line = int(parts[0]), int(parts[1]), parts[2]
            seqs, ok = [], True
            for token in line.split():
                m = TOKEN.match(token)
                seq = resolve(m.group("head"), m.group("reading")) if m else None
                if seq is None:
                    ok = False
                    break
                seqs.append(seq)
            if not ok:
                continue
            for seq in set(seqs):
                counts[seq] = counts.get(seq, 0) + 1
            sentences.append((jpn_id, eng_id, seqs))
    return counts, sentences


def rank_words(entries, counts):
    scored = []
    for seq, e in entries.items():
        if not e["senses"]:
            continue
        if is_grammar(e):
            continue
        common, nf = priority(e)
        count = counts.get(seq, 0)
        if count < 2 and not common:
            continue
        score = math.log1p(count) + (1.0 if common else 0) + (max(0, 48 - nf) / 48 * 1.5 if nf < 99 else 0)
        scored.append((score, seq))
    scored.sort(key=lambda x: (-x[0], x[1]))
    return [seq for _, seq in scored[:WORD_LIMIT]]


def read_tsv_bz2(name, keep=None):
    out = {}
    with bz2.open(os.path.join(CACHE, name), "rt", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            sid = int(parts[0])
            if keep is None or sid in keep:
                out[sid] = parts[2]
    return out


def parse_kanjidic():
    rows = []
    with gzip.open(os.path.join(CACHE, "kanjidic2.xml.gz"), "rb") as f:
        for _, el in ET.iterparse(f, events=("end",)):
            if el.tag != "character":
                continue
            misc = el.find("misc")
            grade = misc.findtext("grade")
            freq = misc.findtext("freq")
            jlpt = misc.findtext("jlpt")
            if grade or freq or jlpt:
                rm = el.find("reading_meaning")
                group = rm.find("rmgroup") if rm is not None else None
                meanings, on, kun = [], [], []
                if group is not None:
                    meanings = [m.text for m in group.findall("meaning") if "m_lang" not in m.attrib]
                    on = [r.text for r in group.findall("reading") if r.get("r_type") == "ja_on"]
                    kun = [r.text for r in group.findall("reading") if r.get("r_type") == "ja_kun"]
                rows.append((el.findtext("literal"), "; ".join(meanings[:4]), "、".join(on[:3]), "、".join(kun[:3]),
                             int(misc.findtext("stroke_count") or 0), int(grade) if grade else None,
                             int(jlpt) if jlpt else None, int(freq) if freq else None))
            el.clear()
    return rows


def trim(sentences, per_word=12):
    """Up to `per_word` of the easiest, shortest sentences for every word, so each word has
    examples at a beginner's level without keeping all of Tatoeba."""
    by_word = {}
    for row in sorted(sentences, key=lambda r: (r[3], r[4])):
        for w in row[5]:
            bucket = by_word.setdefault(w, [])
            if len(bucket) < per_word:
                bucket.append(row[0])
    keep = {sid for ids in by_word.values() for sid in ids}
    return [row for row in sentences if row[0] in keep]


def kanji_in(word):
    return "".join(ch for ch in word if "一" <= ch <= "鿿" or ch == "々")


def build(out):
    start = time.time()
    fetch()
    print("Reading JMdict…")
    entries = parse_jmdict()
    print(f"  {len(entries):,} entries")
    print("Reading the Tatoeba indices…")
    counts, indexed = parse_indices(entries)
    print(f"  {len(indexed):,} sentences fully indexed")
    ranked = rank_words(entries, counts)
    rank_of = {seq: i + 1 for i, seq in enumerate(ranked)}
    grammar = {seq for seq, e in entries.items() if is_grammar(e)}

    print("Choosing sentences…")
    candidates = []
    for jpn_id, eng_id, seqs in indexed:
        content = [s for s in seqs if s not in grammar]
        if not content or any(s not in rank_of for s in content):
            continue
        candidates.append((jpn_id, eng_id, sorted(set(content), key=lambda s: rank_of[s])))
    jpn = read_tsv_bz2("jpn_sentences.tsv.bz2", {c[0] for c in candidates})
    links = {}
    with bz2.open(os.path.join(CACHE, "jpn-eng_links.tsv.bz2"), "rt", encoding="utf-8") as f:
        for line in f:
            a, b = line.split("\t")[:2]
            links.setdefault(int(a), int(b))
    eng_ids = {c[1] for c in candidates} | {links[c[0]] for c in candidates if c[0] in links}
    eng = read_tsv_bz2("eng_sentences.tsv.bz2", eng_ids)
    sentences = []
    seen = set()
    for jpn_id, eng_id, content in candidates:
        jp = jpn.get(jpn_id)
        en = eng.get(eng_id) or eng.get(links.get(jpn_id, -1))
        if not jp or not en or len(jp) > SENTENCE_MAX_CHARS or jp in seen:
            continue
        seen.add(jp)
        sentences.append((jpn_id, jp, en, max(rank_of[s] for s in content), len(jp), content))
    sentences = trim(sentences)
    print(f"  {len(sentences):,} sentences kept")

    print("Reading KANJIDIC2…")
    kanji = parse_kanjidic()

    if os.path.exists(out):
        os.remove(out)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    db = sqlite3.connect(out)
    db.executescript("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE words (id INTEGER PRIMARY KEY, rank INTEGER NOT NULL, word TEXT NOT NULL, kana TEXT NOT NULL,
            kanji TEXT, meaning TEXT NOT NULL, meanings TEXT NOT NULL, pos TEXT NOT NULL, uses INTEGER NOT NULL,
            kanji_chars TEXT NOT NULL);
        CREATE TABLE kanji (literal TEXT PRIMARY KEY, meanings TEXT NOT NULL, onyomi TEXT NOT NULL, kunyomi TEXT NOT NULL,
            strokes INTEGER NOT NULL, grade INTEGER, jlpt INTEGER, freq INTEGER);
        CREATE TABLE sentences (id INTEGER PRIMARY KEY, jp TEXT NOT NULL, en TEXT NOT NULL, level INTEGER NOT NULL,
            length INTEGER NOT NULL, words TEXT NOT NULL);
        CREATE TABLE sentence_words (word INTEGER NOT NULL, level INTEGER NOT NULL, sentence INTEGER NOT NULL,
            PRIMARY KEY (word, level, sentence)) WITHOUT ROWID;
    """)
    rows = []
    for seq in ranked:
        e = entries[seq]
        display, kana, kanji_form = forms(e)
        meaning = MEANING_OVERRIDES.get(display) or short_meaning(e)
        rows.append((seq, rank_of[seq], display, kana, kanji_form, meaning, long_meaning(e),
                     pos_kind(e["senses"][0][0]), counts.get(seq, 0), kanji_in(kanji_form or "")))
    db.executemany("INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    db.executemany("INSERT INTO kanji VALUES (?,?,?,?,?,?,?,?)", kanji)
    db.executemany("INSERT INTO sentences VALUES (?,?,?,?,?,?)",
                   [(sid, jp, en, level, length, ",".join(map(str, content))) for sid, jp, en, level, length, content in sentences])
    db.executemany("INSERT INTO sentence_words VALUES (?,?,?)",
                   [(w, level, sid) for sid, _, _, level, _, content in sentences for w in content])
    db.executescript("""
        CREATE INDEX words_rank ON words(rank);
        CREATE INDEX sentences_level ON sentences(level);
    """)
    meta = {
        "built": time.strftime("%Y-%m-%d"),
        "words": str(len(rows)),
        "sentences": str(len(sentences)),
        "kanji": str(len(kanji)),
        "attribution": "Words and kanji: JMdict and KANJIDIC2, © the Electronic Dictionary Research and Development "
                       "Group, CC BY-SA 4.0. Sentences: Tatoeba (tatoeba.org), CC BY 2.0 FR.",
    }
    db.executemany("INSERT INTO meta VALUES (?,?)", meta.items())
    db.commit()
    db.execute("VACUUM")
    db.close()
    size = os.path.getsize(out) / 1e6
    print(f"Wrote {out}: {len(rows):,} words, {len(sentences):,} sentences, {len(kanji):,} kanji, {size:.1f} MB "
          f"in {time.time() - start:.0f} s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=os.path.join(ROOT, "Apps/MindTrack/Catalogs/japanese.db"))
    args = parser.parse_args()
    build(args.out)
