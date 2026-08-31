#!/usr/bin/env python3
"""
Archive every Harvard undergraduate dining hall from FoodPro.

Separate from archive.py, which snapshots the CS50 API for the Quincy app.
That pipeline and its data are untouched; this writes alongside it.

Archives by locationNum rather than by House, because several Houses share a
kitchen (Cabot/Pforzheimer 05, Dunster/Mather 07, Lowell/Winthrop 17). Ten
fetches cover thirteen halls. Houses are mapped back on at normalize time.

FoodPro publishes a rolling 7-day window and keeps no history, so a missed run
is permanent data loss -- same rule as the CS50 archive.

Stdlib only. Python 3.9 compatible.
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.parse
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import foodpro  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "raw", "halls")
META = os.path.join(ROOT, "data", "meta")

# Distinct kitchens. Several Houses map onto each; see foodpro.LOCATIONS.
LOCATION_NUMS = sorted({num for _, num in foodpro.LOCATIONS.values()})

PAUSE = 0.5  # between requests, to stay polite


def log(msg):
    print(msg, flush=True)


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha(obj):
    return hashlib.sha256(canonical(obj)).hexdigest()


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(json.dumps(obj, sort_keys=True, indent=1).encode("utf-8"))
        fh.write(b"\n")
    os.replace(tmp, path)


def discover_dates(location_num):
    """The window FoodPro itself advertises, rather than a guessed range."""
    page = foodpro.fetch(foodpro.day_url(location_num, ""))
    dates = []
    for value in re.findall(r"<option[^>]*value=['\"]([^'\"]*)['\"]", page, re.I):
        if "dtdate=" not in value:
            continue
        q = urllib.parse.parse_qs(urllib.parse.urlparse(value).query)
        d = (q.get("dtdate") or [""])[0]
        if d and d not in dates:
            dates.append(d)
    return dates


def iso(date_mdy):
    m, d, y = date_mdy.split("/")
    return "%04d-%02d-%02d" % (int(y), int(m), int(d))


def main():
    now = datetime.now(timezone.utc).astimezone()
    now_iso = now.isoformat(timespec="seconds")
    today = now.date().isoformat()

    log("hall archiver | %s" % now_iso)
    dates = discover_dates(LOCATION_NUMS[0])
    if not dates:
        log("FAILED: FoodPro advertised no dates")
        return 1
    log("window: %s .. %s (%d days)" % (iso(dates[0]), iso(dates[-1]), len(dates)))

    written, unchanged, frozen, empty = [], [], [], []
    for num in LOCATION_NUMS:
        for date_mdy in dates:
            day = iso(date_mdy)
            path = os.path.join(OUT, num, "%s.json" % day)

            # Past dates are the historical record; never rewrite them.
            if day < today and os.path.exists(path):
                frozen.append((num, day))
                continue

            time.sleep(PAUSE)
            try:
                meals = foodpro.fetch_day_view(num, date_mdy)
            except Exception as exc:  # noqa: BLE001
                log("  %s %s  FETCH FAILED: %s" % (num, day, exc))
                continue

            if not meals:
                empty.append((num, day))
                if day > today:
                    continue  # not published yet is not a fact worth recording

            digest = sha(meals)
            if os.path.exists(path):
                try:
                    with open(path) as fh:
                        if json.load(fh).get("mealsSha256") == digest:
                            unchanged.append((num, day))
                            continue
                except (ValueError, OSError):
                    pass

            items = sum(len(s["items"]) for m in meals for s in m["stations"])
            write_json(path, {
                "locationNum": num,
                "date": day,
                "fetchedAt": now_iso,
                "source": "foodpro.huds.harvard.edu/shtmenu.aspx",
                "mealsSha256": digest,
                "itemCount": items,
                "meals": meals,
            })
            written.append((num, day))
            log("  loc=%s %s  %3d items in %d meals" % (num, day, items, len(meals)))

    os.makedirs(META, exist_ok=True)
    with open(os.path.join(META, "hall_runs.jsonl"), "a") as fh:
        fh.write(json.dumps({
            "ranAt": now_iso,
            "window": [iso(dates[0]), iso(dates[-1])],
            "written": ["%s/%s" % (a, b) for a, b in written],
            "unchanged": len(unchanged),
            "frozen": len(frozen),
            "empty": ["%s/%s" % (a, b) for a, b in empty],
        }, sort_keys=True) + "\n")

    log("done: %d changed, %d unchanged, %d frozen, %d empty"
        % (len(written), len(unchanged), len(frozen), len(empty)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        log("HALL ARCHIVER FAILED: %s" % exc)
        sys.exit(1)
