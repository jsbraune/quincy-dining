#!/usr/bin/env python3
"""
Quincy dining archiver.

Snapshots the CS50 Dining API to disk so that past menus survive.

Why this exists: the upstream feed publishes a ~13-day window (roughly
yesterday through +12 days) and keeps no history. Data older than about
24 hours is gone permanently. Everything this repo can ever say about
"what was served last Tuesday" comes from files this script wrote.

Design notes:
  * We archive the UNFILTERED menu feed (all locations), not just Quincy.
    It is 40KB/day either way, and while Quincy's kitchen is closed the
    student eats at Annenberg/Adams/Dunster. Filtering happens downstream.
  * Past dates are FROZEN. Once a date is behind us its file is never
    rewritten -- that file is the historical record.
  * Present/future dates are refetched every run, because HUDS edits
    menus in-week ("Menus Subject to Change").
  * Lookup tables (recipes/categories/locations) are content-hashed and
    only written when they actually change.

Stdlib only. Python 3.9 compatible.
"""

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta, timezone

API = "https://api.cs50.io/dining"
UA = "quincy-dining-archiver/0.1 (personal use; contact jason@reconstrategy.com)"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
MENUS_DIR = os.path.join(DATA, "raw", "menus")
TABLES_DIR = os.path.join(DATA, "raw", "tables")
META_DIR = os.path.join(DATA, "meta")

# How far back to re-check (cheap insurance against a missed run) and how
# far forward to probe. Forward probing stops early after STOP_AFTER_EMPTY
# consecutive empty days, so MAX_FWD is just a safety ceiling.
BACK_DAYS = 2
MAX_FWD = 21
STOP_AFTER_EMPTY = 3

TABLES = ("locations", "categories", "recipes")


def log(msg):
    print(msg, flush=True)


def fetch(path, tries=4):
    """GET a JSON endpoint with exponential backoff."""
    url = API + path
    delay = 1.5
    last = None
    for attempt in range(1, tries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError) as exc:
            last = exc
            if attempt < tries:
                time.sleep(delay)
                delay *= 2
    raise RuntimeError("fetch failed after %d tries: %s (%s)" % (tries, url, last))


def canonical(obj):
    """Stable bytes for hashing/writing, so unchanged data produces no diff."""
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


def archive_tables(now_iso, today):
    """Snapshot lookup tables to one stable file each.

    These tables are ~4200 rows and change rarely (a handful of new recipes
    at a time). Writing a fresh dated blob per change would put hundreds of
    near-identical megabytes into git history, so instead each table lives at
    a fixed path and is overwritten. Git already stores versioned deltas --
    `git log -- data/raw/tables/recipes.json` is the change history, and the
    output is sorted and line-oriented so those deltas stay small.
    """
    results = {}
    os.makedirs(TABLES_DIR, exist_ok=True)
    for name in TABLES:
        rows = fetch("/" + name)
        digest = sha(rows)
        path = os.path.join(TABLES_DIR, "%s.json" % name)

        previous = None
        if os.path.exists(path):
            try:
                with open(path) as fh:
                    previous = json.load(fh).get("sha256")
            except (ValueError, OSError):
                previous = None

        changed = previous != digest
        if changed:
            write_json(path, {"table": name, "fetchedAt": now_iso,
                              "sha256": digest, "rows": rows})
        results[name] = {"rows": len(rows), "changed": changed}
        log("  tables/%-11s %5d rows  %s" % (name, len(rows),
                                             "CHANGED" if changed else "unchanged"))
    return results


def archive_menus(now_iso, today):
    """Walk the publication window, writing one file per date."""
    written, frozen, skipped, empty_streak = [], [], [], 0

    for offset in range(-BACK_DAYS, MAX_FWD + 1):
        day = today + timedelta(days=offset)
        iso = day.isoformat()
        path = os.path.join(MENUS_DIR, "%s.json" % iso)
        is_past = day < today

        # Past dates are the historical record; never rewrite them.
        if is_past and os.path.exists(path):
            frozen.append(iso)
            continue

        rows = fetch("/menus?date=%s" % iso)

        if not rows:
            empty_streak += 1
            # A future date with no rows just isn't published yet -- not a
            # fact worth recording. A past/today empty IS a fact (closure).
            if day > today:
                skipped.append(iso)
                if empty_streak >= STOP_AFTER_EMPTY:
                    log("  menus: horizon ends at %s (%d empty days)" % (iso, empty_streak))
                    break
                continue
        else:
            empty_streak = 0

        quincy = sum(1 for r in rows if 8 in r.get("location", []))
        write_json(path, {
            "date": iso,
            "fetchedAt": now_iso,
            "source": "api.cs50.io/dining/menus",
            "rowCount": len(rows),
            "quincyRowCount": quincy,
            "rows": rows,
        })
        written.append(iso)
        log("  menus/%s  %4d rows (%3d Quincy)%s" % (iso, len(rows), quincy,
                                                     "  [frozen next run]" if day <= today else ""))

    return written, frozen, skipped


def main():
    now = datetime.now(timezone.utc).astimezone()
    now_iso = now.isoformat(timespec="seconds")
    today = now.date()

    log("quincy-dining archiver  |  run at %s" % now_iso)
    log("lookup tables:")
    tables = archive_tables(now_iso, today)
    log("menu window:")
    written, frozen, skipped = archive_menus(now_iso, today)

    os.makedirs(META_DIR, exist_ok=True)
    entry = {
        "ranAt": now_iso,
        "today": today.isoformat(),
        "menusWritten": written,
        "menusFrozen": frozen,
        "futureNotPublished": skipped,
        "tables": tables,
    }
    with open(os.path.join(META_DIR, "runs.jsonl"), "a") as fh:
        fh.write(json.dumps(entry, sort_keys=True) + "\n")

    log("done: %d written, %d frozen, %d not yet published"
        % (len(written), len(frozen), len(skipped)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - cron wants a clear nonzero exit
        log("ARCHIVER FAILED: %s" % exc)
        sys.exit(1)
