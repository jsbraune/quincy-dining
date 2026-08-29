# quincy-dining

A personal dining-menu app for Quincy House, Harvard. Not affiliated with
Harvard University or HUDS. Single-user; not distributed.

## Layout

```
archiver/archive.py     snapshots the upstream API to data/ (stdlib only)
data/raw/menus/         one file per date, all locations, ~40KB each
data/raw/tables/        recipes / categories / locations lookups
data/meta/runs.jsonl    one line per archiver run
```

## Run

```
python3 archiver/archive.py
```

Idempotent and safe to run repeatedly. See CLAUDE.md for how the data
actually behaves -- there are several non-obvious traps.
