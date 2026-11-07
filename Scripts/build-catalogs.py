#!/usr/bin/env python3
"""Build Stadig Macro's catalogs: one command for every source. Python standard library only.

    python3 Scripts/build-catalogs.py check                 # the rules, on sample labels and foods
    python3 Scripts/build-catalogs.py update [--download]   # what's newer upstream; fetch it into the cache
    python3 Scripts/build-catalogs.py build [usda off supplements] [--output DIR]
    python3 Scripts/build-catalogs.py validate [catalog.db ...] [--report out.csv]

Every source is read into one food record (food_catalog.Food), but the output stays in a file per
licence and way of shipping, so the app works without off.db and nothing else takes on its ODbL
terms. Supplement labels are a different kind of data and keep a catalog of their own.

`build` makes the catalogs named, or all three, from the newest source in the cache
(~/Library/Caches/SystemFoodCatalog), or from --usda, --fndds, --off and --dsld. Each is checked
before it replaces the old one, and its sources, hashes and counts go into
Packages/FoodDatabase/catalog-manifest.json. With --output, it builds there and touches nothing else.
After rebuilding off.db or supplements.db, run Scripts/publish-catalogs.sh.
"""
import argparse
import dataclasses
import datetime
import email.utils
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import urllib.request

import food_catalog
import food_energy
import food_validation
import supplement_catalog

ROOT = Path(__file__).resolve().parent.parent
CACHE = Path.home() / "Library" / "Caches" / "SystemFoodCatalog"
MANIFEST = ROOT / "Packages" / "FoodDatabase" / "catalog-manifest.json"
USDA_FOLDER = ROOT / "Packages" / "FoodDatabase" / "Sources" / "FoodDatabase" / "Resources"
MACRO_FOLDER = ROOT / "Apps" / "MacroTrack" / "Catalogs"
CATALOGS = {"usda": USDA_FOLDER, "off": MACRO_FOLDER, "supplements": MACRO_FOLDER}
# The manifest keeps supplements under its source's name.
MANIFEST_KEYS = {"usda": "usda", "off": "off", "supplements": "dsld"}
# FoodData Central dates its files, so a new release is a new name that only this page shows.
FDC_DOWNLOADS = "https://fdc.nal.usda.gov/download-datasets"


@dataclasses.dataclass(frozen=True)
class Source:
    name: str
    url: str
    # Where it's cached, as a glob when each download gets its own dated name.
    cached: str
    # About how big, to say before downloading it unasked.
    megabytes: int
    fdc_kind: str | None = None

    def newest(self):
        """The cached copy to build from: the latest date in its name, then the latest download."""
        found = list(CACHE.glob(self.cached))
        return max(found, key=lambda path: (re.findall(r"\d{8}", path.name), path.stat().st_mtime), default=None)


SOURCES = {
    "sr": Source("USDA SR Legacy", food_catalog.USDA_URL, "usda-sr-legacy.zip", 14, "sr_legacy_food"),
    "fndds": Source("USDA FNDDS", food_catalog.FNDDS_URL, "usda-fndds.zip", 4, "survey_food"),
    "off": Source("Open Food Facts", food_catalog.OFF_URL, "openfoodfacts-products*.jsonl.gz", 13_400),
    "dsld": Source("NIH DSLD", supplement_catalog.DSLD_URL, "dsld/DSLD-full-database-CSV.zip", 90),
}


def remote_file(source):
    """What the server has now: size, and when it last changed."""
    with urllib.request.urlopen(urllib.request.Request(source.url, method="HEAD"), timeout=30) as response:
        modified = response.headers.get("Last-Modified")
        return int(response.headers.get("Content-Length") or 0), modified and email.utils.parsedate_to_datetime(modified)


def newer_fdc_release(source, page):
    """A FoodData Central file dated after the one `source` names, if the downloads page lists one."""
    pattern = rf"FoodData_Central_{source.fdc_kind}_json_(\d{{4}}-\d{{2}}(?:-\d{{2}})?)\.zip"
    dates = re.findall(pattern, page)
    newest = max(dates, default="")
    return newest if newest > re.search(pattern, source.url).group(1) else None


def is_stale(source, size):
    """Why the cached copy isn't what the server has, if it isn't. A new export is a new size."""
    cached = source.newest()
    if cached is None:
        return "not cached"
    if size and size != cached.stat().st_size:
        return f"{cached.stat().st_size:,} bytes cached, {size:,} upstream"
    return None


def download(source, modified):
    """Into the cache, whole or not at all. Open Food Facts keeps a dated file per export."""
    name = source.cached.replace("*", f"-{modified:%Y%m%d}") if "*" in source.cached else source.cached
    target = CACHE / name
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    print(f"  downloading {source.url}")
    with urllib.request.urlopen(source.url, timeout=60) as response, partial.open("wb") as out:
        shutil.copyfileobj(response, out, 1 << 22)
    partial.replace(target)
    print(f"  saved {target}")


def update(fetch):
    """Says which sources have something newer, and with `fetch` downloads it. A new FoodData Central
    release is reported but not fetched: its URL here decides what's built, so moving it is a code change."""
    with urllib.request.urlopen(FDC_DOWNLOADS, timeout=30) as response:
        page = response.read().decode("utf-8", "replace")
    fresh = True
    for source in SOURCES.values():
        size, modified = remote_file(source)
        stale = is_stale(source, size)
        release = source.fdc_kind and newer_fdc_release(source, page)
        when = f"{modified:%Y-%m-%d}" if modified else "date unknown"
        print(f"{source.name}: {when}, {'newer: ' + stale if stale else 'up to date'}")
        if release:
            fresh = False
            print(f"  USDA has a {release} release: update its URL in food_catalog.py")
        if stale:
            fresh = False
            if fetch:
                download(source, modified or datetime.datetime.now(datetime.UTC))
    if not fresh and not fetch:
        print("Run with --download to fetch the newer files.")
    return 0


def source_path(key, given):
    """The file to build from, downloading it only if that's cheap: Open Food Facts takes asking."""
    if given:
        return given
    source = SOURCES[key]
    if cached := source.newest():
        return cached
    if source.megabytes > 1000:
        raise SystemExit(f"No {source.name} export in {CACHE}: run `update --download`, or pass it.")
    download(source, datetime.datetime.now(datetime.UTC))
    return source.newest()


def install(name, entry, folder, write_manifest):
    """Moves a checked catalog into place and records it, so the manifest always describes the file."""
    pending = folder / f"{name}.pending.db"
    pending.replace(folder / f"{name}.db")
    if write_manifest:
        manifest = json.loads(MANIFEST.read_text())
        manifest[MANIFEST_KEYS[name]] = entry
        if name != "supplements":
            manifest["schemaVersion"] = food_catalog.SCHEMA_VERSION
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"{name}.db: {entry['included']:,} entries, {entry['bytes']:,} bytes, {entry['version']}")


def kept_usda_peaks():
    """Without a usda rebuild, off.db's limits come from the bundled catalog, which must be the recorded one."""
    kept = USDA_FOLDER / "usda.db"
    if hashlib.sha256(kept.read_bytes()).hexdigest() != json.loads(MANIFEST.read_text())["usda"]["sha256"]:
        raise SystemExit(f"{kept} doesn't match its manifest entry; rebuild it too.")
    return food_catalog.catalog_peaks(kept)


def checked(path):
    if food_validation.validate_all([path]):
        raise SystemExit(f"{path} still has foods that can be repaired: left there, nothing installed.")


def build(args):
    check()
    names = args.catalogs or list(CATALOGS)
    if unknown := set(names) - set(CATALOGS):
        raise SystemExit(f"No catalog called {', '.join(sorted(unknown))}: there's {', '.join(CATALOGS)}.")

    def folder_of(name):
        return args.output or CATALOGS[name]

    usda_peaks = None
    if "usda" in names:
        sr, fndds = source_path("sr", args.usda), source_path("fndds", args.fndds)
        entry, usda_peaks = food_catalog.build("usda", sr, folder_of("usda"), fndds=fndds)
        checked(folder_of("usda") / "usda.pending.db")
        install("usda", entry, folder_of("usda"), not args.output)
    if "off" in names:
        limits = food_catalog.micro_limits(usda_peaks if usda_peaks is not None else kept_usda_peaks())
        entry, _ = food_catalog.build("off", source_path("off", args.off), folder_of("off"), limits)
        checked(folder_of("off") / "off.pending.db")
        install("off", entry, folder_of("off"), not args.output)
    if "supplements" in names:
        entry = supplement_catalog.build(source_path("dsld", args.dsld), folder_of("supplements"))
        install("supplements", entry, folder_of("supplements"), not args.output)
    if not args.output and {"off", "supplements"} & set(names):
        print("off.db and supplements.db aren't in git: publish with Scripts/publish-catalogs.sh, then commit.")
    return 0


def check():
    food_catalog.check()
    food_validation.check()
    return 0


def validate(args):
    food_validation.check()
    paths = args.catalogs or [path for path in (USDA_FOLDER / "usda.db", MACRO_FOLDER / "off.db") if path.exists()]
    if unrepaired := food_validation.validate_all(paths, args.tolerance, args.report):
        print(f"\n{unrepaired:,} packaged foods can still be repaired: rebuild off.db", file=sys.stderr)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check", help="Only the rules, on sample labels and foods.")
    fetch = commands.add_parser("update", help="Say which sources have something newer.")
    fetch.add_argument("--download", action="store_true", help="Download what's newer into the cache (Open Food Facts is 13 GB).")
    make = commands.add_parser("build", help="Build catalogs, check them and install them.")
    make.add_argument("catalogs", nargs="*", help="usda, off or supplements; all without any.")
    make.add_argument("--output", type=Path, help="Build here instead, leaving the app's catalogs and the manifest alone.")
    make.add_argument("--usda", type=Path, help="USDA SR Legacy JSON zip.")
    make.add_argument("--fndds", type=Path, help="USDA FNDDS (Survey Foods) JSON zip.")
    make.add_argument("--off", type=Path, help="Open Food Facts export (JSONL or CSV, gzipped or not).")
    make.add_argument("--dsld", type=Path, help="DSLD full-database CSV export (.zip).")
    report = commands.add_parser("validate", help="Check built catalogs' calories against their macros.")
    report.add_argument("catalogs", nargs="*", type=Path, help="usda.db and off.db without any.")
    report.add_argument("--tolerance", type=float, default=food_energy.TOLERANCE)
    report.add_argument("--report", type=Path, help="Write every food that doesn't agree to this CSV.")
    args = parser.parse_args()
    if args.command == "check":
        return check()
    if args.command == "update":
        return update(args.download)
    return build(args) if args.command == "build" else validate(args)


if __name__ == "__main__":
    raise SystemExit(main())
