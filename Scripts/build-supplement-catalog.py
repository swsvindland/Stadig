#!/usr/bin/env python3
"""Build Macro Track's offline supplement catalog from the NIH Dietary Supplement Label Database.
Python standard library only.

Usage: python3 Scripts/build-supplement-catalog.py [--dsld /path/DSLD-full-database-CSV.zip]

Writes supplements.db into Apps/MacroTrack/Catalogs (bundled from there, not in git) and records
its source and counts in Packages/FoodDatabase/catalog-manifest.json. Without --dsld, the export
is downloaded once (about 90 MB) into ~/Library/Caches/SystemFoodCatalog/dsld.

Each label keeps its serving as printed ("2 Softgel(s)") and its Supplement Facts lines as
[name, amount, unit], in label order. The app reads names and units into nutrients itself
(SystemCore's SupplementIngredients), so one set of rules serves the catalog and label photos.
One label per barcode: the one on the market, else the newest. Labels without a barcode are kept
while on the market, for search by name.

The DSLD is a US government work in the public domain (dsld.od.nih.gov).
"""
import argparse
import csv
import datetime
import hashlib
import io
import json
import re
import sqlite3
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "Apps" / "MacroTrack" / "Catalogs" / "supplements.db"
MANIFEST = ROOT / "Packages" / "FoodDatabase" / "catalog-manifest.json"
CACHE = Path.home() / "Library" / "Caches" / "SystemFoodCatalog" / "dsld"
DSLD_URL = "https://api.ods.od.nih.gov/dsld/s3/data/DSLD-full-database-CSV.zip"
SCHEMA_VERSION = 1
# A label lists more than this only for blends of herbs; the rest add nothing to a dose.
MAX_LINES = 60

csv.field_size_limit(1 << 30)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rows(archive, prefix):
    """Every row of the export's numbered CSV files that start with `prefix`."""
    for name in sorted(n for n in archive.namelist() if Path(n).name.startswith(prefix) and n.endswith(".csv")):
        with archive.open(name) as raw:
            yield from csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8", errors="replace", newline=""))


def check_digit_valid(code):
    digits = [int(c) for c in code]
    total = sum(d * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(digits[:-1])))
    return (10 - total % 10) % 10 == digits[-1]


def barcode(value):
    """The 14-digit key the app stores barcodes under, or None."""
    digits = re.sub(r"\D", "", value or "")
    if len(digits) == 11:
        # Printed without its leading zero ("74312 70640 0").
        digits = "0" + digits
    if len(digits) not in (8, 12, 13, 14) or not check_digit_valid(digits):
        return None
    return int(digits.zfill(14))


def number(value):
    try:
        result = float(value.replace(",", ""))
    except (AttributeError, ValueError):
        return None
    return result if result == result and result >= 0 else None


def compact(value):
    return round(value, 4) if value != int(value) else int(value)


def build(source):
    archive = zipfile.ZipFile(source)
    products = {}
    for row in rows(archive, "ProductOverview"):
        try:
            dsld = int(row["DSLD ID"])
        except (KeyError, ValueError):
            continue
        name = (row.get("Product Name") or "").strip()
        if not name:
            continue
        products[dsld] = {
            "name": name[:120],
            "brand": (row.get("Brand Name") or "").strip()[:80],
            "barcode": barcode(row.get("Bar Code")),
            "serving": (row.get("Serving Size") or "").strip()[:80],
            "market": 1 if (row.get("Market Status") or "").strip() == "On Market" else 0,
            "entered": (row.get("Date Entered into DSLD") or "").strip(),
            "lines": [],
        }
    for row in rows(archive, "DietarySupplementFacts"):
        try:
            product = products.get(int(row["DSLD ID"]))
        except (KeyError, ValueError):
            continue
        if product is None or len(product["lines"]) >= MAX_LINES:
            continue
        amount = number(row.get("Amount Per Serving"))
        unit = (row.get("Amount Per Serving Unit") or "").strip()
        name = (row.get("Ingredient") or "").strip()
        if not name or amount is None or unit in ("%", "None"):
            continue
        product["lines"].append([name[:80], compact(amount), unit[:20]])

    # One label per barcode: on the market first, then the newest entry.
    chosen = {}
    loose = []
    for dsld, product in products.items():
        code = product["barcode"]
        if code is None:
            if product["market"]:
                loose.append((dsld, product))
            continue
        best = chosen.get(code)
        rank = (product["market"], product["entered"], dsld)
        if best is None or rank > (best[1]["market"], best[1]["entered"], best[0]):
            chosen[code] = (dsld, product)
    kept = sorted(list(chosen.values()) + loose, key=lambda item: item[0])

    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    temporary = DESTINATION.with_suffix(".tmp")
    temporary.unlink(missing_ok=True)
    db = sqlite3.connect(temporary)
    db.executescript("""
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        CREATE TABLE supplements (id INTEGER PRIMARY KEY, name TEXT NOT NULL, brand TEXT NOT NULL,
                                  barcode INTEGER, serving TEXT NOT NULL, market INTEGER NOT NULL, data TEXT NOT NULL);
        CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    """)
    db.executemany(
        "INSERT INTO supplements VALUES (?, ?, ?, ?, ?, ?, ?)",
        ((dsld, p["name"], p["brand"], p["barcode"], p["serving"], p["market"],
          json.dumps(p["lines"], ensure_ascii=False, separators=(",", ":"))) for dsld, p in kept))
    db.executescript("""
        CREATE INDEX supplements_barcode ON supplements(barcode);
        CREATE VIRTUAL TABLE supplement_search USING fts5(name, brand, content='supplements', content_rowid='id',
                                                          tokenize='unicode61 remove_diacritics 2', prefix='2 3', columnsize=0);
        INSERT INTO supplement_search(supplement_search) VALUES ('rebuild');
        INSERT INTO supplement_search(supplement_search) VALUES ('optimize');
    """)
    source_hash = sha256_file(source)
    recipe_hash = sha256_file(__file__)
    version = f"dsld-v{SCHEMA_VERSION}-{source_hash[:12]}-{recipe_hash[:8]}"
    meta = {
        "version": version,
        "license": "Public domain (US government work)",
        "attribution": "NIH Office of Dietary Supplements, Dietary Supplement Label Database (dsld.od.nih.gov)",
        "source": DSLD_URL,
        "built": datetime.date.today().isoformat(),
    }
    db.executemany("INSERT INTO catalog_meta VALUES (?, ?)", meta.items())
    db.commit()
    db.execute("VACUUM")
    db.close()
    temporary.replace(DESTINATION)

    counts = {
        "version": version,
        "sourceUrl": DSLD_URL,
        "recipeSha256": recipe_hash,
        "sourceSha256": source_hash,
        "sha256": sha256_file(DESTINATION),
        "bytes": DESTINATION.stat().st_size,
        "license": "Public domain",
        "sourceRecords": len(products),
        "included": len(kept),
        "withBarcode": len(chosen),
        "onMarket": sum(p["market"] for _, p in kept),
        "lines": sum(len(p["lines"]) for _, p in kept),
    }
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    manifest["dsld"] = counts
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(counts, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dsld", type=Path, help="the DSLD full-database CSV export (.zip); downloaded when left out")
    args = parser.parse_args()
    source = args.dsld
    if source is None:
        CACHE.mkdir(parents=True, exist_ok=True)
        source = CACHE / "DSLD-full-database-CSV.zip"
        if not source.exists():
            print(f"Downloading {DSLD_URL}")
            partial = source.with_suffix(".part")
            urllib.request.urlretrieve(DSLD_URL, partial)
            partial.replace(source)
    build(source)


if __name__ == "__main__":
    main()
