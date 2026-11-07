"""Checks a built food catalog's calories against its macros, for Scripts/build-catalogs.py.
Python standard library only.

Reports how many foods agree, how many are explained (alcohol, sweeteners, vinegars), how many could
still be repaired and how many are suspect, with the most scanned examples. A report can list every
row that doesn't agree. Open Food Facts rows that could still be repaired mean off.db was built before
the builder repaired them: USDA's are reported but never changed. The rules are in food_energy.py.
"""
import collections
import csv
import json
import sqlite3

import food_energy
from food_energy import EXPLAINED, OK, REPAIRED, SUSPECT

# Each row is `verdict, the kcal a repair would give, then what it's handed`.
SAMPLES = [
    (OK, None, dict(kcal=165, protein=31, carbs=0, fat=3.6)),                       # chicken breast
    (OK, None, dict(kcal=370, protein=8, carbs=60, fat=9, fiber=10)),               # US label: carbs hold the fibre
    (OK, None, dict(kcal=390, protein=8, carbs=60, fat=9, fiber=10)),               # EU label: fibre beside them
    (OK, None, dict(kcal=3, protein=0.4, carbs=0.2, fat=0)),                        # rounding, not error
    (OK, None, dict(kcal=539, protein=6.3, carbs=57.5, fat=30.9, kj=2252)),         # a hazelnut spread
    (EXPLAINED, None, dict(kcal=43, protein=0.5, carbs=3.6, fat=0, name="Lager beer")),
    (EXPLAINED, None, dict(kcal=2, protein=0, carbs=99, fat=0, name="Stevia powder")),
    (EXPLAINED, None, dict(kcal=88, protein=0.5, carbs=17, fat=0, name="Vinegar, balsamic")),
    (REPAIRED, 58.8, dict(kcal=246, protein=1.75, carbs=10.1, fat=1.28)),           # kilojoules as calories
    (REPAIRED, 250, dict(kcal=2500, protein=5, carbs=40, fat=8, kj=1046)),          # a typo, and the label's kJ
    (REPAIRED, 210, dict(kcal=63, protein=10, carbs=20, fat=10, serving=30)),       # a serving's calories
    (SUSPECT, None, dict(kcal=77, protein=10, carbs=3.2, fat=30)),                  # macros or calories? unknown
    (SUSPECT, None, dict(kcal=375, protein=0.7, carbs=0.8, fat=82)),
    (SUSPECT, None, dict(kcal=0, protein=11, carbs=41, fat=38, fiber=7)),
    (SUSPECT, None, dict(kcal=257, protein=10, carbs=3.1, fat=8)),
    (SUSPECT, None, dict(kcal=70, protein=0.5, carbs=5.8, fat=0, serving=355)),      # a beer, not a serving mix-up
    (EXPLAINED, None, dict(kcal=58, protein=0.5, carbs=5.8, fat=0, name="Bière blonde")),
    (OK, None, dict(kcal=257, protein=10, carbs=3.1, fat=18, tolerance=0.25)),      # a wider tolerance
]


def check():
    for want, repaired, food in SAMPLES:
        verdict, kcal, _ = food_energy.assess(**food)
        assert verdict == want, f"{food}: {verdict}, not {want}"
        if repaired is not None:
            assert abs(kcal - repaired) <= repaired * 0.01, f"{food}: {kcal:.1f}, not {repaired}"
    print(f"{len(SAMPLES)} sample foods read as expected")


def rows(connection):
    order = json.loads(connection.execute("SELECT value FROM catalog_meta WHERE key = 'nutrients'").fetchone()[0])
    fiber = order.index("fiber")
    query = "SELECT COALESCE(id, CAST(barcode AS TEXT)), name, brand, popularity, data FROM foods"
    for key, name, brand, popularity, data in connection.execute(query):
        data = json.loads(data)
        values = data[1]
        portions = data[2] if len(data) > 2 else []
        yield key, name, brand, popularity, dict(
            kcal=values[0], protein=values[1], carbs=values[2], fat=values[3],
            fiber=values[fiber] if len(values) > fiber else None, name=name,
            serving=portions[0][1] if portions else None)


def validate(path, tolerance, writer):
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    version = connection.execute("SELECT value FROM catalog_meta WHERE key = 'version'").fetchone()[0]
    counts, reasons = collections.Counter(), collections.Counter()
    worst = collections.defaultdict(list)
    for key, name, brand, popularity, food in rows(connection):
        verdict, kcal, reason = food_energy.assess(**food, tolerance=tolerance)
        counts[verdict] += 1
        if verdict == OK:
            continue
        reasons[f"{verdict}: {reason}"] += 1
        least, most = food_energy.macro_range(food["protein"], food["carbs"], food["fat"], food["fiber"])
        row = [path.name, key, name, brand, popularity, verdict, reason, food["kcal"], round(least), round(most),
               round(kcal, 1), food["protein"], food["carbs"], food["fat"], food["fiber"], food["serving"]]
        if writer:
            writer.writerow(row)
        if verdict != EXPLAINED:
            worst[reason].append((popularity, name, brand, food["kcal"], round(least), round(most)))
    total = sum(counts.values())
    print(f"\n{path.name} ({version}): {total:,} foods")
    for verdict in (OK, EXPLAINED, REPAIRED, SUSPECT):
        print(f"  {verdict:10}{counts[verdict]:>11,}{counts[verdict] / max(total, 1):>8.2%}")
    for reason, count in sorted(reasons.items()):
        print(f"    {reason:24}{count:>9,}")
    for reason, foods in sorted(worst.items()):
        print(f"  most scanned, {reason} (kcal; what the macros make):")
        for _, name, brand, kcal, least, most in sorted(foods, reverse=True)[:5]:
            print(f"    {name[:44]:44} {brand[:16]:16} {kcal:>7} kcal; {least}-{most}")
    return counts[REPAIRED]


def validate_all(paths, tolerance=food_energy.TOLERANCE, report=None):
    """Reports on each catalog; how many packaged foods could still be repaired."""
    handle = report.open("w", newline="", encoding="utf-8") if report else None
    writer = csv.writer(handle) if handle else None
    if writer:
        writer.writerow(["catalog", "id", "name", "brand", "popularity", "verdict", "reason", "kcal", "macrosLeast",
                         "macrosMost", "repairedKcal", "protein", "carbs", "fat", "fiber", "serving"])
    unrepaired = 0
    for path in paths:
        repairable = validate(path, tolerance, writer)
        if "usda" not in path.name:
            unrepaired += repairable
    if handle:
        handle.close()
    return unrepaired
