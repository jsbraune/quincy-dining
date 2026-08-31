#!/usr/bin/env python3
"""
FoodPro parser: per-dining-hall menus for Harvard undergraduate dining.

Why this exists: the CS50 API returns ONE common menu for every House, so it
cannot power a hall picker. FoodPro publishes a genuinely distinct menu per
kitchen. This reads FoodPro directly.

Recipe ids match CS50's, so nutrition/allergens still come from
`data/raw/tables/recipes.json` -- this module only answers "what is served
where", which is the part CS50 loses.

Stdlib only. Python 3.9 compatible.
"""

import html
import re
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://www.foodpro.huds.harvard.edu/foodpro"
UA = "quincy-dining-archiver/0.2 (personal use; +https://github.com/jsbraune/quincy-dining)"

# Verified against Harvard's own dining pages, then checked by fetching each
# one. Harvard's two menu pages disagree with each other in places; where they
# did, the value here is the one the live data supports.
#
#   Quincy is 08, not 17: only 08 and 30 publish a "Breakfast Meats" station
#   (a full hot breakfast), which is a documented Quincy/Annenberg trait.
#   Eliot is 80 -- its temporary dining hall during the 2025-27 renewal.
#   Dunster and Mather are 07, which currently publishes only bag meals.
LOCATIONS = {
    "adams":       ("Adams House",       "09"),
    "annenberg":   ("Annenberg Hall",    "30"),
    "cabot":       ("Cabot House",       "05"),
    "currier":     ("Currier House",     "38"),
    "dunster":     ("Dunster House",     "07"),
    "eliot":       ("Eliot House",       "80"),
    "kirkland":    ("Kirkland House",    "14"),
    "leverett":    ("Leverett House",    "16"),
    "lowell":      ("Lowell House",      "17"),
    "mather":      ("Mather House",      "07"),
    "pforzheimer": ("Pforzheimer House", "05"),
    "quincy":      ("Quincy House",      "08"),
    "winthrop":    ("Winthrop House",    "17"),
    "flyby":       ("FlyBy",             "29"),
    "bagmeals":    ("Bag Meals",         "07"),
}

# Diet markers are the SILENT .gif icons, not the .png files.
#
# The .png files are named vegan.png / veg.png / halal.png but never appear on
# an item -- they are legend art, and their alt text reads "Low/Medium/High
# Carbon Footprint". Keying off those filenames (or off any alt text) parses
# the legend and tags nothing. Verified: across 80 items, vgn.gif was vegan
# 50/50, veg.gif was vegetarian 66/66, with zero false positives against
# CS50's own flags.
DIET_ICONS = {"vgn.gif": "vegan", "veg.gif": "vegetarian", "hal.gif": "halal"}

_STATION = re.compile(r"class=['\"]longmenucolmenucat['\"][^>]*>(.*?)</div>", re.S | re.I)
_ITEM = re.compile(r"class=['\"]longmenucoldispname['\"]", re.I)
_RECIPE = re.compile(r"RecNumAndPort=(\d+)\*(\d+)")
_NAME = re.compile(r"<a\b[^>]*>(.*?)</a>", re.S | re.I)
_PORTION = re.compile(r"class=['\"]longmenucolportions['\"][^>]*>(.*?)</div>", re.S | re.I)
_ICON = re.compile(r"src=\"[^\"]*?([A-Za-z0-9_\-]+\.(?:gif|png))\"", re.I)


def _text(fragment):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", fragment))).strip()


def fetch(url, tries=4):
    delay = 1.5
    last = None
    for attempt in range(1, tries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=40) as resp:
                return resp.read().decode("utf-8", "ignore")
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            last = exc
            if attempt < tries:
                time.sleep(delay)
                delay *= 2
    raise RuntimeError("fetch failed after %d tries: %s (%s)" % (tries, url, last))


def day_url(location_num, date_mdy):
    return ("%s/shtmenu.aspx?sName=HARVARD+UNIVERSITY+DINING+SERVICES"
            "&locationNum=%s&locationName=Dining+Hall&naFlag=1"
            "&WeeksMenus=This+Week%%27s+Menus&myaction=read&dtdate=%s"
            % (BASE, location_num, urllib.parse.quote(date_mdy, safe="")))


def normalize_meal(label):
    """Map a hall's own meal label onto breakfast/lunch/dinner.

    Labels are wildly inconsistent between halls: 'Breakfast' / 'Breakfast Menu'
    / 'Breakfast Entrees', 'LUNCH' / 'Lunch Entrees, Starches & Veggies', and
    Lowell/Winthrop publish 'Dinnner' with three n's. Prefix matching absorbs
    all of it; exact names must never be hardcoded.
    """
    low = re.sub(r"[^a-z ]", "", label.lower()).strip()
    if low.startswith("break"):
        return "breakfast"
    if low.startswith("brunch"):
        return "brunch"
    if low.startswith("lunch"):
        return "lunch"
    if low.startswith("dinn"):
        return "dinner"
    return None


def discover_meals(location_num, date_mdy, page=None):
    """Meal periods a hall advertises for a date, as (meal, raw_label, url)."""
    page = page if page is not None else fetch(day_url(location_num, date_mdy))
    out, seen = [], set()
    for href in re.findall(r"href=['\"](longmenucopy\.aspx\?[^'\"]+)['\"]", page, re.I):
        href = html.unescape(href)
        params = urllib.parse.parse_qs(urllib.parse.urlparse(href).query)
        raw = (params.get("mealName") or [""])[0]
        # Harvard embeds literal <br> tags inside mealName. Passing those
        # through crashes their own server with an ASP.NET Runtime Error, so
        # strip markup before rebuilding the URL.
        label = _text(raw)
        if not label:
            continue
        meal = normalize_meal(label)
        key = (meal, label)
        if meal is None or key in seen:
            continue
        seen.add(key)
        url = ("%s/longmenucopy.aspx?sName=HARVARD+UNIVERSITY+DINING+SERVICES"
               "&locationNum=%s&locationName=Dining+Hall&naFlag=1"
               "&WeeksMenus=This+Week%%27s+Menus&dtdate=%s&mealName=%s"
               % (BASE, location_num, urllib.parse.quote(date_mdy, safe=""),
                  urllib.parse.quote_plus(label)))
        out.append((meal, label, url))
    return out


def parse_meal(page):
    """One longmenucopy page -> ordered stations, each with its items.

    Station order is the page's order, which mirrors how the hall lays the
    meal out. Never sort it.
    """
    marks = []
    for m in _STATION.finditer(page):
        name = _text(m.group(1)).strip("- ").strip()
        if name:
            marks.append((m.start(), "station", name))
    for m in _ITEM.finditer(page):
        marks.append((m.start(), "item", None))
    marks.sort(key=lambda x: x[0])

    stations, current = [], None
    for idx, (pos, kind, name) in enumerate(marks):
        if kind == "station":
            current = {"name": name, "items": []}
            stations.append(current)
            continue
        end = marks[idx + 1][0] if idx + 1 < len(marks) else min(len(page), pos + 2000)
        block = page[pos:end]

        rec = _RECIPE.search(block)
        nm = _NAME.search(block)
        if not rec or not nm:
            continue
        item_name = _text(nm.group(1))
        if not item_name:
            continue
        portion_m = _PORTION.search(block)
        portion = _text(portion_m.group(1)) if portion_m else ""
        tags = sorted({DIET_ICONS[i.lower()] for i in _ICON.findall(block)
                       if i.lower() in DIET_ICONS})
        if current is None:
            current = {"name": "Menu", "items": []}
            stations.append(current)
        current["items"].append({
            "recipeId": int(rec.group(1)),
            "portionCode": int(rec.group(2)),
            "name": item_name,
            "portion": portion,
            "tags": tags,
        })
    return [s for s in stations if s["items"]]


def fetch_day(location_num, date_mdy, pause=0.4):
    """All meals for one hall on one date."""
    page = fetch(day_url(location_num, date_mdy))
    meals = []
    for meal, label, url in discover_meals(location_num, date_mdy, page=page):
        time.sleep(pause)
        stations = parse_meal(fetch(url))
        if stations:
            meals.append({"meal": meal, "sourceLabel": label, "stations": stations})
    return meals



# ---------------------------------------------------------------------------
# Day view
#
# longmenucopy carries recipe ids, portions and diet icons, but it is only
# reachable when a hall's mealName round-trips. Several halls store names with
# literal <br> tags inside: sending them crashes FoodPro's server, stripping
# them stops the name matching, so those halls have no usable longmenucopy.
#
# The day view has no recipe ids at all, but it reaches every hall and holds
# all three meals in a single request. Item names match CS50's recipe table
# (~100% once page chrome is discarded), so nutrition and allergens are
# recovered by name instead of by id.
# ---------------------------------------------------------------------------

# Boilerplate that lives in the page furniture, not on the menu.
_CHROME = re.compile(
    r"accessibility|copyright|president and fellows|consumer responsibility|"
    r"report copyright|info practices|privacy|harvard university|dining services|"
    r"campus services|select a date|set filters|^back$|^select$|menus for",
    re.I)

_DAY_STATION = re.compile(r"^--\s*(.+?)\s*--$")


def parse_day_view(page):
    """shtmenu page -> [{meal, sourceLabel, stations:[{name, items:[{name}]}]}].

    Sections are split on the meal-period anchors in the HTML, not on rendered
    text. Several halls store meal names containing <br>, so the label renders
    across two lines and never matches as a string; the anchor position is
    unambiguous. Items carry names only -- join to the recipe table by name.
    """
    anchors = []
    for m in re.finditer(r"href=['\"](longmenucopy\.aspx\?[^'\"]+)['\"]", page, re.I):
        params = urllib.parse.parse_qs(urllib.parse.urlparse(html.unescape(m.group(1))).query)
        label = _text((params.get("mealName") or [""])[0])
        meal = normalize_meal(label) if label else None
        if meal:
            anchors.append((m.start(), meal, label))
    if not anchors:
        return _split_without_anchors(page)

    meals = []
    for i, (pos, meal, label) in enumerate(anchors):
        end = anchors[i + 1][0] if i + 1 < len(anchors) else len(page)
        segment = page[pos:end]
        stations = _stations_from_segment(segment)
        if stations:
            meals.append({"meal": meal, "sourceLabel": label, "stations": stations})
    return meals


def _split_without_anchors(page):
    """Fallback for halls that publish no meal-period links (e.g. Kirkland).

    The page still lists every station for the whole day, and stations repeat
    once per meal -- a second "Salad Bar" means lunch has started. Splitting on
    the first repeat recovers the meal boundaries.
    """
    stations = _stations_from_segment(page)
    if not stations:
        return []
    groups, current, seen = [], [], set()
    for st in stations:
        if st["name"] in seen:
            groups.append(current)
            current, seen = [], set()
        seen.add(st["name"])
        current.append(st)
    if current:
        groups.append(current)

    names = ["breakfast", "lunch", "dinner"]
    out = []
    for i, group in enumerate(groups[:3]):
        out.append({"meal": names[i] if i < len(names) else "meal%d" % i,
                    "sourceLabel": "", "stations": group})
    return out


def _stations_from_segment(segment):
    body = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", segment)
    lines = [l.strip() for l in html.unescape(re.sub(r"(?s)<[^>]+>", "\n", body)).split("\n")]
    stations, current = [], None
    for line in lines:
        if not line:
            continue
        m = _DAY_STATION.match(line)
        if m:
            name = m.group(1).strip()
            if re.search(r"aspx|Version|Logo|Header|Footer|MODIFY|Recipe Name|Select", name):
                current = None
            else:
                current = {"name": name, "items": []}
                stations.append(current)
            continue
        if current is None or not (2 < len(line) < 70):
            continue
        if not re.search(r"[A-Za-z]{3}", line) or _CHROME.search(line):
            continue
        current["items"].append({"name": line})
    return [s for s in stations if s["items"]]


def fetch_day_view(location_num, date_mdy):
    """Every meal for one hall on one date, in a single request."""
    return parse_day_view(fetch(day_url(location_num, date_mdy)))

if __name__ == "__main__":
    import sys
    slug = sys.argv[1] if len(sys.argv) > 1 else "quincy"
    date = sys.argv[2] if len(sys.argv) > 2 else "9/3/2026"
    name, num = LOCATIONS[slug]
    print("%s (locationNum=%s) on %s" % (name, num, date))
    for meal in fetch_day_view(num, date):
        n = sum(len(s["items"]) for s in meal["stations"])
        print("  %-9s %3d items in %2d stations   (label: %r)"
              % (meal["meal"], n, len(meal["stations"]), meal["sourceLabel"]))
        for s in meal["stations"][:3]:
            sample = ", ".join(i["name"] for i in s["items"][:3])
            print("      %-26s %s" % (s["name"][:26], sample[:60]))
