# quincy-dining

Personal dining app for Quincy House, Harvard. One user (a Quincy resident).
Not distributed, not affiliated with Harvard/HUDS, no Harvard marks.

## Stack

- Archiver: Python 3.9 (macOS system python), **stdlib only**. No Node on this
  machine. Avoid 3.10+ syntax (no `match`, no `X | Y` unions).
- Client: not chosen yet. PWA vs Expo/React Native is deliberately deferred --
  the archive and normalized schema are identical either way.

## Data source

`https://api.cs50.io/dining` -- public, no key, no auth. Endpoints:
`/locations`, `/categories`, `/recipes`, `/menus`.

Quincy is **location id 8**. Houses share kitchen ids (Cabot+Pfoho 5,
Dunster+Mather 7, Eliot+Kirkland 14, Lowell+Winthrop 15); Quincy has its own.

A menu row is a join record: `{date, meal, category, recipe, location[]}`.
`meal` is 0=breakfast, 1=lunch, 2=dinner. `category` -> station name.
`recipe` -> name, nutrition, allergens, ingredients, vegan/vegetarian.

## Traps (all verified 2026-08-28)

1. **`/recipes` silently ignores every query parameter.** `?id=`, `?recipe=`,
   `?recipe_id=` all return the identical full 4,170-row table. It does not
   error -- naive code "works" and mislabels every item with row 0. Treat it
   as a lookup table: fetch once, index by id locally. Same for `/categories`.

2. **`/menus?location=8` DOES filter correctly.** Verified exact against
   manual filtering of the unfiltered feed. Trustworthy.

3. **No history upstream.** The window is roughly yesterday through +13 days.
   Anything older is gone permanently. The archive in `data/` is the only
   record that will ever exist. Do not skip runs.

4. **Menus are edited in-week.** Future-dated files must be refetched; past
   dates are frozen on first write. Always surface an "as of" timestamp from
   `fetchedAt` rather than implying live truth.

5. **A closed hall returns an empty list, not an error.** Quincy's own kitchen
   opens **2026-09-02**; before that Quincy appears only in a shared
   all-houses breakfast set. An empty screen in late August is correct, not a
   bug.

6. **CS50 lacks `halal` and micronutrients** (iron, potassium, vit D). Only
   `vegan`/`vegetarian` booleans are exposed. FoodPro
   (`www.foodpro.huds.harvard.edu` -- note the `www.`, the bare host does not
   resolve) has them, but no scraper is built and none is planned.

## Archiver design

- Archives the **unfiltered** feed (all locations), not just Quincy. Same cost,
  and while Quincy is closed the student eats at Annenberg/Adams/Dunster.
- Past dates frozen; present/future refetched each run.
- Lookup tables live at stable paths and are overwritten. Git history is the
  version archive -- do not reintroduce dated table snapshots (5MB each).

## Allergen liability

If allergen filtering ships: HUDS does not guarantee allergens are labeled,
formulations change without notice, and cross-contact occurs. Results must
read "no declared allergen", never "safe", with a non-dismissable disclaimer.
