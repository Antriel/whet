# StoneStore

A `StoneStore` is a `StoneFactory` whose entries are JSON stone declarations, backed by a `JsonDb`
file (default `stone-store.json`). One JSON file describes a whole data-driven stone graph.

Discover what's editable with `whet stone-schema` (lists registered types) and
`whet stone-schema <type>` (prints that type's `configSchema()` JSON).

## Mounting from a Project file

```js
const store = await new StoneStore({ id: 'assets-store' }).load('assets/stone-store.json');
bundle.route([['/', store]]); // the store IS a Router
```

**Reference the store, never its inner stones.** Recreate-on-sync invalidates captured instances by
design. Consume entry outputs through routes, or via a `$stone` ref from another entry.

Pass `clearCacheOnRemove: true` to clear the cache of stones from removed entries; otherwise they age
out via the cache durability rules.

## Entry format

The file is a JSON array of entries:

- `id` (required) — stable; becomes the entry key and the stone id.
- `type` (required) — a `StoneRegistry` type name.
- `config` — the stone config as plain JSON, with `$stone` / `$router` sentinels revived (below).
- `mount` — routes the entry's main stone into the store's Router: a dir string (`"ui/"`) or an array
  of `[routeUnder, filter?, extractDirs?]`. There is no `"$self"`; the main stone is the implicit
  target. A `mount` on a type without a main stone is an error.
- `disabled: true` — the entry is skipped entirely (the "commented-out stone").
- `each` + `overrides` — directory-scan expansion (below).

## References

Inside `config`:

- `{ "$stone": "<id>" }` → the live stone with that id. Sibling entries' main stones are checked
  first, then `project.getStone(id)`, so entry order doesn't matter.
- `{ "$router": <routes> }` → `new Router(<routes>)`, with nested `$stone` refs revived. Plain strings
  in routes stay strings (a string is already a `Files` shortcut).

A sentinel object must have exactly that one key. A `$stone` reference cycle is an error.

## `each` expansion

An entry with `each` is a group. `each.dir` is scanned for files matching the `each.pattern` regex,
producing one sub-entry per match keyed `groupId/name` (name from `each.nameTemplate`). `overrides`,
keyed by derived name, are deep-merged over the base `config`. The tokens `$file` / `$name` are
substituted throughout `config`, `$router` route arrays and `mount`.

## Validation

Sync is all-or-nothing: structure and each type's `configSchema()` are checked up front. Any problem
aborts the sync with the current stones untouched, and every finding is reported in one error.
