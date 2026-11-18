#!/usr/bin/env python3
"""Writes the brands people in the US scan most, for search suggestions.

    python3 Scripts/popular-brands.py Apps/MacroTrack/Catalogs/off.db

A brand counts by its scanned foods sold at home (markets us, ca or world only), each by its
popularity, so a store's own label with hundreds of foods outranks one famous product. Run it when
the packaged-food catalog is rebuilt and review the diff: the list is data, but a new catalog can
bring a mislabelled brand to the top.
"""

import collections
import re
import sqlite3
import sys

COUNT = 320
HOME = {"us", "ca", "world"}
# Brand fields that name no brand, and other countries' store labels that list a US market.
SKIP = {
    "original", "organic", "organics", "simply", "ready", "giant", "star", "bear", "david", "prime", "bloom", "ratio", "built", "365",
    "sainsbury's", "tesco", "coop", "marks & spencers", "m&s food", "danone", "cadbury", "the kroger co", "fritolay", "walmart", "costco",
}
OUT = "Packages/FoodDatabase/Sources/FoodDatabase/Search/PopularBrands.swift"


def key(brand):
    return re.sub(r"[^a-z0-9]", "", brand)


def main():
    db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    weight = collections.defaultdict(float)
    spelled = collections.defaultdict(collections.Counter)
    for brand, popularity, markets in db.execute("SELECT brand, popularity, markets FROM foods WHERE popularity >= 1.0 AND brand <> ''"):
        if not set(markets.split()) or not set(markets.split()) <= HOME or "us" not in markets.split():
            continue
        name = brand.split(",")[0].strip().lower().replace("’", "'").rstrip(".")
        if len(key(name)) < 3 or name in SKIP or not re.fullmatch(r"[a-z0-9&'.\- ]+", name) or len(name.split()) > 4:
            continue
        weight[key(name)] += popularity
        spelled[key(name)][name] += 1
    top = sorted(weight, key=lambda k: -weight[k])[:COUNT]
    brands = [spelled[k].most_common(1)[0][0] for k in top]
    lines = [""]
    for brand in brands:
        item = f'"{brand}", '
        if len(lines[-1]) + len(item) > 140:
            lines.append("")
        lines[-1] += item
    body = "\n".join(f"        {line.rstrip()}" for line in lines)
    with open(OUT, "w") as out:
        out.write(
            "/// The brands people in the US scan most, the most scanned first. Generated from the packaged-food\n"
            "/// catalog by `Scripts/popular-brands.py`; don't edit it by hand.\n"
            "enum PopularBrands {\n"
            "    static let names: [String] = [\n"
            f"{body}\n"
            "    ]\n"
            "}\n"
        )
    print(f"{len(brands)} brands -> {OUT}")


if __name__ == "__main__":
    main()
