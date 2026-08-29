#!/usr/bin/env python3
"""
Build client-ready JSON from the raw archive.

Reads data/raw/ (written by archive.py) and emits data/normalized/:

    quincy/YYYY-MM-DD.json   one day: meals -> stations -> items
    recipes.json             full detail (ingredients, all macros) by id
    index.json               which dates exist, and a little provenance

The split matters. Recipe detail is ~5MB and barely changes, so a client
fetches it once and caches hard; day files are small and churn daily.

Pure local work -- no network. Stdlib only, Python 3.9 compatible.
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "raw")
OUT = os.path.join(ROOT, "data", "normalized")

MEALS = {0: "breakfast", 1: "lunch", 2: "dinner"}

# CS50 exposes vegan/vegetarian as recipe booleans but has no halal flag.
# Halal is encoded as a *station* instead (ids 17 "Halal" and 38 "HALAL"),
# so we recover it from category membership rather than the recipe record.
HALAL_STATIONS = {"halal"}

# Derived slugs are fine ("Quincy House" -> quincy-house) but the schema this
# project settled on calls the location plain "quincy".
SLUG_OVERRIDES = {8: "quincy"}

# {amount: "34.9g", percent: 68.0} -> (34.9, "g"). Roughly 8% of recipes
# have null nutrition entirely, so every field here is best-effort.
AMOUNT_RE = re.compile(r"^\s*([0-9]*\.?[0-9]+)\s*([a-zA-Z]*)\s*$")

NUTRIENTS = (
    ("total_fat", "g"), ("sat_fat", "g"), ("trans_fat", "g"),
    ("cholesterol", "mg"), ("sodium", "mg"), ("total_carb", "g"),
    ("dietary_fiber", "g"), ("sugars", "g"), ("protein", "g"),
)


def load(path):
    with open(path) as fh:
        return json.load(fh)


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(json.dumps(obj, sort_keys=True, indent=1).encode("utf-8"))
        fh.write(b"\n")
    os.replace(tmp, path)


def amount(field):
    """Pull a number out of {'amount': '34.9g'}. Returns None if absent."""
    if not isinstance(field, dict):
        return None
    m = AMOUNT_RE.match(field.get("amount") or "")
    return float(m.group(1)) if m else None


def nutrition(recipe):
    out = {}
    if recipe.get("calories") is not None:
        out["calories"] = recipe["calories"]
    for key, unit in NUTRIENTS:
        val = amount(recipe.get(key))
        if val is not None:
            out["%s_%s" % (key, unit)] = val
    return out


def tags_for(recipe, is_halal):
    tags = []
    if recipe.get("vegan"):
        tags.append("vegan")
    if recipe.get("vegetarian"):
        tags.append("vegetarian")
    if is_halal:
        tags.append("halal")
    return tags


def normalize_day(raw, location_id, location_slug, cats, recs):
    """One raw menu file -> one normalized day."""
    rows = [r for r in raw["rows"] if location_id in r.get("location", [])]

    # Group by meal, preserving the feed's station order. It is NOT sorted by
    # category id -- the sequence mirrors how FoodPro lays the meal out
    # (Soup, Salad Bar, Entrees, ...), which is the order a human expects.
    meals = {}
    for row in rows:
        meals.setdefault(row["meal"], []).append(row)

    out_meals = []
    for meal_id in sorted(meals):
        meal_rows = meals[meal_id]

        halal_recipes = {
            r["recipe"] for r in meal_rows
            if (cats.get(r["category"], "")).strip().lower() in HALAL_STATIONS
        }

        stations, order = {}, []
        for row in meal_rows:
            cat = row["category"]
            if cat not in stations:
                stations[cat] = []
                order.append(cat)
            recipe = recs.get(row["recipe"])
            if recipe is None:
                continue  # recipe table lags the menu feed; skip rather than fabricate
            # Day files carry exactly what a list row and the filters need.
            # Full macros and ingredients live in recipes.json, loaded once
            # for the detail view. Inlining them here cost 2.3x the bytes.
            item = {
                "recipeId": row["recipe"],
                "name": recipe["name"],
                "portion": recipe.get("serving_size") or "",
                "tags": tags_for(recipe, row["recipe"] in halal_recipes),
                "allergens": recipe.get("allergens") or [],
            }
            if recipe.get("calories") is not None:
                item["calories"] = recipe["calories"]
            stations[cat].append(item)

        out_meals.append({
            "meal": MEALS.get(meal_id, "meal%d" % meal_id),
            "stations": [
                {"name": cats.get(c, "Station %d" % c), "categoryId": c, "items": stations[c]}
                for c in order if stations[c]
            ],
        })

    return {
        "location": location_slug,
        "locationId": location_id,
        "date": raw["date"],
        "fetchedAt": raw["fetchedAt"],
        "itemCount": sum(len(s["items"]) for m in out_meals for s in m["stations"]),
        "meals": out_meals,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--location", type=int, default=8, help="CS50 location id (Quincy=8)")
    ap.add_argument("--slug", default=None, help="output folder name; defaults from the id")
    args = ap.parse_args()

    locs = {l["id"]: l["name"] for l in load(os.path.join(RAW, "tables", "locations.json"))["rows"]}
    cats = {c["id"]: c["name"] for c in load(os.path.join(RAW, "tables", "categories.json"))["rows"]}
    recs = {r["id"]: r for r in load(os.path.join(RAW, "tables", "recipes.json"))["rows"]}

    if args.location not in locs:
        print("unknown location id %d; known: %s" % (args.location, sorted(locs)))
        return 1
    slug = (args.slug or SLUG_OVERRIDES.get(args.location)
            or re.sub(r"[^a-z0-9]+", "-", locs[args.location].lower()).strip("-"))

    menu_dir = os.path.join(RAW, "menus")
    days, empty, used = [], [], set()
    for fname in sorted(os.listdir(menu_dir)):
        if not fname.endswith(".json"):
            continue
        day = normalize_day(load(os.path.join(menu_dir, fname)), args.location, slug, cats, recs)
        write_json(os.path.join(OUT, slug, "%s.json" % day["date"]), day)
        for m in day["meals"]:
            for st in m["stations"]:
                for it in st["items"]:
                    used.add(it["recipeId"])
        (days if day["itemCount"] else empty).append(day["date"])
        print("  %s  %4d items  %s" % (
            day["date"], day["itemCount"],
            ", ".join("%s:%d" % (m["meal"], sum(len(s["items"]) for s in m["stations"]))
                      for m in day["meals"]) or "(closed)"))

    # Recipe detail for the detail view. Only recipes that actually appear on
    # an archived menu: 411 of 4170 in the first window, so shipping the whole
    # table would be a 10x waste (3.7MB vs 290KB).
    write_json(os.path.join(OUT, "recipes.json"), {
        "generatedAt": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "recipes": {str(rid): {
            "name": recs[rid]["name"],
            "portion": recs[rid].get("serving_size") or "",
            "allergens": recs[rid].get("allergens") or [],
            "ingredients": recs[rid].get("ingredients"),
            "nutrition": nutrition(recs[rid]),
            "vegan": bool(recs[rid].get("vegan")),
            "vegetarian": bool(recs[rid].get("vegetarian")),
            "note": recs[rid].get("information"),
        } for rid in sorted(used)},
    })

    write_json(os.path.join(OUT, "index.json"), {
        "generatedAt": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "location": slug,
        "locationId": args.location,
        "servingDates": days,
        "closedDates": empty,
        "recipeCount": len(used),
    })

    print("\n%d serving days, %d closed/empty days, %d recipes in use (of %d known)"
          % (len(days), len(empty), len(used), len(recs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
