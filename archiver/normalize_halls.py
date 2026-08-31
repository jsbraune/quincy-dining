#!/usr/bin/env python3
"""
Build client-ready JSON for the all-halls app from data/raw/halls/.

Separate from normalize.py, which serves the Quincy app. That output is not
touched.

    data/normalized/halls/<hall>/<date>.json   one hall, one day
    data/normalized/halls/recipes.json         detail for recipes in use
    data/normalized/halls/index.json           halls, dates, provenance

The day view carries item names but no recipe ids, so nutrition and allergens
are joined from the CS50 recipe table by name. Names come from the same HUDS
system and match ~100% once page chrome is discarded; anything that fails to
match still appears on the menu, just without nutrition.

Pure local work, no network. Stdlib only, Python 3.9 compatible.
"""

import json
import os
import re
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import foodpro  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_HALLS = os.path.join(ROOT, "data", "raw", "halls")
RECIPES = os.path.join(ROOT, "data", "raw", "tables", "recipes.json")
OUT = os.path.join(ROOT, "data", "normalized", "halls")

NUTRIENTS = (("total_fat", "g"), ("sat_fat", "g"), ("trans_fat", "g"),
             ("cholesterol", "mg"), ("sodium", "mg"), ("total_carb", "g"),
             ("dietary_fiber", "g"), ("sugars", "g"), ("protein", "g"))
AMOUNT = re.compile(r"^\s*([0-9]*\.?[0-9]+)")

# The day view has no diet icons, so halal is recovered from station names --
# the same approach the Quincy app uses, and the only signal available here.
HALAL_STATION = re.compile(r"^\s*halal\s*$", re.I)


def norm_name(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def amount(field):
    if not isinstance(field, dict):
        return None
    m = AMOUNT.match(field.get("amount") or "")
    return float(m.group(1)) if m else None


def nutrition(recipe):
    out = {}
    if recipe.get("calories") is not None:
        out["calories"] = recipe["calories"]
    for key, unit in NUTRIENTS:
        v = amount(recipe.get(key))
        if v is not None:
            out["%s_%s" % (key, unit)] = v
    return out


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(json.dumps(obj, sort_keys=True, indent=1).encode("utf-8"))
        fh.write(b"\n")
    os.replace(tmp, path)


def main():
    recs = json.load(open(RECIPES))["rows"]
    by_name = {}
    for r in recs:
        by_name.setdefault(norm_name(r["name"]), r)

    generated = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    halls, used, matched, total = [], set(), 0, 0

    for slug, (display, num) in sorted(foodpro.LOCATIONS.items()):
        src = os.path.join(RAW_HALLS, num)
        if not os.path.isdir(src):
            continue
        serving, closed = [], []
        for fname in sorted(os.listdir(src)):
            if not fname.endswith(".json"):
                continue
            raw = json.load(open(os.path.join(src, fname)))
            out_meals = []
            for meal in raw["meals"]:
                stations = []
                for st in meal["stations"]:
                    is_halal = bool(HALAL_STATION.match(st["name"]))
                    items = []
                    for it in st["items"]:
                        total += 1
                        r = by_name.get(norm_name(it["name"]))
                        item = {"name": it["name"]}
                        if r:
                            matched += 1
                            used.add(r["id"])
                            item["recipeId"] = r["id"]
                            item["portion"] = r.get("serving_size") or ""
                            item["allergens"] = r.get("allergens") or []
                            if r.get("calories") is not None:
                                item["calories"] = r["calories"]
                            tags = []
                            if r.get("vegan"):
                                tags.append("vegan")
                            if r.get("vegetarian"):
                                tags.append("vegetarian")
                            if is_halal:
                                tags.append("halal")
                            item["tags"] = tags
                        else:
                            item["allergens"] = []
                            item["tags"] = ["halal"] if is_halal else []
                        items.append(item)
                    if items:
                        stations.append({"name": st["name"], "items": items})
                if stations:
                    out_meals.append({"meal": meal["meal"], "stations": stations})

            count = sum(len(s["items"]) for m in out_meals for s in m["stations"])
            day = {
                "hall": slug,
                "hallName": display,
                "locationNum": num,
                "date": raw["date"],
                "fetchedAt": raw["fetchedAt"],
                "itemCount": count,
                "meals": out_meals,
            }
            write_json(os.path.join(OUT, slug, "%s.json" % raw["date"]), day)
            (serving if count else closed).append(raw["date"])

        halls.append({"hall": slug, "name": display, "locationNum": num,
                      "servingDates": serving, "closedDates": closed})
        print("  %-12s loc=%s  %2d serving, %d closed" % (slug, num, len(serving), len(closed)))

    write_json(os.path.join(OUT, "recipes.json"), {
        "generatedAt": generated,
        "recipes": {str(r["id"]): {
            "name": r["name"],
            "portion": r.get("serving_size") or "",
            "allergens": r.get("allergens") or [],
            "ingredients": r.get("ingredients"),
            "nutrition": nutrition(r),
            "vegan": bool(r.get("vegan")),
            "vegetarian": bool(r.get("vegetarian")),
            "note": r.get("information"),
        } for r in recs if r["id"] in used},
    })
    write_json(os.path.join(OUT, "index.json"), {
        "generatedAt": generated,
        "halls": halls,
        "recipeCount": len(used),
    })

    rate = (matched / total * 100) if total else 0
    print("\n  %d halls, %d items, %.1f%% joined to a recipe, %d recipes in use"
          % (len(halls), total, rate, len(used)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
