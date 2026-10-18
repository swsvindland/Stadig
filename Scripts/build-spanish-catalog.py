#!/usr/bin/env python3
"""Builds spanish.db for Mind Track: words and example sentences, offline, in the same schema as
japanese.db (Scripts/build-japanese-catalog.py), so one engine reads both.

    python3 Scripts/build-spanish-catalog.py            # writes Apps/MindTrack/Catalogs/spanish.db
    python3 Scripts/build-spanish-catalog.py --out x.db

Sources, downloaded once (about 130 MB) into ~/Library/Caches/SystemSpanishCatalog:
- Spanish entries from the English Wiktionary, extracted by wiktextract and published by
  kaikki.org, under CC BY-SA 4.0 (https://kaikki.org/dictionary/rawdata.html). Meanings, parts of
  speech, gender and every inflection (so "comí" and "dámelo" are known to be "comer" and "dar").
- Word frequencies from OpenSubtitles 2018, compiled by Hermit Dave's FrequencyWords, under
  CC BY-SA 4.0 (https://github.com/hermitdave/FrequencyWords). Subtitles are how people talk.
- Tatoeba's Spanish sentences, their English translations and the links between them, under
  CC BY 2.0 FR (https://tatoeba.org/en/terms_of_use).

Word order is how often a word is said: the subtitle counts of all its forms. A form that could be
two words is split between them. When one is a noun (or another non-verb) spelled like a verb form,
"casa" (house) and "casa" (marries), the English translations of the Tatoeba sentences using it say
how often it's the noun; the rest, like "fue" (ser or ir), is shared out by how common each word is
and how common that form is for its kind of word, estimated together over the whole list. Inside a
sentence, its own translation decides. Articles, contractions and object pronouns aren't vocabulary
cards; they're free in sentences, like Japanese particles. A sentence is kept when every word in it
is in the deck (names are free too), and its level is its rarest word's rank.

Card ids are a hash of the word, so they stay put when the catalog is rebuilt.
"""
import argparse
import bz2
import gzip
import hashlib
import json
import os
import re
import shutil
import sqlite3
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.expanduser("~/Library/Caches/SystemSpanishCatalog")
# The Japanese build caches Tatoeba's English sentences too; reuse them rather than download twice.
JAPANESE_CACHE = os.path.expanduser("~/Library/Caches/SystemJapaneseCatalog")
SOURCES = {
    "kaikki-spanish.jsonl.gz": "https://kaikki.org/dictionary/Spanish/kaikki.org-dictionary-Spanish.jsonl.gz",
    "es_50k.txt": "https://raw.githubusercontent.com/hermitdave/FrequencyWords/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018/es/es_50k.txt",
    "spa_sentences.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/spa/spa_sentences.tsv.bz2",
    "spa-eng_links.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/spa/spa-eng_links.tsv.bz2",
    "eng_sentences.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2",
}

WORD_LIMIT = 20000
SENTENCE_MAX_CHARS = 70
SENTENCE_MAX_WORDS = 12
# Kinds of entry that can be a card. Names, affixes and phrases can't.
CARD_POS = {"noun", "verb", "adj", "adv", "pron", "prep", "conj", "intj", "num", "det"}
POS_NAMES = {"adj": "adjective", "adv": "adverb", "pron": "pronoun", "prep": "preposition", "conj": "conjunction",
             "intj": "interjection", "num": "number", "det": "determiner"}
# Grammar, not vocabulary: free in sentences, never a card.
GRAMMAR = {"el", "la", "los", "las", "lo", "un", "una", "unos", "unas", "al", "del",
           "me", "te", "se", "nos", "os", "le", "les"}
# Old spellings and plurals that are the same card as another word.
ALIASES = {"éste": "este", "ésta": "este", "éstos": "este", "éstas": "este", "ése": "ese", "ésa": "ese", "ésos": "ese",
           "ésas": "ese", "aquél": "aquel", "aquélla": "aquel", "sus": "su", "tus": "tu", "mis": "mi", "sólo": "solo",
           "veces": "vez", "primera": "primero", "nueva": "nuevo", "e": "y", "u": "o"}
# Not cards, though they still count as the word they're a form of: a pronoun from French subtitles, an archaism and
# "ago", which are really haber's "he" and hacer's "hace".
NOT_CARDS = {"elle", "he", "hace", "papar", "mamar", "ox", "uh"}
# Swearing: not cards, and sentences with it are dropped.
BANNED = {"puto", "puta", "mierda", "joder", "coño", "cabrón", "carajo", "pendejo", "gilipollas", "polla", "follar",
          "chingar", "verga", "pinche", "culo", "cojones", "hijoputa", "putada", "maricón", "zorra", "jodido"}
# Kinds of word that keep their own spelling's count whole when it's also another word's form: "para" is "for"
# before it's parar's "stops", and "no" is "no" before an abbreviation of número.
FUNCTION_POS = {"prep", "conj", "pron", "det", "num", "adv", "intj"}
# The entry a card teaches, where the usual choice gets it wrong.
FORCE_POS = {"mi": "det", "tu": "det", "su": "det", "gracias": "intj", "adiós": "intj", "vale": "intj", "vaya": "intj",
             "venga": "intj", "oye": "intj", "anda": "intj", "hola": "intj", "noche": "noun", "mañana": "noun", "fácil": "adj",
             "rápido": "adj", "fuerte": "adj", "alto": "adj", "seguro": "adj", "genial": "adj", "justo": "adj", "primero": "adj",
             "mismo": "adj", "igual": "adj", "medio": "adj", "derecho": "noun", "persona": "noun", "bien": "adv", "más": "adv",
             "ya": "adv", "ahora": "adv", "luego": "adv", "como": "conj", "cuando": "conj", "mucho": "adv", "tanto": "adv",
             "listo": "adj", "claro": "adv", "tarde": "adv", "sobre": "prep", "contra": "prep", "nada": "pron", "ese": "det",
             "pronto": "adv", "bajo": "prep", "cerca": "adv", "entre": "prep", "hasta": "prep", "uno": "num", "ayer": "adv", "basta": "intj"}
# Imperatives that are interjections in their own right. Other interjections that are just a verb's form ("vamos",
# "sabes") stay with the verb.
KEEP_INTERJECTIONS = {"vale", "vaya", "venga", "oye", "anda"} | {w for w, pos in FORCE_POS.items() if pos == "intj"}
# Senses tagged like this don't make the short meaning.
SKIP_TAGS = {"obsolete", "archaic", "rare", "dated", "historical", "vulgar", "derogatory", "offensive", "ethnic", "slur",
             "Internet", "nonstandard", "misspelling", "uncommon", "euphemistic"}
# Wiktionary calls some everyday Latin American words dated or uncommon ("lindo"): their senses count when there are
# no others.
SOFT_TAGS = {"dated", "uncommon", "rare"}
# Words that are mostly written as names in Tatoeba ("Luis", "Tony") aren't cards, except these.
KEEP_NAMES = {"dios", "señor", "señora"}
LETTER_GLOSS = re.compile(r"name of the .*letter|^(the )?(letter|digraph)\b", re.IGNORECASE)
SKIP_GLOSS = re.compile(r"^(only )?used in\b|^the musical note|"
                        r"^(apheretic|alternative|obsolete|archaic|dated|eye dialect|clipping|abbreviation|contraction) "
                        r"(form|spelling|of)\b", re.IGNORECASE)
# Words whose first Wiktionary sense isn't the one a learner meets first.
MEANING_OVERRIDES = {
    "que": "that; which", "de": "of; from", "a": "to; at", "en": "in; on", "por": "for; by; through", "para": "for; in order to",
    "con": "with", "sin": "without", "como": "like; as; how", "si": "if", "sí": "yes", "no": "no; not", "ya": "already; now",
    "muy": "very", "más": "more", "bien": "well; fine", "aquí": "here", "ahora": "now", "qué": "what", "cómo": "how",
    "algo": "something", "nada": "nothing", "todo": "all; everything", "eso": "that", "esto": "this", "este": "this",
    "ese": "that", "estar": "to be (a state or place)", "ser": "to be (what something is)", "haber": "to have (done); there is",
    "hay": "there is; there are", "tener": "to have", "hacer": "to do; to make", "ir": "to go", "poder": "can; to be able to",
    "querer": "to want; to love", "saber": "to know (a fact)", "conocer": "to know (a person or place)", "decir": "to say; to tell",
    "ver": "to see", "dar": "to give", "deber": "must; to owe", "pasar": "to happen; to pass", "quedar": "to stay; to remain",
    "creer": "to believe; to think", "hablar": "to speak; to talk", "llevar": "to carry; to wear", "dejar": "to leave; to let",
    "seguir": "to follow; to keep on", "encontrar": "to find", "llamar": "to call", "venir": "to come", "pensar": "to think",
    "salir": "to go out; to leave", "volver": "to return; to come back", "tomar": "to take; to drink", "mirar": "to look at",
    "esperar": "to wait; to hope", "buscar": "to look for", "tal": "such", "vez": "time (occasion)", "mismo": "same",
    "otro": "other; another", "cosa": "thing", "hombre": "man", "señor": "sir; Mr", "señora": "madam; Mrs",
    "gracias": "thank you", "hola": "hello", "bueno": "good", "mal": "badly", "malo": "bad", "nunca": "never",
    "siempre": "always", "también": "also; too", "tampoco": "neither; not either", "entonces": "then; so",
    "pues": "well; so", "mucho": "a lot; much", "poco": "little; a bit", "tan": "so (as much)", "hasta": "until; up to",
    "desde": "since; from", "sobre": "on; about", "entre": "between; among", "porque": "because", "pero": "but",
    "cuando": "when", "donde": "where", "dónde": "where", "quién": "who", "cuál": "which", "cuánto": "how much",
    "aún": "still; yet", "todavía": "still; yet", "luego": "later; then", "tiempo": "time; weather", "año": "year",
    "día": "day", "vida": "life", "mundo": "world", "casa": "house; home", "gente": "people", "parte": "part",
    "favor": "favour", "claro": "of course; clear", "mira": "look", "verdad": "truth; true", "uno": "one",
    "nadie": "nobody", "alguien": "someone", "yo": "I", "tú": "you", "él": "he; him", "ella": "she; her", "nosotros": "we",
    "vosotros": "you (plural, in Spain)", "ellos": "they", "ellas": "they (feminine)", "usted": "you (formal)",
    "ustedes": "you (plural)", "mi": "my", "tu": "your", "su": "his; her; their; your (formal)", "nuestro": "our",
    "vuestro": "your (plural, in Spain)", "mío": "mine", "tuyo": "yours", "suyo": "his; hers; theirs",
    "gustar": "to like (to be pleasing)", "solo": "only; alone", "aquel": "that (over there)", "vale": "OK; all right",
    "vaya": "wow; well", "venga": "come on", "oye": "hey; listen", "anda": "come on; go on", "mejor": "better", "peor": "worse",
    "bajo": "under; low", "cerca": "near; close", "lejos": "far", "fuera": "outside", "dentro": "inside", "mientras": "while",
    "según": "according to", "durante": "during", "contra": "against", "adiós": "goodbye", "noche": "night",
    "mañana": "morning; tomorrow", "hoy": "today", "coche": "car", "auto": "car", "chica": "girl", "chico": "boy",
    "clase": "class", "policía": "police", "probar": "to try; to taste", "callar": "to be quiet", "confiar": "to trust",
    "ganar": "to win; to earn", "tratar": "to try; to treat", "sentar": "to sit", "juego": "game", "cuenta": "bill; account",
    "tierra": "earth; land", "tipo": "guy; type", "tanto": "so much", "cierto": "true; certain", "listo": "ready; clever",
    "vuelta": "turn; return", "cariño": "affection; darling", "mayor": "older; bigger", "derecho": "right; law",
    "alto": "tall; high", "medio": "half; middle", "genial": "great", "fácil": "easy", "fuerte": "strong",
    "rápido": "fast; quickly", "primero": "first", "justo": "fair; just; exactly", "seguro": "sure; safe",
    "igual": "the same; equal", "menos": "less; fewer", "ni": "nor; not even", "cualquiera": "anyone; any",
    "alguno": "some; any", "ninguno": "none; no", "importar": "to matter", "encantar": "to love (to delight)",
    "llegar": "to arrive", "matar": "to kill", "escuchar": "to listen to", "entender": "to understand",
    "conseguir": "to get; to manage", "suponer": "to suppose", "contar": "to count; to tell", "echar": "to throw",
    "coger": "to take; to catch", "meter": "to put in", "disculpar": "to excuse", "levantar": "to lift; to raise",
    "quitar": "to remove", "detener": "to stop; to arrest", "perdonar": "to forgive", "orden": "order",
    "cuanto": "as much as", "dicho": "said", "hecho": "done; fact", "visto": "seen", "pasado": "past; last",
    "supuesto": "supposed", "persona": "person", "padre": "father", "tarde": "late; afternoon", "dios": "god",
    "realmente": "really", "demasiado": "too much; too", "después": "after; later", "antes": "before",
    "primo": "cousin", "abuelo": "grandfather", "abuela": "grandmother", "temprano": "early", "cansado": "tired",
    "carta": "letter; menu", "ayer": "yesterday", "novia": "girlfriend; bride", "novio": "boyfriend; groom",
    "cámara": "camera; chamber", "caballero": "gentleman", "viaje": "trip; journey", "basta": "that's enough",
    "noticia": "news", "cuarto": "room; quarter", "sueño": "sleep; dream", "oído": "ear; hearing", "guardar": "to keep; to save",
    "campo": "field; countryside", "marchar": "to go; to leave", "largar": "to let go; to clear off",
}
TOKEN = re.compile(r"[a-záéíóúüñ]+")
WORDS = re.compile(r"[A-Za-záéíóúüñÁÉÍÓÚÑ]+")
NAME = re.compile(r"^[A-ZÁÉÍÓÚÑ][a-záéíóúüñ]+$")
ENGLISH_WORD = re.compile(r"[a-z]+")
STOP = {"the", "and", "for", "with", "that", "this", "which", "from", "into", "one", "someone", "something", "about", "used",
        "very", "who", "its", "his", "her", "their", "out", "off", "make", "made", "act", "being", "also", "any", "all", "not",
        "but", "have", "has", "had", "get", "got", "put", "take", "certain", "especially", "usually", "person", "people"}
# Tags that say which form of a word this is: person, number, tense and mood, gender.
SLOT_TAGS = {"first-person", "second-person", "third-person", "singular", "plural", "present", "preterite", "imperfect",
             "future", "conditional", "subjunctive", "indicative", "imperative", "infinitive", "gerund", "participle", "past",
             "masculine", "feminine", "combined-form", "formal", "vos-form", "negative", "imperfect-se", "diminutive",
             "augmentative", "superlative", "comparative"}
SKIP_FORM_TAGS = {"table-tags", "inflection-template", "error-unrecognized-form", "canonical", "romanization", "alternative",
                  "obsolete", "archaic", "pronunciation-spelling", "misspelling", "nonstandard"}
CLITICS = ("nos", "os", "me", "te", "se", "lo", "la", "le", "los", "las", "les")
ACCENTS = str.maketrans("áéíóú", "aeiou")


def fetch():
    os.makedirs(CACHE, exist_ok=True)
    for name, url in SOURCES.items():
        path = os.path.join(CACHE, name)
        if os.path.exists(path) and os.path.getsize(path) > 0:
            continue
        shared = os.path.join(JAPANESE_CACHE, name)
        if os.path.exists(shared) and os.path.getsize(shared) > 0:
            shutil.copyfile(shared, path)
            continue
        print(f"Downloading {url}")
        urllib.request.urlretrieve(url, path + ".part")
        os.replace(path + ".part", path)


def word_id(word):
    """Stable across rebuilds: the first 48 bits of the word's SHA-1."""
    return int(hashlib.sha1(("es:" + word).encode("utf-8")).hexdigest()[:12], 16)


def slot(tags):
    return tuple(sorted(t for t in tags if t in SLOT_TAGS)) or ("base",)


def pos_class(pos):
    return pos if pos in ("verb", "noun", "adj") else "other"


def clean_gloss(gloss):
    bare = gloss
    while re.search(r"\([^()]*\)", bare):
        bare = re.sub(r"\s*\([^()]*\)", "", bare)
    return re.sub(r"\s+", " ", bare).strip(" ;,.") or gloss.strip()


def short(gloss, limit=30):
    """"to talk; to speak; to communicate using words" is "to talk; to speak" as an answer choice."""
    parts = [p.strip() for p in re.split(r"[;,]", clean_gloss(gloss)) if p.strip()]
    out = parts[0] if parts else gloss
    for part in parts[1:]:
        if len(out) + 2 + len(part) > limit:
            break
        out += "; " + part
    return out if len(out) <= 40 else out[:39].rstrip() + "…"


def regional(tags):
    # Region tags are capitalised ("Spain", "Latin-America", "Chile"); grammatical tags aren't.
    return any(t[:1].isupper() and t not in SKIP_TAGS for t in tags)


def good_senses(senses, skip=SKIP_TAGS):
    """Senses worth teaching, general ones before regional ones."""
    usable = [s for s in senses if s[0] and not (set(s[1]) & skip) and not SKIP_GLOSS.match(s[0])
              and not LETTER_GLOSS.search(s[0])]
    return [s for s in usable if not regional(s[1])] + [s for s in usable if regional(s[1])]


def parse_kaikki():
    """Lemma entries and a map from every form to the words it can be a form of."""
    lemmas = {}       # word -> [{pos, senses, gender}]
    forms = {}        # form -> {(lemma, pos class, slot)}

    def add(form, lemma, pos, tags):
        form = form.strip().lower()
        if form.startswith("no "):
            form = form[3:]
        if not form or not TOKEN.fullmatch(form):
            return
        forms.setdefault(form, set()).add((lemma, pos_class(pos), slot(tags)))

    with gzip.open(os.path.join(CACHE, "kaikki-spanish.jsonl.gz"), "rt", encoding="utf-8") as f:
        for line in f:
            e = json.loads(line)
            word, pos = e.get("word", ""), e.get("pos", "")
            if pos not in CARD_POS and pos not in ("article", "contraction"):
                continue
            if word != word.lower() or not TOKEN.fullmatch(word):
                continue
            senses = []
            for s in e.get("senses", []):
                tags = s.get("tags", [])
                if {"abbreviation", "initialism", "acronym", "clipping"} & set(tags):
                    continue
                if "form-of" in tags or "alt-of" in tags or s.get("form_of") or s.get("alt_of"):
                    for target in s.get("form_of", []) + s.get("alt_of", []):
                        if target.get("word"):
                            add(word, target["word"], pos, tags)
                    continue
                glosses = s.get("glosses") or []
                if glosses:
                    senses.append((glosses[0], tags))
            if not senses:
                continue
            head = (e.get("head_templates") or [{}])[0]
            gender = head.get("args", {}).get("1", "") if head.get("name") == "es-noun" else ""
            lemmas.setdefault(word, []).append({"pos": pos, "senses": senses, "gender": gender})
            add(word, word, pos, ["base"])
            for form in e.get("forms", []):
                tags = form.get("tags", [])
                if set(tags) & SKIP_FORM_TAGS or not form.get("form"):
                    continue
                text = form["form"]
                if text.startswith("before a noun "):
                    text = text[len("before a noun "):]
                add(text, word, pos, tags)
    for alias, target in ALIASES.items():
        forms[alias] = {(target, "other", ("base",))}
        lemmas.pop(alias, None)
    return lemmas, forms


def choose(word, entries):
    """The entry a card teaches: the verb if there is one ("poder" is "can", not "power"), otherwise
    the entry with the most senses ("sobre" is "on", "amigo" is "friend")."""
    usable = [e for e in entries if e["pos"] in CARD_POS and good_senses(e["senses"])]
    forced = FORCE_POS.get(word)
    if forced:
        match = [e for e in entries if e["pos"] == forced]
        if match:
            return match[0]
        if word in MEANING_OVERRIDES:
            return {"pos": forced, "senses": [(MEANING_OVERRIDES[word], [])], "gender": ""}
    if not usable:
        soft = SKIP_TAGS - SOFT_TAGS
        usable = [{**e, "senses": [(g, [t for t in tags if t not in SOFT_TAGS]) for g, tags in good_senses(e["senses"], soft)]}
                  for e in entries if e["pos"] in CARD_POS and good_senses(e["senses"], soft)]
    if not usable:
        return None
    verbs = [e for e in usable if e["pos"] == "verb"]
    if verbs:
        return verbs[0]
    return max(usable, key=lambda e: (e["pos"] != "intj", len(good_senses(e["senses"])), -usable.index(e)))


def cards(lemmas, forms):
    """The words that can be cards, each with the entry it teaches."""
    form_of = {}
    for form, options in forms.items():
        for lemma, _, _ in options:
            if lemma != form:
                form_of.setdefault(form, set()).add(lemma)
    out = {}
    for word, entries in lemmas.items():
        if word in GRAMMAR or word in NOT_CARDS or word in BANNED:
            continue
        entry = choose(word, entries)
        if entry is None:
            continue
        if entry["pos"] == "intj" and word not in KEEP_INTERJECTIONS and any(l in lemmas for l in form_of.get(word, ())):
            continue
        out[word] = entry
    return out


def keywords(entry):
    """The English words that say a translation is about this sense of a word: "house", "home"."""
    out = set()
    for gloss, _ in good_senses(entry["senses"])[:2]:
        for w in ENGLISH_WORD.findall(clean_gloss(gloss).lower()):
            if len(w) >= 3 and w not in STOP:
                out.add(w)
    return out


def mentions(english, words):
    """Whether an English sentence uses any of these words, or one starting with it ("seriously")."""
    tokens = ENGLISH_WORD.findall(english.lower())
    return any(t == w or (len(w) >= 4 and t.startswith(w)) for t in tokens for w in words)


def read_frequencies():
    counts = {}
    with open(os.path.join(CACHE, "es_50k.txt"), encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2 and TOKEN.fullmatch(parts[0]):
                counts[parts[0]] = int(parts[1])
    return counts


def lemma_frequencies(counts, forms, deck, fixed, rounds=15):
    """How often each word is said, from the counts of its forms. `fixed` gives some forms' split
    already (a noun spelled like a verb form, from the translations). A verb can't take more of a
    noun or adjective's form than three times what its unambiguous forms say it would: "punto" is the
    noun, whatever its translations say, because "puntar" is too rare to account for it. The rest of an
    ambiguous form is shared out by each candidate's total so far times how common that slot is for
    its kind of word (third-person preterite for a verb, the plural for a noun), the two
    re-estimated together."""
    candidates = {}
    for form, count in counts.items():
        options = sorted({c for c in forms.get(form, ()) if c[0] in deck or c[0] in GRAMMAR})
        if options:
            candidates[form] = (count, options)
    totals, sure = {}, {}
    for form, (count, options) in candidates.items():
        for lemma, _, _ in options:
            totals[lemma] = totals.get(lemma, 0) + count / len(options)
        if len({o[0] for o in options}) == 1:
            sure[options[0][0]] = sure.get(options[0][0], 0) + count
    slot_share = {}

    def verb_cap(options, count):
        """Three times what the verbs among `options` would say in this form, by their unambiguous forms
        (about half of a verb's use)."""
        return 3 * sum(2 * sure.get(l, 0) * slot_share.get((c, s), 1) for l, c, s in options if c == "verb") if slot_share else count
    for _ in range(rounds):
        assigned, slot_sum, class_sum = {}, {}, {}

        def give(lemma, cls, sl, share):
            assigned[lemma] = assigned.get(lemma, 0) + share
            slot_sum[(cls, sl)] = slot_sum.get((cls, sl), 0) + share
            class_sum[cls] = class_sum.get(cls, 0) + share

        for form, (count, options) in candidates.items():
            rest = count
            if form in fixed:
                lemma, share = fixed[form]
                for option in options:
                    if option[0] == lemma:
                        others = [o for o in options if o[0] != lemma]
                        rest = count * (1 - share)
                        if all(o[1] == "verb" for o in others):
                            rest = min(rest, verb_cap(others, count))
                        give(*option, count - rest)
                        options = others
                        break
            if not options:
                continue
            weights = [max(1e-9, totals.get(l, 0)) * slot_share.get((c, s), 1) for l, c, s in options]
            # A verb can't take more than three times its expected count from a noun or adjective's form either:
            # "amiga" is amigo's, not amigar's.
            verbs = [i for i, o in enumerate(options) if o[1] == "verb"]
            if slot_share and verbs and len(verbs) < len(options):
                share = sum(weights[i] for i in verbs) / sum(weights)
                cap = verb_cap([options[i] for i in verbs], rest)
                if rest * share > cap:
                    scale = cap / (rest * share)
                    others = sum(w for i, w in enumerate(weights) if i not in verbs)
                    moved = sum(weights) * share * (1 - scale)
                    weights = [w * scale if i in verbs else w + moved * w / others for i, w in enumerate(weights)]
            total = sum(weights)
            for option, w in zip(options, weights):
                give(*option, rest * w / total)
        totals = assigned
        slot_share = {key: value / class_sum[key[0]] for key, value in slot_sum.items()}
    return totals, slot_share


def display(word, entry):
    """Nouns carry their article, so gender is learned with the word: el perro, la casa, el agua."""
    if entry["pos"] != "noun":
        return word
    gender = entry["gender"]
    if gender == "m-p":
        return "los " + word
    if gender == "f-p":
        return "las " + word
    if gender == "m":
        return "el " + word
    if gender == "f":
        # Feminine nouns starting with a stressed a take "el": el agua, el hambre.
        return ("el " if starts_stressed_a(word) else "la ") + word
    if gender.startswith("mf"):
        return "el/la " + word
    return word


def starts_stressed_a(word):
    bare = word[1:] if word.startswith("h") else word
    if not bare or bare[0] not in "aá":
        return False
    if bare[0] == "á":
        return True
    vowels = re.findall(r"[aeiouáéíóú]+", word)
    if len(vowels) == 1:
        return True
    # Two-syllable words ending in a vowel, n or s stress the first: agua, alma, hambre, arma.
    return len(vowels) == 2 and word[-1] in "aeiouns" and not re.search(r"[áéíóú]", word)


def read_tatoeba():
    spanish = {}
    with bz2.open(os.path.join(CACHE, "spa_sentences.tsv.bz2"), "rt", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3 and len(parts[2]) <= SENTENCE_MAX_CHARS:
                spanish[int(parts[0])] = parts[2]
    links = {}
    with bz2.open(os.path.join(CACHE, "spa-eng_links.tsv.bz2"), "rt", encoding="utf-8") as f:
        for line in f:
            a, b = line.split("\t")[:2]
            if int(a) in spanish:
                links.setdefault(int(a), int(b))
    wanted = set(links.values())
    english = {}
    with bz2.open(os.path.join(CACHE, "eng_sentences.tsv.bz2"), "rt", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3 and int(parts[0]) in wanted:
                english[int(parts[0])] = parts[2]
    return [(sid, text, english[links[sid]]) for sid, text in spanish.items() if sid in links and links[sid] in english]


def build(out):
    start = time.time()
    fetch()
    print("Reading Wiktionary (kaikki.org)…")
    lemmas, forms = parse_kaikki()
    deck = cards(lemmas, forms)
    print(f"  {len(lemmas):,} words, {len(forms):,} forms, {len(deck):,} possible cards")
    print("Reading Tatoeba…")
    pairs = read_tatoeba()
    print(f"  {len(pairs):,} short sentences with an English translation")
    capitalised, lower = {}, {}
    for _, text, _ in pairs:
        for raw in WORDS.findall(text)[1:]:
            if NAME.match(raw):
                capitalised[raw.lower()] = capitalised.get(raw.lower(), 0) + 1
            elif raw.islower():
                lower[raw] = lower.get(raw, 0) + 1
    for word in [w for w in deck if capitalised.get(w, 0) >= 3 and capitalised[w] > lower.get(w, 0) and w not in KEEP_NAMES]:
        del deck[word]

    # A noun or adjective spelled like another card's verb form: how often is it the noun? A function word keeps
    # its whole count.
    homographs = {}
    fixed = {w: (w, 1.0) for w, e in deck.items() if e["pos"] in FUNCTION_POS}
    for word, entry in deck.items():
        if entry["pos"] not in ("noun", "adj"):
            continue
        verbs = {l for l, c, _ in forms.get(word, ()) if c == "verb" and l != word and l in deck}
        if verbs:
            homographs[word] = keywords(entry)
    seen, hits = {}, {}
    for _, text, en in pairs:
        for token in set(TOKEN.findall(text.lower())):
            if token in homographs:
                seen[token] = seen.get(token, 0) + 1
                if mentions(en, homographs[token]):
                    hits[token] = hits.get(token, 0) + 1
    fixed.update({w: (w, (hits.get(w, 0) + 0.5) / (seen.get(w, 0) + 1)) for w in homographs})

    totals, slot_share = lemma_frequencies(read_frequencies(), forms, deck, fixed)
    ranked = sorted((w for w in deck if totals.get(w, 0) >= 3), key=lambda w: (-totals[w], w))[:WORD_LIMIT]
    rank_of = {w: i + 1 for i, w in enumerate(ranked)}
    print(f"  {len(ranked):,} words ranked; first: {', '.join(ranked[:25])}")

    def likeliest(token, english):
        """The deck word a token is in this sentence, "" for grammar, None if it's none of them."""
        if token in GRAMMAR:
            return ""
        if token in rank_of and deck[token]["pos"] in FUNCTION_POS:
            return token
        if token in homographs and token in rank_of:
            if mentions(english, homographs[token]):
                return token
            options = [(totals.get(l, 0) * slot_share.get((c, s), 1), l) for l, c, s in forms.get(token, ())
                       if l != token and l in rank_of]
            if options:
                return max(options)[1]
        options = [(totals.get(l, 0) * slot_share.get((c, s), 1), l) for l, c, s in forms.get(token, ())
                   if l in rank_of or l in GRAMMAR]
        if not options:
            return None
        best = max(options)[1]
        return "" if best in GRAMMAR else best

    def resolve(token, english=""):
        if token in BANNED:
            return None
        found = likeliest(token, english)
        if found is not None:
            return found
        # Pronouns stuck to the verb: dámelo is da + me + lo, comerlo is comer + lo.
        stem = token
        for _ in range(2):
            for clitic in CLITICS:
                if stem.endswith(clitic) and len(stem) > len(clitic) + 1:
                    stem = stem[: -len(clitic)]
                    found = likeliest(stem, english) or likeliest(stem.translate(ACCENTS), english)
                    if found:
                        return found
                    break
        return None

    # Names: capitalised mid-sentence and not a word, anywhere in the corpus. Free in sentences.
    names = set()
    for _, text, _ in pairs:
        for raw in WORDS.findall(text)[1:]:
            if NAME.match(raw) and resolve(raw.lower()) is None:
                names.add(raw)

    sentences, seen_text = [], set()
    for sid, text, en in pairs:
        raws = WORDS.findall(text)
        if not raws or len(raws) > SENTENCE_MAX_WORDS or re.search(r"\d", text) or text.lower() in seen_text:
            continue
        content, ok = [], True
        for raw in raws:
            if raw in names:
                continue
            found = resolve(raw.lower(), en)
            if found is None:
                ok = False
                break
            if found:
                content.append(found)
        if ok and content:
            seen_text.add(text.lower())
            content = sorted(set(content), key=lambda w: rank_of[w])
            sentences.append((sid, text, en, max(rank_of[w] for w in content), len(text), [word_id(w) for w in content]))
    sentences = trim(sentences)
    print(f"  {len(sentences):,} sentences kept, {len(names):,} names free")

    uses = {}
    for row in sentences:
        for w in row[5]:
            uses[w] = uses.get(w, 0) + 1

    if os.path.exists(out):
        os.remove(out)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    db = sqlite3.connect(out)
    db.executescript("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE words (id INTEGER PRIMARY KEY, rank INTEGER NOT NULL, word TEXT NOT NULL, kana TEXT NOT NULL,
            kanji TEXT, meaning TEXT NOT NULL, meanings TEXT NOT NULL, pos TEXT NOT NULL, uses INTEGER NOT NULL,
            kanji_chars TEXT NOT NULL);
        CREATE TABLE sentences (id INTEGER PRIMARY KEY, jp TEXT NOT NULL, en TEXT NOT NULL, level INTEGER NOT NULL,
            length INTEGER NOT NULL, words TEXT NOT NULL);
        CREATE TABLE sentence_words (word INTEGER NOT NULL, level INTEGER NOT NULL, sentence INTEGER NOT NULL,
            PRIMARY KEY (word, level, sentence)) WITHOUT ROWID;
    """)
    rows = []
    for word in ranked:
        entry = deck[word]
        senses = good_senses(entry["senses"])
        meaning = MEANING_OVERRIDES.get(word) or short(senses[0][0])
        meanings = "; ".join(dict.fromkeys(clean_gloss(s[0]) for s in senses[:3]))
        text = display(word, entry)
        wid = word_id(word)
        # The kana column is the word as it's read: in Spanish, the word itself.
        rows.append((wid, rank_of[word], text, text, None, meaning, meanings, POS_NAMES.get(entry["pos"], entry["pos"]),
                     uses.get(wid, 0), ""))
    db.executemany("INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    db.executemany("INSERT INTO sentences VALUES (?,?,?,?,?,?)",
                   [(sid, es, en, level, length, ",".join(map(str, content))) for sid, es, en, level, length, content in sentences])
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
        "attribution": "Words: Wiktionary, via kaikki.org, CC BY-SA 4.0. Word frequency: FrequencyWords (OpenSubtitles 2018), "
                       "CC BY-SA 4.0. Sentences: Tatoeba (tatoeba.org), CC BY 2.0 FR.",
    }
    db.executemany("INSERT INTO meta VALUES (?,?)", meta.items())
    db.commit()
    db.execute("VACUUM")
    db.close()
    size = os.path.getsize(out) / 1e6
    print(f"Wrote {out}: {len(rows):,} words, {len(sentences):,} sentences, {size:.1f} MB in {time.time() - start:.0f} s")


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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=os.path.join(ROOT, "Apps/MindTrack/Catalogs/spanish.db"))
    args = parser.parse_args()
    build(args.out)
