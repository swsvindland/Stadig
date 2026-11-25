"""The food catalogs: every source read into one `Food`, written to a file per licence and shipping.
Python standard library only. Run by Scripts/build-catalogs.py.

usda.db holds SR Legacy and FNDDS's fast-food and restaurant foods, drinks and dishes, and is bundled from
Packages/FoodDatabase/Sources/FoodDatabase/Resources (in git). off.db holds Open Food Facts, under
the ODbL, and is bundled from Apps/MacroTrack/Catalogs (not in git). The two stay apart so that the
app works without off.db and so nothing else takes on its licence. Never processes user data.

Each food also carries how processed it is (NOVA 1 whole or minimally processed, 2 a culinary
ingredient, 3 processed, 4 ultra-processed; Open Food Facts' own group, or for USDA an estimate
from the food's category and name), whether it's a fermented food with live cultures, and whether
its calories fit its macros (food_energy.py).

The older CSV export (--off /path/off.csv[.gz]) is still read, but it leaves out the nutrition of
every product kept in Open Food Facts' newer format. Ported from the React Native Macro Track.
"""
import collections
import csv
import dataclasses
import functools
import gzip
import hashlib
import html
import itertools
import json
import math
import multiprocessing
import re
from pathlib import Path
import sqlite3
import zipfile

import food_energy

ROOT = Path(__file__).resolve().parent.parent
USDA_DESTINATION = ROOT / "Packages" / "FoodDatabase" / "Sources" / "FoodDatabase" / "Resources"
OFF_DESTINATION = ROOT / "Apps" / "MacroTrack" / "Catalogs"
# The ODbL asks that the derived database and the recipe that builds it be public: this script
# and the built off.db must be published where this points before a release ships.
RECIPE_URL = "https://github.com/swsvindland/macro-track/tree/main/assets/food"
SCHEMA_VERSION = 3
USDA_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip"
FNDDS_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip"
OFF_URL = "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"
OFF_SAMPLE_URL = "https://world.openfoodfacts.org/data/exports/products.random-modulo-1000.jsonl.gz"
OFF_CSV_URL = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
# Where shoppers read English, a product is named in English when Open Food Facts has that name;
# elsewhere it keeps the name printed in the package's own language.
ENGLISH_MARKETS = {"en:united-states", "en:united-kingdom", "en:canada", "en:australia",
                   "en:new-zealand", "en:ireland"}
# Open Food Facts' country tags as the ISO 3166 codes a phone names its region by, for every
# country with more than a few dozen catalog foods; "world" is sold everywhere. A search ranks
# packaged foods sold in the phone's region above the same products sold only elsewhere.
COUNTRIES = dict(pair.split(":") for pair in """
    france:fr united-states:us spain:es germany:de italy:it united-kingdom:gb scotland:gb
    canada:ca switzerland:ch belgium:be australia:au ireland:ie netherlands:nl japan:jp brazil:br
    sweden:se poland:pl finland:fi norway:no denmark:dk austria:at portugal:pt czech-republic:cz
    new-zealand:nz romania:ro mexico:mx bulgaria:bg russia:ru luxembourg:lu morocco:ma hungary:hu
    india:in greece:gr thailand:th israel:il lithuania:lt argentina:ar singapore:sg south-africa:za
    estonia:ee croatia:hr turkey:tr turkiye:tr türkiye:tr slovakia:sk saudi-arabia:sa colombia:co
    ukraine:ua united-arab-emirates:ae chile:cl philippines:ph latvia:lv hong-kong:hk slovenia:si
    serbia:rs reunion:re algeria:dz iceland:is taiwan:tw bolivia:bo south-korea:kr puerto-rico:pr
    malaysia:my tunisia:tn egypt:eg costa-rica:cr kuwait:kw cyprus:cy qatar:qa indonesia:id peru:pe
    lebanon:lb new-caledonia:nc ecuador:ec uruguay:uy french-polynesia:pf malta:mt guadeloupe:gp
    panama:pa georgia:ge dominican-republic:do bosnia-and-herzegovina:ba cuba:cu north-macedonia:mk
    republic-of-macedonia:mk vietnam:vn paraguay:py china:cn belarus:by iraq:iq venezuela:ve
    martinique:mq el-salvador:sv mauritius:mu moldova:md andorra:ad guatemala:gt albania:al
    jordan:jo pakistan:pk bahrain:bh montenegro:me senegal:sn honduras:hn kazakhstan:kz
    faroe-islands:fo kenya:ke cote-d-ivoire:ci jamaica:jm trinidad-and-tobago:tt armenia:am oman:om
    cambodia:kh libya:ly french-guiana:gf nicaragua:ni monaco:mc madagascar:mg gibraltar:gi guam:gu
    nigeria:ng jersey:je iran:ir bangladesh:bd sri-lanka:lk cameroon:cm barbados:bb uzbekistan:uz
    virgin-islands-of-the-united-states:vi palestinian-territories:ps ethiopia:et brunei:bn
    ghana:gh macau:mo aland-islands:ax gabon:ga seychelles:sc azerbaijan:az myanmar:mm
    afghanistan:af mongolia:mn guernsey:gg saint-pierre-and-miquelon:pm suriname:sr maldives:mv
    isle-of-man:im democratic-republic-of-the-congo:cd nepal:np the-bahamas:bs kosovo:xk
    liechtenstein:li syria:sy kyrgyzstan:kg haiti:ht san-marino:sm burkina-faso:bf zambia:zm
    aruba:aw bermuda:bm greenland:gl curacao:cw benin:bj mozambique:mz mali:ml guinea:gn togo:tg
    guyana:gy namibia:na saint-lucia:lc fiji:fj republic-of-the-congo:cg mauritania:mr tanzania:tz
    cayman-islands:ky mayotte:yt zimbabwe:zw djibouti:dj rwanda:rw niger:ne botswana:bw somalia:so
    belize:bz sierra-leone:sl angola:ao yemen:ye cape-verde:cv sint-maarten:sx laos:la world:world
""".split())
LICENSES = {
    "usda": ("CC0-1.0", "USDA FoodData Central: SR Legacy (April 2018), and the fast-food and restaurant "
                        "foods and the drinks of FNDDS 2021-2023 (October 2024). Public domain (CC0 1.0)."),
    "off": ("ODbL-1.0",
            "Contains information from Open Food Facts (https://world.openfoodfacts.org), which is "
            "made available here under the Open Database License (ODbL) 1.0 "
            "(https://opendatacommons.org/licenses/odbl/1-0/). Individual contents are available "
            "under the Database Contents License (https://opendatacommons.org/licenses/dbcl/1-0/). "
            "This derived database and the recipe that builds it are published at "
            "{recipe}."),
}

# The same keys and units as NutritionEngine's Micronutrients. USDA reports each in that unit; Open Food
# Facts reports grams per 100 g or ml, so its values are multiplied by the factor.
MICROS = [
    # key, USDA nutrient ids (summed; the first must be present), OFF columns (first present), factor
    ("sugar", [2000], ["sugars"], 1),
    ("addedSugar", [], ["added-sugars"], 1),
    ("saturatedFat", [1258], ["saturated-fat"], 1),
    ("transFat", [1257], ["trans-fat"], 1),
    ("monounsaturatedFat", [1292], ["monounsaturated-fat"], 1),
    ("polyunsaturatedFat", [1293], ["polyunsaturated-fat"], 1),
    # ALA (or undifferentiated 18:3), EPA, DPA and DHA; linoleic and arachidonic acid.
    ("omega3", [(1404, 1270), 1278, 1280, 1272], ["omega-3-fat"], 1),
    ("omega6", [(1316, 1269), 1271], ["omega-6-fat"], 1),
    ("cholesterol", [1253], ["cholesterol"], 1e3),
    ("potassium", [1092], ["potassium"], 1e3),
    ("calcium", [1087], ["calcium"], 1e3),
    ("iron", [1089], ["iron"], 1e3),
    ("magnesium", [1090], ["magnesium"], 1e3),
    ("phosphorus", [1091], ["phosphorus"], 1e3),
    ("zinc", [1095], ["zinc"], 1e3),
    ("copper", [1098], ["copper"], 1e3),
    ("manganese", [1101], ["manganese"], 1e3),
    ("selenium", [1103], ["selenium"], 1e6),
    ("vitaminA", [1106], ["vitamin-a"], 1e6),
    ("vitaminC", [1162], ["vitamin-c"], 1e3),
    ("vitaminD", [1114], ["vitamin-d"], 1e6),
    ("vitaminE", [1109], ["vitamin-e"], 1e3),
    ("vitaminK", [1185], ["vitamin-k", "phylloquinone"], 1e6),
    ("thiamin", [1165], ["vitamin-b1"], 1e3),
    ("riboflavin", [1166], ["vitamin-b2"], 1e3),
    ("niacin", [1167], ["vitamin-pp"], 1e3),
    ("pantothenicAcid", [1170], ["pantothenic-acid"], 1e3),
    ("vitaminB6", [1175], ["vitamin-b6"], 1e3),
    ("folate", [1190], ["vitamin-b9", "folates"], 1e6),
    ("vitaminB12", [1178], ["vitamin-b12"], 1e6),
    ("choline", [1180], ["choline"], 1e3),
    ("caffeine", [1057], ["caffeine"], 1e3),
]
FAT_PARTS = {"saturatedFat", "transFat", "monounsaturatedFat", "polyunsaturatedFat", "omega3", "omega6"}
# A US Nutrition Facts panel always lists these, so a zero was printed. Imported records fill the
# voluntary ones with zeros nobody measured (bread with no magnesium), so those zeros are unknown.
LABELED = {"sugar", "addedSugar", "saturatedFat", "transFat", "cholesterol", "potassium", "calcium",
           "iron", "vitaminD"}
FL_OZ_ML = 29.5735
OZ_G = 28.3495


@dataclasses.dataclass(slots=True)
class Food:
    """One food from any source: what the catalogs hold, whichever file it's written to. `nutrients`
    are per 100 of `basis` ("g" or "ml"), `id` starts with its source ("usda:", "off:") and `also`
    is other names to search by."""
    id: str
    name: str
    brand: str
    barcode: str | None
    basis: str
    nutrients: dict
    micros: dict
    portions: list
    popularity: float
    markets: str
    nova: int | None
    traits: int
    also: list = dataclasses.field(default_factory=list)


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


LB_G = 453.592
# unit: basis, grams or ml in one, and whether the label prints the basis' own metric amount.
UNITS = {"ml": ("ml", 1, True), "cl": ("ml", 10, True), "l": ("ml", 1000, True),
         "floz": ("ml", FL_OZ_ML, False), "g": ("g", 1, True), "gram": ("g", 1, True),
         "grams": ("g", 1, True), "kg": ("g", 1000, True), "oz": ("g", OZ_G, False),
         "lb": ("g", LB_G, False), "lbs": ("g", LB_G, False)}
SERVING_UNITS = r"ml|fl\.?\s*oz|oz|grams?|g"
# A package's net quantity is also printed in litres, centilitres, kilos and pounds ("1.89L").
PACKAGE_UNITS = r"ml|cl|l|fl\.?\s*oz|oz|kg|lbs?|grams?|g"


def label_amounts(label, units=SERVING_UNITS):
    """Each amount in a label as (basis, grams or ml, printed in that metric unit)."""
    found = []
    for amount, unit in re.findall(rf"(\d+(?:[.,]\d+)?)\s*({units})\b", label, re.I):
        basis, factor, exact = UNITS[re.sub(r"[.\s]", "", unit.lower())]
        found.append((basis, float(amount.replace(",", ".")) * factor, exact))
    return found


def amount_in(found, basis):
    """The amount a label prints for `basis`: "8 fl oz (240 ml)" is 240 ml, not 236.6."""
    values = [(value, exact) for unit, value, exact in found if unit == basis]
    metric = [value for value, exact in values if exact]
    return metric[-1] if metric else values[0][0] if values else None


def serving_basis(label):
    """The basis and grams or ml of a serving label, when every amount in it agrees on one."""
    found = label_amounts(label)
    if len({basis for basis, _, _ in found}) != 1:
        return None, None
    return found[0][0], amount_in(found, found[0][0])


def label_basis(raw):
    """
    The basis of a product's per-100 values and its serving's amount in it, and how they were read.
    Records from before 2025 don't state it reliably (and the CSV omits it), so only units printed
    on the product are read, never its category: the serving label's one unit; where that label prints
    both ("1/4 cup (60 ml) (80.1 g)"), the one whose amount is OFF's serving_quantity, which OFF
    computed its per-100 values from; else the unit the package is sold in ("1.89L" is per 100 ml).
    """
    label = raw.get("serving_size", "") or ""
    basis, amount = serving_basis(label)
    if basis:
        return basis, amount, "serving"
    found = label_amounts(label)
    served = number(raw.get("serving_quantity"))
    matched = {unit for unit, value, _ in found
               if served and abs(value - served) <= max(0.5, served * 0.01)}
    if len(matched) == 1:
        return matched.pop(), served, "servingQuantity"
    sold = {unit for unit, _, _ in label_amounts(raw.get("quantity", "") or "", PACKAGE_UNITS)}
    if len(sold) == 1:
        basis = sold.pop()
        return basis, amount_in(found, basis), "package"
    return None, None, None


def csv_records(path):
    opener = gzip.open if str(path).endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", newline="") as source:
        csv.field_size_limit(16 * 1024 * 1024)
        for raw in csv.DictReader(source, delimiter="\t"):
            if None in raw:
                yield {"_malformed": True}
                continue
            for key in ("countries_tags", "labels_tags", "categories_tags"):
                raw[key] = [tag for tag in (raw.get(key) or "").split(",") if tag]
            raw["nutriments"] = {k: v for k, v in raw.items() if k.endswith("_100g") and v}
            yield raw


def jsonl_parts(path, size=32 * 1024 * 1024):
    """
    The export in pieces of whole lines for the worker processes: byte ranges they read themselves
    from a plain file, or the lines, from a compressed one that can only be read in order.
    """
    if str(path).endswith(".gz"):
        with gzip.open(path, "rb") as source:
            while lines := source.readlines(size):
                yield lines
        return
    total = path.stat().st_size
    with path.open("rb") as source:
        start = 0
        while start < total:
            source.seek(min(start + size, total))
            source.readline()
            end = source.tell()
            yield (str(path), start, end)
            start = end


def jsonl_part(part, limits):
    """The foods in one piece of the export, in order, and what was left out."""
    if isinstance(part, tuple):
        name, start, end = part
        with open(name, "rb") as source:
            source.seek(start)
            lines = source.read(end - start).split(b"\n")
    else:
        lines = part
    stats = collections.Counter()
    foods = [food for line in lines if line.strip()
             if (food := off_food(json.loads(line), limits, stats))]
    return foods, stats


# A nutrient's amount in grams per 100, from the unit Open Food Facts gives it in.
GRAMS = {"g": 1, "mg": 1e-3, "µg": 1e-6, "mcg": 1e-6}


def serving_unit(quantity, unit, label):
    """
    Whether a serving's amount is grams or ml: the unit the label prints that amount in
    ("1 cup (55 g)" is 55 g where OFF read 55 ml), else OFF's own unit when the label prints none.
    """
    found = label_amounts(label)
    matched = {basis for basis, value, _ in found
               if quantity and abs(value - quantity) <= max(0.5, quantity * 0.01)}
    if matched:
        return matched.pop() if len(matched) == 1 else None
    return unit if unit in ("g", "ml") and {basis for basis, _, _ in found} <= {unit} else None


def label_nutrition(raw):
    """
    Values per 100 g or ml from the nutrition object of Open Food Facts' newer records, as the
    *_100g fields it replaced, and their basis. Only label values count: not ones estimated from
    the ingredients, nor ones for the product once prepared. OFF puts every value on one basis and
    may name the wrong one (a smoothie's per-100 ml label as per 100 g), so each value's basis is
    read from what it was entered as: per 100 g, per 100 ml, or per serving, in the serving's unit.
    """
    nutrition = raw.get("nutrition") or {}
    entered = nutrition.get("input_sets") or []
    label = raw.get("serving_size") or ""
    nutriments, bases = {}, {}
    for key, entry in ((nutrition.get("aggregated_set") or {}).get("nutrients") or {}).items():
        index = entry.get("source_index")
        given = entered[index] if isinstance(index, int) and 0 <= index < len(entered) else {}
        value = number(entry.get("value"))
        if (entry.get("source") == "estimate" or given.get("preparation") != "as_sold"
                or value is None):
            continue
        per = entry.get("source_per")
        basis = ("g" if per == "100g" else "ml" if per == "100ml"
                 else serving_unit(number(given.get("per_quantity")), given.get("per_unit"), label)
                 if per == "serving" else None)
        unit = entry.get("unit")
        if unit == "kcal" and key in ("energy", "energy-kcal"):
            key = "energy-kcal"
        elif unit == "kJ" and key in ("energy", "energy-kj"):
            key = "energy-kj"
        elif unit in GRAMS:
            value *= GRAMS[unit]
        else:
            continue
        nutriments[f"{key}_100g"] = value
        bases[key] = basis
        # OFF fills a label's missing kilojoules in from its macros and shows them as the value, so
        # only a figure in what was entered is a second opinion on the calories.
        if key == "energy-kj" and any(((given.get("nutrients") or {}).get(name) or {}).get("value") is not None
                                      for name in ("energy-kj", "energy")):
            nutriments["energy-kj-entered_100g"] = value
            bases["energy-kj-entered"] = basis
    energy = "energy-kcal" if "energy-kcal" in bases else "energy-kj"
    core = {bases.get(key) for key in (energy, "proteins", "carbohydrates", "fat")}
    basis = core.pop() if len(core) == 1 else None
    if not basis:
        return None, nutriments
    # A value entered on another basis than the label's core can't join it.
    return basis, {f"{key}_100g": nutriments[f"{key}_100g"] for key, b in bases.items() if b == basis}


def product_name(raw):
    english = raw.get("product_name_en") or ""
    if english.strip() and ENGLISH_MARKETS.intersection(raw.get("countries_tags") or []):
        name = english
    else:
        name = raw.get("product_name") or english or next(
            (raw[key] for key in sorted(raw) if key.startswith("product_name_")
             and isinstance(raw[key], str) and raw[key].strip()), "")
    return " ".join(html.unescape(name).split())


def served_quantity(raw, basis):
    """
    OFF's own reading of the serving in the basis, and where it is: serving_quantity, or in newer
    records, which leave that out, the amount their per-serving values were entered for, when
    every set agrees. A set for exactly 100 is the per-100 values entered as a serving ("0.5 tsp"
    of 100 g).
    """
    if raw.get("serving_quantity_unit") == basis and (served := number(raw.get("serving_quantity"))):
        return served, "servingFromQuantity"
    entered = {number(given.get("per_quantity")) for given in (raw.get("nutrition") or {}).get("input_sets") or []
               if given.get("per") == "serving" and given.get("preparation") == "as_sold"
               and given.get("source") != "estimate" and given.get("per_unit") == basis} - {None, 0, 100}
    return (entered.pop(), "servingFromNutrition") if len(entered) == 1 else (None, None)


def serving_portion(raw, basis):
    """
    The serving the label prints, in the basis: "8 fl oz (240 ml)" is 240 ml. And how its amount
    was read, when it wasn't from the label itself.
    """
    label = (raw.get("serving_size") or "").strip()
    found = label_amounts(label)
    amount = amount_in(found, basis)
    if amount:
        return [{"label": label, "amount": amount}], None
    # OFF's own reading only for a label that prints no amount it could contradict ("1 bar"), and
    # a label that is only a number ("28") only where that's OFF's amount.
    served, source = (None, None) if found else served_quantity(raw, basis)
    if served and re.fullmatch(r"\d+(?:[.,]\d+)?", label):
        if abs(float(label.replace(",", ".")) - served) <= max(0.5, served * 0.01):
            return [{"label": f"{label} {basis}", "amount": served}], source
    elif served:
        return [{"label": label or "1 serving", "amount": served}], source
    # Else the label as first imported from the producer or USDA's branded foods, where edits
    # since have lost it ("0g", or "1 portion (175 g)" of olive oil sold per 100 ml), when it
    # measures the serving in the basis alone ("5 DROPS PER 8 oz. OF LIQUID (0.208 ml)" is no
    # 8 oz) and isn't the basis' own 100 ("100 g (100 g)").
    imported = (raw.get("serving_size_imported") or "").strip()
    kind, amount = serving_basis(imported)
    if kind == basis and amount and amount != 100:
        return [{"label": imported, "amount": amount}], "servingFromImport"
    return [], None


def per_serving(quantity, unit, source="packaging"):
    """A newer record's nutrition as entered for one serving, for SERVING_SAMPLES."""
    return {"nutrition": {"input_sets": [{"per": "serving", "per_quantity": quantity, "per_unit": unit,
                                          "preparation": "as_sold", "source": source}]}}


# Real products' serving fields and the portion each must get, checked before every build.
SERVING_SAMPLES = [
    ({"serving_size": "8 fl oz (240 ml)"}, "ml", [("8 fl oz (240 ml)", 240)]),
    ({"serving_size": "1 bar", "serving_quantity": "40", "serving_quantity_unit": "g"}, "g", [("1 bar", 40)]),
    # OFF's reading never overrides the label's own amount: "1 cup (55 g)" is no 55 ml.
    ({"serving_size": "1 cup (55 g)", "serving_quantity": 55, "serving_quantity_unit": "ml"}, "ml", []),
    # Newer records keep OFF's reading only with the per-serving values (Monster Ultra Vice Guava,
    # Pacific Foods' soup).
    ({"serving_size": "1 can", **per_serving(473, "ml")}, "ml", [("1 can", 473)]),
    ({"serving_size": "1 portion (1 cup)", **per_serving(240, "ml")}, "ml", [("1 portion (1 cup)", 240)]),
    ({**per_serving(56, "g")}, "g", [("1 serving", 56)]),
    # A label that is only a number is OFF's amount or nothing (a sharp cheddar; Nutella, whose
    # producer's 15 g is in the label first imported).
    ({"serving_size": "28", **per_serving(28, "g")}, "g", [("28 g", 28)]),
    ({"serving_size": "33", "serving_size_imported": "15 g (NUTELLA)", **per_serving(15, "g", "manufacturer")}, "g",
     [("15 g (NUTELLA)", 15)]),
    # The imported label where edits lost the serving: olive oil sold per 100 ml, and "0g".
    ({"serving_size": "1 portion (175 g)", "serving_size_imported": "1 Tbsp (15 ml)"}, "ml", [("1 Tbsp (15 ml)", 15)]),
    ({"serving_size": "0g", "serving_size_imported": "1/2 ONZ (14 g)"}, "g", [("1/2 ONZ (14 g)", 14)]),
    # Not servings: the per-100 values entered as one, and an imported label measuring something else.
    ({"serving_size": "0.5 tsp (0.5 tsp)", **per_serving(100, "g")}, "g", []),
    ({"serving_size": "1.0 cracker", "serving_size_imported": "100 g (100 g)"}, "g", []),
    ({"serving_size": "1", "serving_size_imported": "5 DROPS PER 8 oz. OF LIQUID (0.208 ml)"}, "g", []),
]


def check_servings():
    for fields, basis, expected in SERVING_SAMPLES:
        portions, _ = serving_portion(fields, basis)
        found = [(p["label"], p["amount"]) for p in portions]
        if found != expected:
            raise SystemExit(f"serving_portion({fields}, {basis!r}) gives {found}, not {expected}")


def check_entered_energy():
    """Kilojoules only count as the label's when someone entered them, not when OFF computed them."""
    def nutrients(kj_entered):
        macros = {key: {"value": 10, "unit": "g", "source_index": 0, "source": "packaging", "source_per": "100g"}
                  for key in ("proteins", "carbohydrates", "fat")}
        energy = {"unit": "kJ", "value": 900, "source_index": 0, "source": "packaging", "source_per": "100g"}
        calories = {**energy, "unit": "kcal", "value": 50}
        entered = {"energy-kj": {"unit": "kJ", "value": 900} if kj_entered else {"unit": "kJ", "value_computed": 900}}
        return {"nutrition": {"input_sets": [{"preparation": "as_sold", "nutrients": entered}], "aggregated_set": {
            "nutrients": {**macros, "energy-kj": energy, "energy-kcal": calories}}}}
    assert label_nutrition(nutrients(True))[1].get("energy-kj-entered_100g") == 900
    assert "energy-kj-entered_100g" not in label_nutrition(nutrients(False))[1]


def number(value):
    try:
        parsed = float(value)
        return parsed if math.isfinite(parsed) and parsed >= 0 else None
    except (TypeError, ValueError):
        return None


def rounded(value):
    """Four significant figures: more than any label prints, and a third of the bytes."""
    return None if value is None else float(f"{value:.4g}")


def barcode(value):
    code = str(value or "").strip()
    if not code.isascii() or not code.isdigit() or len(code) not in (8, 12, 13, 14):
        return None
    total = sum(int(d) * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(code[:-1])))
    return code.zfill(14) if (10 - total % 10) % 10 == int(code[-1]) else None


def valid_nutrients(n):
    return (n["calories"] is not None and n["calories"] <= 1000
            and all(n[k] is not None and n[k] <= 100 for k in ("protein", "carbs", "fat"))
            and sum(n[k] for k in ("protein", "carbs", "fat")) <= 105
            and (n["fiber"] is None or n["fiber"] <= 100)
            and (n["sodium"] is None or n["sodium"] <= 100000))


def checked_micros(nutrients, micros, limits, stats):
    """Drops values above what any food holds, and parts larger than their whole."""
    kept = {}
    for key, value in micros.items():
        whole = (nutrients["fat"] if key in FAT_PARTS
                 else nutrients["carbs"] if key == "sugar"
                 else micros.get("sugar", nutrients["carbs"]) if key == "addedSugar"
                 else None)
        if value > limits.get(key, math.inf) or (whole is not None and value > whole * 1.05 + 0.5):
            stats["excludedMicroValues"] += 1
            continue
        kept[key] = value
    return kept


# MARK: How processed, and fermented

FERMENTED_LABELS = {"en:probiotic", "en:probiotics", "en:with-live-cultures", "en:live-cultures",
                    "en:contains-live-cultures", "en:live-and-active-cultures", "en:raw-fermented",
                    "en:lacto-fermented", "en:unpasteurized"}
FERMENTED_CATEGORIES = {"en:kefirs", "en:kefir", "en:kimchi", "en:kimchis", "en:sauerkrauts", "en:sauerkraut",
                        "en:misos", "en:miso", "en:tempeh", "en:tempehs", "en:natto", "en:kombuchas", "en:kombucha",
                        "en:yogurts", "en:yoghurts", "en:greek-yogurts", "en:skyrs", "en:fermented-dairy-desserts",
                        "en:buttermilks", "en:lassis", "en:fermented-vegetables", "en:fermented-milks"}
# Fresh cultured dairy that Open Food Facts also files under cheese (skyr, fromage blanc, quark).
FRESH_CULTURED = {"en:yogurts", "en:skyrs", "en:kefirs", "en:fromages-blancs-petit-suisses-and-skyr", "en:quarks",
                  "en:cottage-cheeses", "en:fermented-milks"}
# Live cultures named in ingredients ("live and active cultures", "L. acidophilus", "B. lactis").
LIVE_CULTURES = re.compile(r"live (and active )?cultures|lactobacill|bifidobacteri|acidophilus|"
                           r"streptococcus thermophilus|l\. ?casei|b\. ?lactis|ferments? lactiques|cultures vivantes|"
                           r"probiotic", re.I)
# Fermented, but eaten cooked or made shelf-stable: no live cultures left.
NOT_LIVE = re.compile(r"frozen yog|bread|cracker|chip|bar\b|cereal|cookie|cake|pasteuri|heat[- ]treated|cuisin|"
                      r"soup|dressing|sauce|powder|pretzel|candy|candies|babyfood|dessert|\bcanned\b|granola|yogurt, frozen|"
                      r"margarine|spread|muffin|waffle|pancake|gumm|chocolate|ice cream|\bcooked\b", re.I)
# Cheese is fermented, but rarely what "eat fermented foods" means, and most of it is cooked,
# pressed or aged past live cultures that matter; counting it would steer toward more cheese.
NOT_LIVE_CATEGORIES = {"en:cheeses", "en:processed-cheeses", "en:cheese-spreads", "en:frozen-desserts",
                       "en:ice-creams-and-sorbets", "en:dietary-supplements", "en:biscuits-and-cakes",
                       "en:confectioneries", "en:breads", "en:bars", "en:butters", "en:creams", "en:fats",
                       "en:cocoa-and-its-products", "en:sauces", "en:vinegars", "en:alcoholic-beverages", "en:snacks",
                       "en:cereals-and-potatoes"}
# USDA groups whose yogurt or miso is a topping or an ingredient.
NOT_LIVE_GROUPS = {"fast foods", "restaurant foods", "baked products", "sweets", "snacks", "baby foods",
                   "fats and oils", "meals, entrees, and side dishes", "soups, sauces, and gravies"}
# Names of fermented foods across the languages packaged foods come in.
FERMENTED_NAMES = re.compile(r"\b(yogh?o?urt|yoghourt|joghurt|jogurt|yaourt|yogur|iogurte|kefir|kéfir|kimchi|sauerkraut|"
                             r"choucroute|kombucha|miso|natto|tempeh|skyr|lassi|ayran|kvass)\b", re.I)
USDA_FERMENTED = re.compile(r"\b(yogurt|kefir|sauerkraut|kimchi|miso|tempeh|natto|kombucha|buttermilk, cultured|"
                            r"skyr|lassi)\b", re.I)


# Categories whose products nearly all share a NOVA group, for products without the ingredients
# Open Food Facts computes it from. Checked in this order; anything else stays unknown.
CATEGORY_NOVA = [
    (4, {"en:processed-cheeses", "en:cheese-spreads", "en:margarines", "en:sodas", "en:colas", "en:energy-drinks",
         "en:sweetened-beverages", "en:artificially-sweetened-beverages", "en:candies", "en:confectioneries",
         "en:chocolate-candies", "en:gummies", "en:chewing-gum", "en:biscuits", "en:cookies", "en:cakes",
         "en:pastries", "en:viennoiseries", "en:ice-creams-and-sorbets", "en:ice-creams", "en:frozen-desserts",
         "en:crisps", "en:potato-crisps", "en:corn-chips", "en:tortilla-chips", "en:crackers", "en:pretzels",
         "en:bars", "en:cereal-bars", "en:protein-bars", "en:protein-powders", "en:meal-replacements",
         "en:instant-noodles", "en:pizzas", "en:frozen-pizzas", "en:meals-with-meat", "en:hot-dog-sausages",
         "en:frankfurters", "en:nuggets", "en:chicken-nuggets", "en:meat-analogues", "en:hazelnut-spreads",
         "en:cocoa-and-hazelnuts-spreads", "en:mayonnaises", "en:ketchup", "en:salad-dressings",
         "en:flavoured-milks", "en:chocolate-cereals", "en:dehydrated-soups"}),
    (2, {"en:vegetable-oils", "en:olive-oils", "en:butters", "en:honeys", "en:sugars", "en:salts", "en:vinegars",
         "en:maple-syrups"}),
    (3, {"en:cheeses", "en:smoked-salmons", "en:bacon", "en:beers", "en:wines", "en:canned-fishes",
         "en:canned-tunas", "en:pickles", "en:salted-butters"}),
    (1, {"en:fresh-vegetables", "en:fresh-fruits", "en:frozen-vegetables", "en:frozen-fruits", "en:eggs",
         "en:chicken-eggs", "en:rices", "en:dry-pastas", "en:rolled-oats", "en:oat-flakes",
         "en:lentils", "en:dried-legumes", "en:fruit-juices", "en:ground-coffees", "en:coffee-beans",
         "en:mineral-waters", "en:spring-waters", "en:flours",
         "en:fresh-meats", "en:fresh-fishes", "en:raisins", "en:dates", "en:unsalted-nuts", "en:quinoa"}),
]


def off_processing(raw):
    """Open Food Facts' own NOVA group, computed from the ingredients, or else one its categories
    make near certain; None when neither can say."""
    try:
        group = int(float(raw.get("nova_group")))
        if 1 <= group <= 4:
            return group
    except (TypeError, ValueError):
        pass
    categories = set(raw.get("categories_tags") or [])
    for group, tags in CATEGORY_NOVA:
        if categories & tags:
            return group
    return None


def off_fermented(raw, name):
    """A fermented food with live cultures, by its labels, categories or ingredients."""
    text = f"{name} {raw.get('ingredients_text_en') or raw.get('ingredients_text') or ''}"
    if NOT_LIVE.search(name):
        return False
    labels = set(raw.get("labels_tags") or [])
    categories = set(raw.get("categories_tags") or [])
    if categories & NOT_LIVE_CATEGORIES and not categories & FRESH_CULTURED:
        return False
    return bool(labels & FERMENTED_LABELS or categories & FERMENTED_CATEGORIES or LIVE_CULTURES.search(text)
                or FERMENTED_NAMES.search(name))


# Words in a USDA name that mark an industrial product whatever its category.
USDA_ULTRA = re.compile(
    r"frankfurter|bologna|salami|pepperoni|hot dog|nugget|breaded|batter|fast food|candies|candy|cookie|cracker|"
    r"\bchips?\b|snack|ready-to-eat|soft drink|carbonated|energy drink|sports drink|drink mix|frozen entree|"
    r"frozen dinner|\bpizza|doughnut|danish|pastr|\bcake|\bpie\b|pie,|muffin|toaster|pop-tart|margarine|"
    r"creamer|whipped topping|imitation|meatless|luncheon|ice cream|frozen yogurt|frozen dessert|syrups?,|"
    r"pudding|gelatin dessert|formula|meal replacement|\bbar\b|granola bar|cheese spread|cheese food|"
    r"pasteurized process|substitute|flavored|with added sugar|(?<!un)sweetened|artificial sweetener|frosting|"
    r"icing|marshmallow|instant|(mashed|flakes|granules).*dehydrated|dehydrated.*(mashed|flakes|granules)|"
    r"\bmix\b|\bdry mix|\bnog\b|french fried|hash brown|extruded|fat free.*(cheese|topping)", re.I)
USDA_PROCESSED = re.compile(r"\bcanned\b|cured|smoked|salted|salt added|pickle|in (heavy |light )?syrup|"
                            r"\bcheese\b|\bham\b|bacon|jerky|sauerkraut|kimchi|miso|tempeh|peanut butter|"
                            r"nut butter|tahini|hummus|soymilk|prepared from recipe|home-prepared|homemade|dulce de leche|"
                            r"condensed|evaporated|with sugar|sugar added", re.I)
CULINARY = re.compile(r"^(oil|butter|lard|shortening|sugars?|honey|syrup, maple|salt|vinegar|ghee|fat,|"
                      r"molasses|cornstarch|gelatin|leavening|baking (soda|powder))\b", re.I)


def usda_processing(category, name):
    """An estimate of the NOVA group for a USDA food, from its food group and name. Plain foods,
    raw or cooked, are 1; oils, butter and sugar 2; cheese, canned and cured foods 3; packaged
    snacks, sweets, processed meats, ready meals and soft drinks 4."""
    n = name.lower()
    c = (category or "").lower()
    if c == "baby foods":
        return None
    whole_cereal = c == "breakfast cereals" and n.startswith(("cereals, oats", "cereals, corn grits", "cereals, farina",
                                                                  "cereals, whole wheat hot", "cereals, wheatena",
                                                                  "cereals, cream of"))
    if whole_cereal and not re.search(r"flavored|sweetened|maple|cinnamon|raisins|apple|ready-to-eat", n):
        return 1
    if CULINARY.search(n) and not USDA_ULTRA.search(n):
        return 2
    if USDA_ULTRA.search(n):
        return 4
    # Fruit and vanilla yogurts, chocolate milk: sugar, flavourings and thickeners.
    if not n.startswith("nuts,") and re.search(r"\b(yogurt|kefir)\b|milk\b", n) and re.search(r"fruit|vanilla|strawberry|chocolate|lemon|peach|cherry|"
                                                             r"berry|banana|coconut|lime|pomegranate|apricot|mango|"
                                                             r"pineapple|raspberry|blueberry|coffee|mocha", n):
        return 4
    if c in {"fast foods", "snacks", "sweets", "breakfast cereals", "sausages and luncheon meats",
             "meals, entrees, and side dishes"}:
        return 3 if c == "sweets" and re.search(r"jams|preserves|jellies|marmalade", n) else 4
    if c == "baked products":
        return 3 if re.search(r"prepared from recipe|home-prepared|homemade", n) else 4
    if c == "soups, sauces, and gravies":
        return 3 if re.search(r"prepared from recipe|home-prepared|homemade", n) else 4
    if c == "beverages":
        if re.search(r"coffee, brewed|tea, brewed|espresso|\bwater\b|juice(?!.*(drink|cocktail|blend))", n):
            return 1
        if re.search(r"\bbeer\b|\bwine\b|cider", n):
            return 3
        return 4
    if c == "fats and oils":
        return 4 if re.search(r"salad dressing|mayonnaise|spread|blend", n) else 2
    if c == "restaurant foods":
        return 3
    if USDA_PROCESSED.search(n):
        return 3
    return 1


def fdc_nutrients(raw):
    """A FoodData Central record's nutrients and micronutrients, as SR Legacy and FNDDS both give them."""
    values = {n["nutrient"]["id"]: number(n.get("amount")) for n in raw["foodNutrients"]}
    nutrients = dict(zip(("calories", "protein", "carbs", "fat", "fiber", "sodium"),
                         (values.get(i) for i in (1008, 1003, 1005, 1004, 1079, 1093))))
    micros = {}
    for key, ids, _, _ in MICROS:
        parts = [next((values[i] for i in (part if isinstance(part, tuple) else (part,))
                       if values.get(i) is not None), None) for part in ids]
        if parts and parts[0] is not None:
            micros[key] = sum(part or 0 for part in parts)
    return nutrients, micros


# What an SR Legacy dish is called where its own name says where it's from first, and a plain
# food where SR Legacy has a name of its own for it: black-eyed peas are its cowpeas, a snow
# crab its queen crab.
USDA_OTHER_NAMES = {
    "Restaurant, family style, spaghetti and meatballs": ["Spaghetti and meatballs", "Spaghetti with meatballs"],
    "Candies, truffles, prepared-from-recipe": ["Chocolate truffles", "Truffles"],
    "Snacks, pork skins, plain": ["Pork rinds", "Chicharrones"],
    "Cowpeas, common (blackeyes, crowder, southern), mature seeds, cooked, boiled, without salt": ["Black-eyed peas", "Blackeyed peas"],
    "Fish, mahimahi, cooked, dry heat": ["Mahi mahi", "Mahi"],
    "Fish, tuna, yellowfin, fresh, cooked, dry heat": ["Ahi tuna", "Ahi"],
    "Fish, tuna, white, canned in water, drained solids": ["Albacore tuna", "Albacore"],
    "Fish, sea bass, mixed species, cooked, dry heat": ["Branzino"],
    "Fish, salmon, chinook, cooked, dry heat": ["King salmon"],
    "Fish, sablefish, cooked, dry heat": ["Black cod"],
    "Crustaceans, crab, alaska king, cooked, moist heat": ["King crab", "King crab legs"],
    "Crustaceans, crab, queen, cooked, moist heat": ["Snow crab", "Snow crab legs"],
}
# SR Legacy's groups of dishes: a burger, a restaurant's lo mein, a frozen lasagna.
USDA_DISHES = {"fast foods", "restaurant foods", "meals, entrees, and side dishes"}


def usda_foods(path, stats):
    with zipfile.ZipFile(path) as archive:
        with archive.open(next(n for n in archive.namelist() if n.endswith(".json"))) as src:
            records = json.load(src)["SRLegacyFoods"]
    for raw in records:
        stats["sourceRecords"] += 1
        category = (raw.get("foodCategory") or {}).get("description")
        nutrients, micros = fdc_nutrients(raw)
        if not valid_nutrients(nutrients):
            stats["excludedNutrition"] += 1
            continue
        portions = []
        for p in raw.get("foodPortions", []):
            grams = number(p.get("gramWeight"))
            amount = number(p.get("amount"))
            label = p.get("modifier") or p.get("portionDescription")
            if grams and amount and label:
                portions.append({"label": f"{amount:g} {label}", "amount": grams})
        name = raw["description"]
        fermented = (bool(USDA_FERMENTED.search(name)) and not NOT_LIVE.search(name)
                     and (category or "").lower() not in NOT_LIVE_GROUPS)
        yield Food(id=f"usda:{raw['fdcId']}", name=name, brand="", barcode=None, basis="g", nutrients=nutrients,
                   micros=checked_micros(nutrients, micros, {}, stats), portions=portions[:12], popularity=0,
                   markets="", nova=usda_processing(category, name),
                   traits=((TRAIT_FERMENTED if fermented else 0) | (TRAIT_DISH if (category or "").lower() in USDA_DISHES else 0)
                           | usda_energy_trait(nutrients, name, stats)),
                   also=USDA_OTHER_NAMES.get(name, []))


# SR Legacy's chain items are from 2006 to 2012; FNDDS, the survey database that replaced its
# fast-food and restaurant groups, has the generic restaurant foods ("Chicken nuggets, from fast
# food") and a few chain burgers by name ("Big Mac (McDonalds)"). The rest of FNDDS repeats SR,
# but for the foods it files chains' items under (an Egg McMuffin is an egg sandwich on an English
# muffin, with ham).
FNDDS_CHAIN = re.compile(r"\((McDonalds|Burger King)\)$")
FNDDS_RESTAURANT = re.compile(r"fast food|restaurant", re.I)
# The chains FNDDS's alternate descriptions name, as it spells them ("Starbuck's", "Dunkin Donut's").
FNDDS_CHAINS = re.compile(
    r"\b(Mc?Donald'?s|Burger King|Wendy'?s|Taco Bell|Subway|Starbuck'?s|Dunkin'?(?: Donut'?s)?|Domino'?s|"
    r"Papa John[’']?s|Pizza Hut|Chick-fil-A|Popeyes|KFC|Arby'?s|Sonic|Jack in the Box|Dairy Queen|"
    r"White Castle|Hardee'?s|Carl'?s Jr\.?|Little Caesars?|Krispy Kreme|Chipotle|Panera|In-N-Out)", re.I)
# The words search skips, as FoodDatabase's `stopWords`.
STOP_WORDS = {"a", "an", "and", "the", "of", "with", "in", "on", "or", "s", "to", "for", "style"}


def fndds_also(raw):
    """The chains' items FNDDS files under a food, as it names them ("McDonald's Chicken
    McNuggets" under chicken nuggets from fast food): its alternate descriptions that name a chain
    and something the chain sells, not a chain alone ("Burger King") nor a note ("NS as to skin
    eaten", "bread, bun or roll")."""
    names = []
    for attribute in raw.get("foodAttributes", []):
        if (attribute.get("foodAttributeType") or {}).get("name") != "Additional Description":
            continue
        for part in (attribute.get("value") or "").split(";"):
            part = " ".join(part.split()).strip(" ,")
            if not FNDDS_CHAINS.search(part):
                continue
            rest = [w for w in re.findall(r"[a-z0-9]+", FNDDS_CHAINS.sub(" ", part).lower())
                    if w not in STOP_WORDS and w != "nfs"]
            if rest and part not in names:
                names.append(part)
    return names


def fndds_portions(raw):
    """FNDDS's portions in its own order, its usual amount first: "Quantity not specified" is the
    amount people report when they don't say how much, and is dropped when no portion is that
    much ("1 McDonald's Big Mac" is, five nuggets aren't)."""
    portions = []
    usual = None
    for p in sorted(raw.get("foodPortions", []), key=lambda p: p.get("sequenceNumber") or 0):
        grams = number(p.get("gramWeight"))
        label = " ".join((p.get("portionDescription") or "").split())
        if not grams or not label:
            continue
        if label.lower() == "quantity not specified":
            usual = grams
        else:
            portions.append({"label": label, "amount": grams})
    first = next((p for p in portions if p["amount"] == usual), None)
    return ([first] if first else []) + [p for p in portions if p is not first]


# What FNDDS has that SR Legacy has little of: drinks as they're ordered and poured, at a bar or
# a coffee shop (a latte, a margarita, a milkshake), by FNDDS's own (What We Eat in America)
# categories. SR Legacy has brewed coffee, table wine and three spirits.
FNDDS_DRINKS = {
    "Coffee", "Tea", "Liquor and cocktails", "Wine", "Beer", "Smoothies and grain drinks", "Milk shakes and other dairy drinks",
    "Flavored milk, whole", "Flavored milk, reduced fat", "Flavored milk, lowfat", "Flavored milk, nonfat",
    # And what's poured from a can, a bottle or a fountain: a cola, an energy drink by its
    # brand, a sports drink, sparkling water, a protein shake, lemonade and the juice drinks.
    "Soft drinks", "Diet soft drinks", "Sport and energy drinks", "Diet sport and energy drinks", "Flavored or carbonated water",
    "Nutritional beverages", "Fruit drinks", "Other diet drinks",
}


# And dishes as they're eaten: a sandwich, a burrito, a plate of pad thai, a bowl of soup. SR
# Legacy has their ingredients and a few frozen entrees.
FNDDS_DISHES = {
    "Deli and cured meat sandwiches", "Burgers", "Egg/breakfast sandwiches", "Frankfurter sandwiches", "Peanut butter and jelly sandwiches",
    "Chicken fillet sandwiches", "Meat and BBQ sandwiches", "Seafood sandwiches", "Cheese sandwiches", "Vegetable sandwiches/burgers",
    "Meat mixed dishes", "Pasta mixed dishes, excludes macaroni and cheese", "Poultry mixed dishes", "Rice mixed dishes",
    "Seafood mixed dishes", "Stir-fry and soy-based sauce mixtures", "Other Mexican mixed dishes", "Burritos and tacos",
    "Fried rice and lo/chow mein", "Egg rolls, dumplings, sushi", "Bean, pea, legume dishes", "Vegetable dishes", "Nachos",
    "Macaroni and cheese", "Pizza", "Turnovers and other grain-based items", "Soups, broth-based", "Soups, cream-based",
    "Ramen and Asian broth-based soups", "Coleslaw, non-lettuce salads", "Lettuce and lettuce salads",
}
# And what's cooked or baked from one food more than put together from several: eggs as an
# omelet, potatoes mashed or fried, pancakes, a slice of cake, a scoop of ice cream, a dip.
FNDDS_PREPARED = {
    "Eggs and omelets", "Pancakes, waffles, French toast", "Cakes and pies", "Cookies and brownies", "Doughnuts, sweet rolls, pastries",
    "Ice cream and frozen dairy desserts", "Pudding", "Gelatins, ices, sorbets", "French fries and other fried white potatoes",
    "Mashed potatoes and white potato mixtures", "Fried vegetables", "Dips, gravies, other sauces", "Tomato-based condiments",
    "Oatmeal", "Grits and other cooked cereals",
    # Sweets and snacks by the names they're asked for: SR Legacy has a candy bar by each maker
    # and "Snacks, corn-based, extruded, puffs or twists", where these are "Chocolate candy",
    # "Candy, gummy" and "Popcorn, movie theater, with added butter".
    "Candy containing chocolate", "Candy not containing chocolate", "Nutrition bars", "Cereal bars", "Popcorn", "Potato chips",
    "Tortilla, corn, other chips",
}
# The SR Legacy group each of those is read as for how processed it is: a bag of chips is a
# snack, not a restaurant's dish.
FNDDS_GROUPS = {
    "Candy containing chocolate": "sweets", "Candy not containing chocolate": "sweets", "Nutrition bars": "snacks", "Cereal bars": "snacks",
    "Popcorn": "snacks", "Potato chips": "snacks", "Tortilla, corn, other chips": "snacks",
}
# And the plain meats, poultry, fish and cereals, which the survey names as they're cooked and
# eaten where SR Legacy names a cut, a grade and a trim: "Beef, steak", "Pork, chop", "Chicken
# breast, grilled, without skin", "Fish, cod, fried", "Bratwurst" and "Cereal, corn flakes",
# where SR has "Beef, flank, steak, separable lean only, trimmed to 0" fat, choice, cooked,
# broiled" and a cereal by each maker. By the SR Legacy group each is read as for how
# processed it is.
FNDDS_PLAIN_FOODS = {
    "Beef, excludes ground": "beef products", "Ground beef": "beef products", "Pork": "pork products",
    "Lamb, goat, game": "lamb, veal, and game products", "Liver and organ meats": "beef products",
    "Chicken, whole pieces": "poultry products", "Chicken patties, nuggets and tenders": "poultry products",
    "Turkey, duck, other poultry": "poultry products", "Fish": "finfish and shellfish products",
    "Shellfish": "finfish and shellfish products", "Bacon": "pork products", "Sausages": "sausages and luncheon meats",
    "Frankfurters": "sausages and luncheon meats", "Cold cuts and cured meats": "sausages and luncheon meats",
    "Ready-to-eat cereal, higher sugar (>21.2g/100g)": "breakfast cereals",
    "Ready-to-eat cereal, lower sugar (=<21.2g/100g)": "breakfast cereals",
    "Blueberries and other berries": "fruits and fruit juices", "Other fruits and fruit salads": "fruits and fruit juices",
}
# The ones of those the survey weighed cooked, as eaten, without always saying so: its "Beef,
# steak" has a grilled steak's numbers. The name says "cooked" where it says no other way, so
# no one logs a raw weight against it.
FNDDS_COOKED = {
    "Beef, excludes ground", "Ground beef", "Pork", "Lamb, goat, game", "Liver and organ meats", "Chicken, whole pieces",
    "Turkey, duck, other poultry", "Fish", "Shellfish", "Sausages",
}
FNDDS_STATED = re.compile(r"cooked|raw|baked|broiled|roast|grilled|fried|stewed|sauteed|steamed|boiled|smoked|rotisserie|canned|dried|"
                          r"pickled|cured|jerky|breaded|coated|barbecue|carnitas|\bstick|nugget|patty|peking|cocktail|scampi|sauce|"
                          r"imitation|mock|caviar|rinds|cracklings|pate|bones|tail$|feet|ears|^chicken skin$|cow head|thuringer", re.I)
# What says how much of it was eaten, which comes after how it was cooked.
FNDDS_EATEN = re.compile(r"(, (?:with skin|without skin|lean and fat|lean only|skinless|skin and coating removed))?$")


def fndds_cooked(name):
    """A plain meat's name with "cooked" where it says no way of cooking: "Steak, cooked",
    "Chicken breast, cooked, without skin"."""
    if FNDDS_STATED.search(name) or FNDDS_RESTAURANT.search(name):
        return name
    return FNDDS_EATEN.sub(lambda m: ", cooked" + (m.group(1) or ""), name, count=1)


# Of the fruit, only what SR Legacy has no entry for: berries or fruit of no one kind, a fruit
# salad, a fruit cocktail. The rest repeats it ("Blueberries, raw").
FNDDS_FRUIT = re.compile(r"^(Berries|Fruit)\b", re.I)
# Where the survey's answer came from, which the same food cooked at home is entered without
# ("from raw"), and which repeats it otherwise: bought cooked, frozen, or from a school lunch.
# And two that the words of a search take for another food: fried chicken "prepared skinless"
# for a skinless thigh, and the thin "sandwich steak" for a roast beef sandwich.
FNDDS_SOURCED = re.compile(r", from (pre-?cooked|frozen|school lunch|other sources)$|, skinless$|^Beef, sandwich steak", re.I)
# Game that SR Legacy has under "Game meat" and few log, whose one-word names would answer
# other searches: "goat" is the cheese, "mocha" isn't mock chicken legs begun.
FNDDS_RARE = re.compile(r"^(Goat|Bear|Beaver|Raccoon|Opossum|Squirrel|Groundhog|Armadillo|Turtle|Dove|Wild pig|Caribou|Moose|"
                        r"Mock chicken legs)\b")
# The survey's own distinctions, which no one logging a plate makes: which vegetables a mixture
# had by the survey's classes, which fat it was cooked in where butter, oil or none says it,
# which of nine dressings a salad was made with, and a pasta dish "ready-to-heat" beside the
# same from a restaurant and from a home recipe.
FNDDS_CODED = re.compile(r"excluding\s+carrots|excluding tomato|dark[- ]green vegetables|other than dark|and/or tomato-based|"
                         r"margarine|animal fat|cooking spray|mayonnaise-type|creamy dressing|Italian dressing|"
                         r"any type of fat free dressing|ready-to-heat|, other$", re.I)
# The survey's wording for what an answer wasn't or might have been, as what it usually was:
# a meat, a starch and vegetables is that whichever vegetables they were, a salad "made with
# mayonnaise" is the salad, and scrambled eggs are made with butter.
FNDDS_REWORDED = (
    (re.compile(r"\s+including\s+carrots,? broccoli,? and/or dark[- ] ?green leafy"), ""),
    (re.compile(r"; no potatoes, no sauce$|[;,] no sauce$|, excluding potatoes$"), ""),
    (re.compile(r"; no potatoes, "), "; "),
    (re.compile(r"; cream sauce, white sauce, or mushroom sauce$|; cream, white, or soup-based sauce$"), "; cream sauce"),
    (re.compile(r"; (?:with )?(.+)$"), r", with \1"),
    (re.compile(r"flavors other than chocolate"), "vanilla or other flavors"),
    (re.compile(r"meat other than pepperoni"), "sausage or other meat"),
    (re.compile(r"with icing or filling other than chocolate"), "with icing or filling"),
    (re.compile(r"salad with assorted vegetables including tomatoes and/or carrots"), "salad with assorted vegetables"),
    (re.compile(r"^(Chicken or turkey (?:caesar )?garden salad(?: with [a-z ]+)?), chicken and/or turkey.*(, no dressing)$"), r"\1\2"),
    (re.compile(r",? tomato,? and/or carrots, with or without other vegetables"), ""),
    (re.compile(r", made with mayonnaise$"), ""),
    (re.compile(r"^((?:Oatmeal|Grits|Cream of wheat|Cornmeal mush).*), no added fat$"), r"\1"),
    (re.compile(r"^(Egg omelet or scrambled egg.*), made with butter$"), r"\1"),
    # What was eaten of a cut or a piece, as it's said: a chicken breast "without skin", a
    # ribeye "lean only". Fried chicken is eaten with its coating unless it was taken off, and
    # home is where a food is cooked unless it says where it's from.
    (re.compile(r", prepared skinless, coating eaten"), ", skinless"),
    (re.compile(r", skin / coating not eaten"), ", skin and coating removed"),
    (re.compile(r", skin / coating eaten"), ""),
    (re.compile(r", skin not eaten"), ", without skin"),
    (re.compile(r", skin eaten"), ", with skin"),
    (re.compile(r",\s+lean and fat eaten"), ", lean and fat"),
    (re.compile(r", lean only eaten"), ", lean only"),
    (re.compile(r"grilled without sauce"), "grilled"),
    (re.compile(r", from raw$"), ""),
    # Fish the survey files by a word that isn't a fish on its own.
    (re.compile(r"^Fish, white, mixed species"), "Fish, white fish"),
    (re.compile(r"^Fish, stick$"), "Fish sticks"),
    (re.compile(r"^Fish, pickled$"), "Pickled fish"),
    (re.compile(r"^(Fruit salad), fresh or raw, (?:ex|in)cluding citrus fruits?, no dressing$"), r"\1"),
)
# The dishes that are whole foods put together or cooked: a salad without its dressing, eggs as
# an omelet or scrambled, oats and grits as they're cooked; not with what's added or sold made.
FNDDS_WHOLE = re.compile(r"^Lettuce, salad\b|^Egg omelet or scrambled egg|^Egg white omelet|^Guacamole|^Oatmeal|^Grits|^Cream of (wheat|rice)|"
                         r"^Cornmeal mush|^Whole wheat cereal, cooked|^Cereal, cooked", re.I)
FNDDS_NOT_WHOLE = re.compile(r"cheese|meat|bacon|ham\b|sausage|dressing,|fast food|restaurant|flavored|reduced sugar|chocolate", re.I)
# The plain foods filed with the dishes, which SR Legacy has.
FNDDS_PLAIN = re.compile(r"^(Egg, (whole|white|yolk)|Egg substitute|Egg white, |Duck egg|Goose egg|Quail egg)|, raw$|^Lettuce, cooked$", re.I)


# What a few of them are called where they're ordered, which their own words don't reach: FNDDS
# files a vodka cranberry under "Cape Cod" and a chai latte under "Tea, hot, with milk". Read
# like the chains' names for a food (`fndds_also`).
FNDDS_OTHER_NAMES = {
    "Cape Cod": ["Vodka cranberry"],
    "Screwdriver": ["Vodka and orange juice"],
    "Greyhound": ["Vodka and grapefruit juice"],
    "Seven and Seven": ["7 and 7"],
    "Whiskey and cola": ["Jack and Coke"],
    "Fruit punch, alcoholic": ["Rum punch"],
    "Martini, flavored": ["Espresso martini"],
    "Alcoholic coffee drink": ["Irish coffee"],
    "Hard seltzer": ["White Claw", "Spiked seltzer"],
    "Wine, sparkling": ["Champagne", "Prosecco"],
    "Beer, higher alcohol": ["IPA", "Craft beer"],
    "Coffee, Latte": ["Flat white", "Caffe latte"],
    "Coffee, Latte, flavored": ["Vanilla latte", "Caramel latte", "Hazelnut latte", "Pumpkin spice latte"],
    "Coffee, Iced Latte, flavored": ["Iced vanilla latte", "Iced caramel latte"],
    "Coffee, macchiato, sweetened": ["Caramel macchiato"],
    "Coffee, Cafe Mocha": ["Mocha latte"],
    "Coffee, Iced Cafe Mocha": ["Iced mocha latte"],
    "Iced Coffee, brewed": ["Cold brew", "Cold brew coffee"],
    "Coffee, brewed": ["Americano"],
    "Tea, hot, with milk": ["Chai latte", "Chai tea latte", "Masala chai", "Matcha latte", "Tea latte"],
    "Tea, bubble": ["Boba", "Boba tea", "Milk tea"],
    "Tea, hot, hibiscus": ["Agua de Jamaica"],
    "Iced Tea / Lemonade juice drink": ["Arnold Palmer"],
}
# And the dishes, by the names they're cooked and ordered by, keyed by the name the catalog gives
# each: the survey files a chicken parmesan under "Chicken or turkey parmigiana" and fettuccine
# alfredo under "Pasta with cream sauce".
FNDDS_DISH_NAMES = {
    # Plain meats, fish and cereals by the names they're bought and ordered by: the survey
    # files a sirloin steak under "Beef, steak, sirloin" and a kielbasa under "Polish sausage".
    "Beef, steak, sirloin, cooked": ["Sirloin steak", "Sirloin"],
    "Beef, steak, ribeye, cooked": ["Ribeye steak", "Rib eye steak", "Ribeye"],
    "Beef, steak, T-bone, cooked": ["T-bone steak", "Porterhouse steak"],
    "Beef, steak, strip, cooked": ["New York strip", "Strip steak", "NY strip steak"],
    "Beef, steak, tenderloin, cooked": ["Filet mignon", "Beef tenderloin"],
    "Beef, steak, round, cooked": ["Round steak"],
    "Beef, steak, chuck, cooked": ["Chuck steak"],
    "Beef, steak, cube, cooked": ["Cube steak"],
    "Beef, shortribs, cooked": ["Short ribs", "Beef short ribs"],
    "Beef, ground, patty": ["Hamburger patty", "Burger patty"],
    "Pork, ribs, cooked": ["Pork ribs", "Spare ribs", "Spareribs", "Baby back ribs"],
    "Barbecue pork": ["Pulled pork"],
    "Pork sausage, cooked": ["Breakfast sausage", "Sausage patty", "Sausage link", "Sausage links"],
    "Polish sausage, cooked": ["Kielbasa"],
    "Turkey bacon, cooked": ["Turkey bacon"],
    "Turkey, prepackaged or deli, luncheon meat": ["Deli turkey", "Sliced turkey", "Turkey lunch meat", "Turkey cold cuts"],
    "Ham, prepackaged or deli, luncheon meat": ["Deli ham", "Sliced ham", "Ham lunch meat"],
    "Chicken, prepackaged or deli, luncheon meat": ["Deli chicken", "Sliced chicken"],
    "Beef, prepackaged or deli, luncheon meat": ["Deli roast beef", "Sliced roast beef"],
    "Fish sticks": ["Fish fingers"],
    "Chicken tenders or strips": ["Chicken fingers", "Chicken tenders", "Chicken strips"],
    "Chicken leg, drumstick and thigh, cooked, without skin": ["Chicken leg quarter", "Leg quarter"],
    "Crab, cooked": ["Crab legs", "Crab meat"],
    "Lobster, cooked": ["Lobster tail"],
    "Fish, snapper, cooked": ["Red snapper"],
    # Neither source has an Arctic char: it's the trout, the fish it's closest to.
    "Fish, trout, cooked": ["Arctic char"],
    "Cereal, shredded wheat, plain": ["Shredded wheat"],
    "Berries": ["Mixed berries"],
    "Berries, frozen": ["Frozen berries", "Frozen mixed berries"],
    "Fruit mixture, frozen": ["Frozen fruit", "Frozen mixed fruit"],
    "Fruit": ["Mixed fruit"],
    # Sweets and snacks, which the survey files by kind: milk chocolate is its "Chocolate
    # candy", gummy bears its "Candy, gummy" and a protein bar its nutrition bar.
    "Chocolate candy": ["Milk chocolate", "Chocolate bar", "Milk chocolate bar", "Candy bar"],
    "Dark chocolate candy": ["Dark chocolate", "Dark chocolate bar"],
    "White chocolate candy": ["White chocolate"],
    "Chocolate candy, peanut butter filled": ["Peanut butter cup", "Peanut butter cups"],
    "Chocolate candy, fudge": ["Fudge", "Chocolate fudge"],
    "Almonds, chocolate covered candy": ["Chocolate covered almonds"],
    "Peanuts, chocolate covered candy": ["Chocolate covered peanuts"],
    "Candy, gummy": ["Gummy bears", "Gummies", "Gummy worms", "Gummy candy"],
    "Candy, licorice": ["Licorice"],
    "Candy, lollipop": ["Lollipop", "Sucker"],
    "Candy, cotton": ["Cotton candy"],
    "Candy, marshmallow": ["Marshmallows", "Marshmallow"],
    "Candy, caramel": ["Caramels", "Caramel candy"],
    "Candy, taffy": ["Taffy", "Salt water taffy"],
    "Candy, mint": ["Mints", "Breath mints"],
    "Candy, hard": ["Hard candy"],
    "Candy, fruit snacks": ["Fruit snacks"],
    "Candy, fruit leather": ["Fruit leather", "Fruit roll up"],
    "Candy, peanut brittle": ["Peanut brittle"],
    "Chewing gum": ["Gum"],
    "Chewing gum, sugar free": ["Sugar free gum", "Sugarless gum"],
    "Cheese flavored corn snacks": ["Cheese puffs", "Cheese curls", "Cheese doodles"],
    "Popcorn, ready-to-eat, kettle": ["Kettle corn"],
    "Popcorn, caramel coated": ["Caramel corn", "Caramel popcorn"],
    "Popcorn, movie theater, with added butter": ["Movie theater popcorn", "Buttered popcorn"],
    "Vegetable chips": ["Veggie chips", "Veggie straws"],
    "Nutrition bar or meal replacement bar": ["Protein bar", "Energy bar", "Meal replacement bar", "Nutrition bar"],
    "Cereal or Granola bar": ["Granola bar", "Cereal bar"],
    "Cheese steak sandwich or sub on white": ["Philly cheesesteak", "Cheesesteak"],
    "Chicken fillet sandwich, fried, from fast food": ["Fried chicken sandwich", "Crispy chicken sandwich"],
    "Chicken fillet sandwich, grilled, from fast food": ["Grilled chicken sandwich"],
    "Egg sandwich on English muffin, with sausage": ["Breakfast sandwich", "Sausage egg and cheese"],
    "Egg sandwich on English muffin, with bacon": ["Bacon egg and cheese"],
    "Tuna salad sandwich on white, with cheese": ["Tuna melt"],
    "Pasta with cream sauce, restaurant": ["Fettuccine alfredo", "Alfredo pasta", "Pasta alfredo"],
    "Pasta with cream sauce and poultry, restaurant": ["Chicken alfredo", "Chicken fettuccine alfredo"],
    "Pasta with cream sauce and seafood, restaurant": ["Shrimp alfredo", "Seafood alfredo"],
    "Pasta with cream sauce and meat, restaurant": ["Carbonara", "Spaghetti carbonara", "Pasta carbonara"],
    "Pasta with tomato-based sauce and meat, restaurant": [
        "Spaghetti bolognese", "Pasta bolognese", "Spaghetti with meat sauce", "Pasta with meat sauce"],
    "Pasta with tomato-based sauce and poultry, restaurant": ["Chicken pasta", "Pasta with chicken"],
    "Chili with meat and beans": ["Beef chili", "Chili con carne", "Chili with beans"],
    "Chili with chicken and beans": ["Turkey chili", "Chicken chili"],
    "Chili, white": ["White chicken chili"],
    "Oatmeal, regular or quick, made with milk": ["Oatmeal with milk", "Oatmeal made with milk", "Porridge with milk"],
    "Oatmeal, regular or quick, made with water": ["Oatmeal with water", "Oatmeal made with water", "Porridge"],
    "Oatmeal, regular or quick, made with non-dairy milk": ["Oatmeal with almond milk", "Oatmeal with oat milk", "Oatmeal with soy milk"],
    "Water, carbonated, plain": ["Sparkling water", "Seltzer", "Seltzer water", "Soda water"],
    "Water, carbonated, flavored": ["Flavored sparkling water", "Flavored seltzer"],
    "Soft drink, fruit flavored, caffeine free": ["Lemon lime soda", "Orange soda"],
    "Nutritional drink or shake, high protein, ready-to-drink": ["Protein shake", "Protein drink"],
    "Nutritional drink or shake, ready-to-drink": ["Meal replacement shake", "Nutrition shake"],
    "Lemonade, fruit juice drink": ["Lemonade"],
    "Pasta with tomato-based sauce, restaurant": [
        "Spaghetti marinara", "Pasta marinara", "Pasta with marinara sauce", "Spaghetti with tomato sauce", "Pasta with tomato sauce"],
    "Pasta with tomato-based sauce and cheese": ["Baked ziti"],
    "Macaroni or noodles with cheese": ["Mac and cheese", "Macaroni and cheese"],
    "Chicken or turkey parmigiana": ["Chicken parmesan", "Chicken parm"],
    "Veal parmigiana": ["Veal parmesan"],
    "Eggplant parmesan casserole, regular": ["Eggplant parmesan", "Eggplant parm", "Eggplant parmigiana"],
    "Chicken curry": ["Chicken tikka masala", "Butter chicken", "Tikka masala"],
    "Chicken or turkey caesar garden salad, no dressing": ["Chicken caesar salad"],
    "Chicken or turkey garden salad, no dressing": ["Grilled chicken salad", "Chicken salad with lettuce"],
    "Lettuce, salad with assorted vegetables, no dressing": [
        "Garden salad", "Side salad", "House salad", "Tossed salad", "Green salad", "Lettuce salad"],
    "Roll with meat and/or shrimp, vegetables and rice paper, not fried": ["Spring roll", "Summer roll", "Fresh spring roll"],
    "Wonton, dumpling or pot sticker, steamed": ["Dumplings", "Steamed dumplings", "Gyoza", "Potstickers"],
    "Wonton, dumpling or pot sticker, fried": ["Fried dumplings", "Fried wontons", "Fried potstickers"],
    "Sushi roll, California": ["California roll"],
    "Sushi roll, salmon": ["Salmon roll", "Salmon avocado roll"],
    "Sushi roll tuna": ["Tuna roll", "Spicy tuna roll"],
    "Sushi roll, shrimp": ["Shrimp tempura roll"],
    "Sushi roll, avocado": ["Avocado roll"],
    "Sushi roll, vegetable": ["Veggie roll", "Cucumber roll"],
    "Sushi roll, eel": ["Eel roll", "Unagi roll"],
    "Sushi, topped with salmon": ["Salmon nigiri", "Nigiri"],
    "Sushi, topped with tuna": ["Tuna nigiri"],
    "Soup, New England clam chowder": ["Clam chowder"],
    "Soup, broccoli cheese": ["Broccoli cheddar soup"],
    "Gelatin dessert": ["Jello", "Jell-O"],
    "Potato tots": ["Tater tots"],
    "Cheese dip": ["Queso", "Queso dip", "Nacho cheese"],
    "Cheese dip with chili pepper": ["Chile con queso"],
    "Shrimp in garlic sauce, Puerto Rican style": ["Shrimp scampi", "Garlic shrimp"],
    "Palak Paneer": ["Saag paneer"],
    "Stuffed cabbage rolls with beef and rice": ["Stuffed cabbage", "Cabbage rolls"],
    "Stuffed shells, cheese-filled, with tomato sauce, meatless": ["Stuffed shells"],
    "Manicotti, cheese-filled, with tomato sauce, meatless": ["Manicotti"],
    "Doughnut, yeast type": ["Glazed donut", "Glazed doughnut"],
    "Roll, sweet, cinnamon bun, frosted": ["Cinnamon roll"],
    "Cake or cupcake, chocolate with chocolate icing, bakery": ["Chocolate cake", "Chocolate cupcake"],
    "Cake or cupcake, white with white icing, bakery": ["Vanilla cake", "Vanilla cupcake", "Birthday cake", "White cake"],
    "Chicken or turkey and vegetables, with soy-based sauce": ["Chicken stir fry", "Chicken and vegetable stir fry"],
    "Beef and vegetables, with soy-based sauce": ["Beef stir fry", "Beef and vegetable stir fry"],
    "Pork and vegetables, with soy-based sauce": ["Pork stir fry"],
    "Shrimp and vegetables, with soy-based sauce": ["Shrimp stir fry"],
    "Tofu and vegetables, with soy-based sauce": ["Tofu stir fry", "Vegetable stir fry", "Veggie stir fry"],
    "Egg, Benedict": ["Eggs Benedict"],
    "Pizza with sausage or other meat, from restaurant or fast food": ["Sausage pizza", "Meat lovers pizza"],
    "Pizza with meat and vegetables, from restaurant or fast food, thin crust": ["Supreme pizza"],
    "Pizza with meat and fruit, thin crust": ["Hawaiian pizza"],
    "Pizza, cheese, with vegetables, from restaurant or fast food, thin crust": ["Veggie pizza", "Vegetable pizza"],
    "Pizza, cheese, from restaurant or fast food, thin crust": ["Margherita pizza"],
    "Milk shake, fast food, vanilla or other flavors": ["Milkshake", "Vanilla milkshake", "Strawberry milkshake"],
    "Milk shake, fast food, chocolate": ["Chocolate milkshake"],
    "Gyro sandwich": ["Gyro"],
    "Grilled cheese sandwich": ["Grilled cheese"],
    "Peanut butter and jelly sandwich": ["Peanut butter and jelly", "PB&J"],
    "Reuben sandwich": ["Reuben"],
    "French dip sandwich": ["French dip"],
    "Cuban sandwich": ["Cubano"],
    "Sloppy joe sandwich, on white bun": ["Sloppy joe"],
    "Chili hot dog sandwich, on white bun": ["Chili dog", "Chili cheese dog"],
    "Bacon, lettuce, tomato sandwich on white": ["BLT", "BLT sandwich"],
    "Barbecue pork sandwich, on white bun": ["Pulled pork sandwich"],
    "Double cheeseburger, from fast food, 2 small patties": ["Double cheeseburger"],
    "Beef shish kabob with vegetables": ["Beef kebab", "Shish kebab"],
    "Chicken or turkey shish kabob with vegetables": ["Chicken kebab"],
    "Lamb shish kabob with vegetables": ["Lamb kebab"],
    # And a few the survey files with plain meat, fish and vegetables.
    'Chicken "wings" with hot sauce, from fast food / restaurant': ["Buffalo wings", "Hot wings", "Buffalo chicken wings"],
    'Chicken "wings", boneless, with hot sauce, from fast food / restaurant': ["Boneless wings", "Boneless buffalo wings"],
    "Pork, carnitas": ["Carnitas"],
    "Spinach, creamed": ["Creamed spinach"],
    "Shrimp cocktail": ["Prawn cocktail"],
}
# The milks a coffee drink "with non-dairy milk" is ordered with.
PLANT_MILKS = ("oat milk", "almond milk", "soy milk", "coconut milk", "oat", "almond", "soy")


def fndds_other_names(description, name):
    """A food's other names: the ones listed for it, by the survey's description or the name the
    catalog gives it, and for a coffee drink "with non-dairy milk" the drink by each milk ("Oat
    milk latte", "Iced soy latte")."""
    names = list(FNDDS_OTHER_NAMES.get(description, [])) + FNDDS_DISH_NAMES.get(name, [])
    parts = [part.strip() for part in description.split(",")]
    if parts[0] == "Coffee" and parts[2:] == ["with non-dairy milk"]:
        drink = parts[1].lower()
        iced, rest = ("Iced ", drink[5:]) if drink.startswith("iced ") else ("", drink)
        names += [f"{iced}{milk} {rest}".capitalize() for milk in PLANT_MILKS]
    return names


def fndds_drink_processing(category, name):
    """An estimate of the NOVA group for one of FNDDS's drinks. Spirits and cocktails are 4, as
    are soft, sports, energy and nutritional drinks, juice drinks, sweetened, flavoured, bottled
    and instant drinks and anything made with ice cream or chocolate; beer, wine and cider are 3,
    with the drinks cultured or cooked at home (kombucha, horchata, atole); coffee, tea, plain
    sparkling water, unsweetened coconut water and a smoothie of whole fruit, with or without
    milk, are 1."""
    n = name.lower()
    if re.search(r"^water, carbonated, plain|^coconut water, unsweetened", n):
        return 1
    if category == "Liquor and cocktails" or re.search(r"malt beverage|seltzer|wine cooler", n):
        return 4
    if category in ("Wine", "Beer"):
        return 3
    if category not in ("Coffee", "Tea", "Smoothies and grain drinks"):
        return 4
    if re.search(r"(?<!un)sweetened|flavored|mocha|frozen|bottled|canned|instant|lightened|juice drink|bubble|\blight\b|protein|"
                 r"substitute|chicory|low calorie", n):
        return 4
    if re.search(r"kombucha|horchata|atole|licuado|frescavena|corn beverage|cafe con leche", n):
        return 3
    return 1


def fndds_name(description):
    """FNDDS's name without its coders' notes: "NFS" is "not further specified" and "NS as to
    fat" "not specified as to", which say what a survey answer left out, not what the food is."""
    parts = [part.strip() for part in " ".join(description.split()).split(",")]
    kept = [part for part in parts if part != "NFS" and not part.startswith("NS as to")]
    name = ", ".join(kept) or parts[0]
    for coded, plain in FNDDS_REWORDED:
        name = coded.sub(plain, name)
    return name


def fndds_foods(path, stats):
    with zipfile.ZipFile(path) as archive:
        with archive.open(next(n for n in archive.namelist() if n.endswith(".json"))) as src:
            records = json.load(src)["SurveyFoods"]
    named = set()
    for raw in records:
        stats["fnddsRecords"] += 1
        name = fndds_name(raw["description"])
        category = (raw.get("wweiaFoodCategory") or {}).get("wweiaFoodCategoryDescription")
        # Before "cooked" is added after it.
        sourced = FNDDS_SOURCED.search(name)
        if category in FNDDS_COOKED:
            name = fndds_cooked(name)
        chains = fndds_also(raw)
        others = fndds_other_names(" ".join(raw["description"].split()), name)
        also = chains + [other for other in others if other not in chains]
        plated = (category in FNDDS_DISHES or category in FNDDS_PREPARED) and not FNDDS_CODED.search(name) and not FNDDS_PLAIN.search(name)
        plain = (category in FNDDS_PLAIN_FOODS and not sourced and not FNDDS_RARE.search(name)
                 and (FNDDS_PLAIN_FOODS[category] != "fruits and fruit juices" or FNDDS_FRUIT.search(name)))
        eaten = category in FNDDS_DRINKS or plated or plain
        if not FNDDS_RESTAURANT.search(name) and not FNDDS_CHAIN.search(name) and not also and not eaten:
            continue
        # Two answers the coders tell apart can be one food once their notes are gone.
        if name.lower() in named:
            stats["fnddsSameName"] += 1
            continue
        named.add(name.lower())
        nutrients, micros = fdc_nutrients(raw)
        if not valid_nutrients(nutrients):
            stats["fnddsExcludedNutrition"] += 1
            continue
        # Read as SR Legacy's groups of the same name: fast food is ultra-processed, and a dish
        # from a restaurant, from either ("Black beans, from fast food / restaurant") or a chain's
        # item under a plain name ("Frozen coffee drink") is processed unless its name says
        # otherwise (nuggets, pizza, cookies). A drink is read by what it is (see
        # `fndds_drink_processing`).
        fast = FNDDS_CHAIN.search(name) or (re.search("fast food", name, re.I) and not re.search("restaurant", name, re.I))
        dish = re.sub(r"fast food|restaurant", "", name, flags=re.I)
        stats["fnddsIncluded"] += 1
        stats["fnddsDrinks"] += category in FNDDS_DRINKS
        stats["fnddsDishes"] += category in FNDDS_DISHES or category in FNDDS_PREPARED
        stats["fnddsPlain"] += bool(plain)
        stats["fnddsWithChainNames"] += bool(chains)
        stats["fnddsChainNames"] += len(chains)
        stats["fnddsOtherNames"] += len(also) - len(chains)
        if category in FNDDS_DRINKS and not fast and not FNDDS_RESTAURANT.search(name):
            nova = fndds_drink_processing(category, name)
        elif FNDDS_WHOLE.search(name) and not FNDDS_NOT_WHOLE.search(name):
            # A dish is processed as a restaurant's is; a salad of raw vegetables, eggs
            # scrambled or folded into an omelet and oats or grits cooked in water or milk are
            # still whole foods.
            nova = 1
        else:
            group = FNDDS_GROUPS.get(category) or (FNDDS_PLAIN_FOODS.get(category) if plain and not fast else None)
            nova = usda_processing(group or ("fast foods" if fast else "restaurant foods"), dish)
        # Kombucha is the one of them with live cultures.
        fermented = TRAIT_FERMENTED if re.search(r"\bkombucha\b", name, re.I) else 0
        yield Food(id=f"usda:{raw['fdcId']}", name=name, brand="", barcode=None, basis="g", nutrients=nutrients,
                   micros=checked_micros(nutrients, micros, {}, stats), portions=fndds_portions(raw)[:12],
                   popularity=0, markets="", nova=nova,
                   traits=fermented | (TRAIT_DISH if category in FNDDS_DISHES else 0) | usda_energy_trait(nutrients, name, stats),
                   also=also)
    # A dish's other names are listed by the name the catalog gives it, so one that no food has
    # is a name that changed.
    unnamed = [name for name in FNDDS_DISH_NAMES if name.lower() not in named]
    if unnamed:
        raise SystemExit(f"FNDDS_DISH_NAMES lists foods the catalog doesn't have: {unnamed}")


def assess_energy(nutrients, name, kj=None, serving=None):
    """What food_energy makes of `nutrients`, or None without the numbers to tell."""
    if any(nutrients[key] is None for key in ("calories", "protein", "carbs", "fat")):
        return None
    return food_energy.assess(nutrients["calories"], nutrients["protein"], nutrients["carbs"], nutrients["fat"],
                              nutrients["fiber"], name, kj, serving)


def reconcile_energy(nutrients, name, kj, serving=None):
    """Repairs `nutrients`' calories in place where that's safe; the verdict, or None without numbers."""
    verdict = assess_energy(nutrients, name, kj, serving)
    if verdict:
        nutrients["calories"] = verdict[1]
    return verdict


def count_energy(verdict, stats):
    if verdict and verdict[0] != food_energy.OK:
        stats[f"energy{verdict[0].capitalize()}"] += 1
        if verdict[0] == food_energy.REPAIRED:
            stats[f"energyRepaired{verdict[2][0].upper()}{verdict[2][1:]}"] += 1


def usda_energy_trait(nutrients, name, stats):
    """USDA's numbers are laboratory data and are never changed, but one that doesn't fit its macros
    is flagged like anyone else's, and that includes a row the rules would call repairable."""
    verdict = assess_energy(nutrients, name)
    count_energy(verdict, stats)
    return TRAIT_ENERGY_SUSPECT if verdict and verdict[0] in (food_energy.SUSPECT, food_energy.REPAIRED) else 0


def off_food(raw, limits, stats):
    """One Open Food Facts product as a catalog food, or None and the reason in `stats`."""
    stats["sourceRecords"] += 1
    if raw.get("_malformed"):
        stats["excludedMalformedRows"] += 1
        return None
    name = product_name(raw)
    code = barcode(raw.get("code"))
    if not name or not code:
        stats["excludedIdentity"] += 1
        return None
    source = None
    if "nutrition" in raw:
        basis, v = label_nutrition(raw)
    else:
        v = raw.get("nutriments") or {}
        # Older records' *_100g fields held per-100 ml values too, under a per that defaulted to
        # 100g (the CSV omits it), so only a per-100 ml one is taken as given. Otherwise the
        # basis is a unit printed on the product, and 100g only where none is. Never convert
        # volume into mass.
        per = raw.get("nutrition_data_per")
        basis, _, source = ("ml", None, None) if per == "100ml" else label_basis(raw)
        if not basis and per == "100g" and raw.get("serving_quantity_unit") != "ml":
            basis = "g"
    energy = number(v.get("energy-kcal_100g"))
    if energy is None:
        kj = number(v.get("energy-kj_100g"))
        if kj is None and v.get("energy_unit") == "kJ":
            kj = number(v.get("energy_100g"))
        energy = kj / 4.184 if kj is not None else None
    sodium = number(v.get("sodium_100g"))
    nutrients = {"calories": energy, "protein": number(v.get("proteins_100g")),
                 "carbs": number(v.get("carbohydrates_100g")), "fat": number(v.get("fat_100g")),
                 "fiber": number(v.get("fiber_100g")), "sodium": sodium * 1000 if sodium is not None else None}
    # First, so kilojoules typed as calories over the 1,000 limit below are repaired, not dropped.
    energy_kj = number(v.get("energy-kj-entered_100g"))
    verdict = reconcile_energy(nutrients, name, energy_kj)
    if not valid_nutrients(nutrients):
        stats["excludedNutrition"] += 1
        return None
    # A per-100 g label on a product served only in ml is a drink entered under the old default.
    served = ({unit for unit, _, _ in label_amounts(raw.get("serving_size") or "")}
              or {raw.get("serving_quantity_unit")})
    if not basis or basis == "g" and served == {"ml"}:
        stats["excludedAmbiguousBasis"] += 1
        return None
    # How many were read past the serving label's own unit (see label_basis).
    if source == "servingQuantity":
        stats["basisFromServingQuantity"] += 1
    elif source == "package":
        stats["basisFromPackage"] += 1
    # And how many servings were read past the label's own amount (see serving_portion).
    portions, read = serving_portion(raw, basis)
    if read:
        stats[read] += 1
    if verdict and verdict[0] == food_energy.SUSPECT and portions:
        verdict = reconcile_energy(nutrients, name, energy_kj, portions[0]["amount"])
    count_energy(verdict, stats)
    suspect = bool(verdict) and verdict[0] == food_energy.SUSPECT
    micros = {}
    for key, _, columns, factor in MICROS:
        value = next((number(v.get(f"{c}_100g")) for c in columns
                      if v.get(f"{c}_100g") not in (None, "")), None)
        if value is not None and (value > 0 or key in LABELED):
            micros[key] = value * factor
    # "Coca-Cola, The Coca-Cola Company" is sold as Coca-Cola.
    brand = " ".join(html.unescape((raw.get("brands") or "").split(",")[0]).split())
    scans = number(raw.get("unique_scans_n")) or 0
    markets = {COUNTRIES.get(tag.split(":", 1)[-1].lower())
               for tag in raw.get("countries_tags") or []}
    return Food(id=f"off:{raw['code']}", name=name, brand=brand, barcode=code, basis=basis, nutrients=nutrients,
                micros=checked_micros(nutrients, micros, limits, stats), portions=portions,
                popularity=round(math.log1p(scans), 2), markets=" ".join(sorted(markets - {None})),
                nova=off_processing(raw),
                traits=(TRAIT_FERMENTED if off_fermented(raw, name) else 0) | (TRAIT_ENERGY_SUSPECT if suspect else 0))


def off_foods(path, limits, stats):
    """Each product of an export, in its order; JSONL is read across every core."""
    if ".csv" in path.name:
        for raw in csv_records(path):
            if food := off_food(raw, limits, stats):
                yield food
        return
    read = functools.partial(jsonl_part, limits=limits)
    with multiprocessing.Pool() as pool:
        for foods, counts in pool.imap(read, jsonl_parts(path)):
            stats.update(counts)
            yield from foods


# Bits of the traits column.
TRAIT_FERMENTED = 1
# Calories too far from the macros to trust, with no way to tell which is wrong (food_energy.py).
TRAIT_ENERGY_SUSPECT = 2
# A dish of several foods (a sandwich, a casserole, a stir-fry), which the search doesn't take
# for one of the foods in it.
TRAIT_DISH = 4

CORE = ("calories", "protein", "carbs", "fat", "fiber", "sodium")
# A row's values by position, the commonest first so that most rows end early. The order is
# stored in catalog_meta, so the app reads it from the catalog rather than assuming it.
ORDER = CORE + ("sugar", "saturatedFat", "cholesterol", "calcium", "iron", "transFat",
                "potassium", "addedSugar", "vitaminD", "vitaminC", "vitaminA")
ORDER += tuple(key for key, *_ in MICROS if key not in ORDER)


def compact(value):
    value = rounded(value)
    return int(value) if value is not None and value.is_integer() else value


def row_data(food):
    """
    What the app reads besides the columns, as compact as JSON allows, since it is most of a
    catalog's size: [basis, values per 100 g or ml in ORDER (null where unknown, trailing ones
    left off), portions as [label, amount] when there are any].
    """
    values = {**food.nutrients, **food.micros}
    row = [compact(values.get(key)) for key in ORDER]
    while row[-1] is None:
        row.pop()
    data = [food.basis, row]
    if food.portions:
        data.append([[p["label"], compact(p["amount"])] for p in food.portions])
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


def food_values(data, order):
    """A row's values by key, from either the compact data or the object earlier versions kept."""
    data = json.loads(data)
    return dict(zip(order, data[1])) if order else data["nutrients"]


def build(source, path, destination, limits=None, fndds=None):
    """Writes `<source>.pending.db` into `destination` for the caller to check and install. Returns
    its manifest entry and its richest amount of each micronutrient."""
    destination.mkdir(parents=True, exist_ok=True)
    digest = sha256_file(path)
    # The recipe is both files: food_energy.py changes what the catalog holds.
    recipe = hashlib.sha256((sha256_file(Path(__file__)) + sha256_file(Path(food_energy.__file__))).encode()).hexdigest()
    fndds_digest = sha256_file(fndds) if fndds else None
    version = f"{source}-v{SCHEMA_VERSION}-{digest[:12]}-{recipe[:8]}"
    if fndds_digest:
        version = f"{source}-v{SCHEMA_VERSION}-{digest[:12]}-{fndds_digest[:8]}-{recipe[:8]}"
    temporary = destination / f"{source}.pending.db"
    temporary.unlink(missing_ok=True)
    connection = sqlite3.connect(temporary)
    # Every typed word is searched as a prefix, and across millions of foods "ch" or "chi" has
    # thousands of words to merge: the prefix indexes keep a keystroke near 10 ms on a laptop for
    # a sixth more size. Without column sizes, bm25 measures the few rows a search ranks itself.
    # Only USDA's foods have other names, one a line: the chains' items FNDDS files under them,
    # searched with the name and brand.
    also = source == "usda"
    connection.executescript(f"""
        CREATE TABLE staged (id TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT NOT NULL,
                             barcode TEXT, popularity REAL NOT NULL, markets TEXT NOT NULL,
                             data TEXT NOT NULL, nova INTEGER, traits INTEGER NOT NULL
                             {", also TEXT NOT NULL" if also else ""}) WITHOUT ROWID;
        CREATE TABLE foods (id TEXT, name TEXT NOT NULL, brand TEXT NOT NULL, barcode INTEGER,
                            popularity REAL NOT NULL, markets TEXT NOT NULL, data TEXT NOT NULL,
                            nova INTEGER, traits INTEGER NOT NULL DEFAULT 0
                            {", also TEXT NOT NULL DEFAULT ''" if also else ""});
        CREATE VIRTUAL TABLE food_search USING fts5(name, brand{", also" if also else ""}, content='foods',
                                                    content_rowid='rowid',
                                                    tokenize='unicode61 remove_diacritics 2',
                                                    prefix='2 3', columnsize=0);
        CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    """)
    stats = collections.Counter()
    peaks = collections.defaultdict(float)
    if source == "usda":
        foods = itertools.chain(usda_foods(path, stats), fndds_foods(fndds, stats) if fndds else ())
    else:
        foods = off_foods(path, limits, stats)
    with connection:
        for food in foods:
            values = (food.id, food.name, food.brand, food.barcode, food.popularity,
                      food.markets, row_data(food), food.nova, food.traits)
            if also:
                values += ("\n".join(food.also),)
            result = connection.execute(f"INSERT OR IGNORE INTO staged VALUES ({', '.join('?' * len(values))})", values)
            if not result.rowcount:
                stats["duplicates"] += 1
                continue
            stats["included"] += 1
            stats["microValues"] += len(food.micros)
            stats["withMicros"] += bool(food.micros)
            stats["withPortions"] += bool(food.portions)
            if food.nova is not None:
                stats[f"nova{food.nova}"] += 1
            else:
                stats["novaUnknown"] += 1
            stats["fermented"] += bool(food.traits & TRAIT_FERMENTED)
            for key, value in food.micros.items():
                peaks[key] = max(peaks[key], value)
        # A search ranks the first matches in row order, so the most scanned foods come first.
        # The 14-digit barcode is kept as a number, and an id that is "off:" and the barcode's
        # 13-digit form, as nearly all are, is left out for the app to derive: together a sixth
        # of the catalog. The id has no index: the app never looks a food up by it.
        connection.executescript(f"""
            INSERT INTO foods (id, name, brand, barcode, popularity, markets, data, nova, traits{", also" if also else ""})
                SELECT CASE WHEN id = 'off:' || substr(barcode, 2) THEN NULL ELSE id END,
                       name, brand, CAST(barcode AS INTEGER), popularity, markets, data, nova, traits
                       {", also" if also else ""} FROM staged
                ORDER BY popularity DESC, id;
            DROP TABLE staged;
            CREATE INDEX foods_barcode ON foods(barcode);
        """)
        connection.execute("INSERT INTO food_search(food_search) VALUES ('rebuild')")
        connection.execute("INSERT INTO food_search(food_search) VALUES ('optimize')")
        # The words the catalog knows and how many foods use each, for correcting typos.
        connection.executescript("""
            CREATE VIRTUAL TABLE temp.vocabulary USING fts5vocab(main, food_search, row);
            CREATE TABLE terms (term TEXT PRIMARY KEY, foods INTEGER NOT NULL) WITHOUT ROWID;
            INSERT INTO terms SELECT term, doc FROM temp.vocabulary
                WHERE length(term) >= 3 AND term NOT GLOB '*[0-9]*';
            DROP TABLE temp.vocabulary;
            -- A misspelled word is checked against the words in many foods, not all of them.
            CREATE INDEX terms_foods ON terms(foods);
        """)
        license_id, notice = LICENSES[source]
        notice = notice.format(recipe=RECIPE_URL)
        url = source_url(source, path)
        connection.executemany("INSERT INTO catalog_meta VALUES (?, ?)", [
            ("version", version), ("license", license_id), ("attribution", notice),
            ("source", f"{url} {FNDDS_URL}" if fndds else url),
            ("nutrients", json.dumps(ORDER, separators=(",", ":")))])
        connection.execute(f"PRAGMA user_version={SCHEMA_VERSION}")
    stats["terms"] = connection.execute("SELECT count(*) FROM terms").fetchone()[0]
    assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    connection.execute("VACUUM")
    connection.close()
    manifest = {"version": version, "sourceUrl": url,
                "recipeSha256": recipe, "sourceSha256": digest,
                "sha256": sha256_file(temporary), "bytes": temporary.stat().st_size,
                "license": license_id, "developmentSample": url == OFF_SAMPLE_URL, **dict(stats)}
    if fndds:
        manifest.update({"fnddsUrl": FNDDS_URL, "fnddsSha256": fndds_digest})
    return manifest, dict(peaks)


def source_url(source, path):
    if source == "usda":
        return USDA_URL
    return (OFF_SAMPLE_URL if "random-modulo" in path.name
            else OFF_CSV_URL if ".csv" in path.name else OFF_URL)


def catalog_peaks(path):
    """The richest food's amount of each micronutrient in a built catalog."""
    keys = {key for key, *_ in MICROS}
    peaks = collections.defaultdict(float)
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    order = connection.execute("SELECT value FROM catalog_meta WHERE key = 'nutrients'").fetchone()
    order = order and json.loads(order[0])
    for (data,) in connection.execute("SELECT data FROM foods"):
        for key, value in food_values(data, order).items():
            if key in keys and value is not None:
                peaks[key] = max(peaks[key], value)
    connection.close()
    return dict(peaks)


def micro_limits(peaks):
    """A packaged food holding over twice the richest USDA food's amount is a unit slip (micrograms
    entered as grams), not food. Added sugar has no USDA value; its whole limits it."""
    return {key: peak * 2 for key, peak in peaks.items()}


def check():
    check_servings()
    check_entered_energy()
    print(f"{len(SERVING_SAMPLES)} serving labels and entered energy read as expected")
