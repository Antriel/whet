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

## The file is an input

Whet never writes the store file as a side effect of building or serving. It changes only on
`store.flushDb()` (`store.db.save()`), which rejects with `code: 'WHET_FILE_CONFLICT'` if the file
changed on disk since whet last read it (another whet process, an agent, `git checkout`, a hand
edit); `flushDb(true)` overwrites anyway.

External edits are picked up on the next request to the store: if the file changed and
`store.db.data` has no unsaved changes, it is reloaded and the entries re-synced. Unsaved changes are
kept instead (with a warning), and the next `flushDb()` reports the conflict. A file that fails to
parse or validate keeps failing requests until it's fixed. For push-style live reload, watch the file
and call `store.db.reload()`.

**Code that reads entries outside the router calls `await store.refresh()` first.** Routing
(`get`, `getHash`, serving) runs the check itself, but direct reads of `entryMap`, `dataMap` or
`getExpansion()` (e.g. a stone that builds a manifest from the entries) don't, and would otherwise see
whatever state the last routed request left behind.

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
producing one sub-entry per match. Each match gets a name: `each.nameTemplate` with `$1`… replaced
by the pattern's captures, else the first capture, else the file stem.

```jsonc
{ "id": "hurt", "type": "audio.asset",
  "each": { "dir": "assets/audio/hurt/", "pattern": "(.*)\\.wav$", "nameTemplate": "hurt_$1" },
  "config": { "source": "$file", "pipeline": [{ "id": "norm", "type": "loudnorm", "target": -16 }] },
  "overrides": { "hurt_3": { "pipeline": [{ "id": "norm", "target": -12 }] } } }
```

**Keys.** With a `nameTemplate`, the name *is* the sub-entry's key (`hurt_3`), so moving a file to
another group or renaming the group doesn't rename the asset. All keys share one namespace; two
entries producing the same key fail the sync. Without a template the key is `groupId/name`
(`hurt/3`), so bare file stems can't collide by accident.

**Overrides**, keyed by name (= the key when templated), merge over the base `config`:

- Objects merge recursively; strings, numbers and plain arrays replace.
- An array whose base items all carry a string `id` merges **by id**. Each override item merges into
  the base item with the same id, and any field may be overridden, `type` included. The base owns
  membership and order: an override can't add, drop or reorder items. To opt a file out of an item,
  use a flag the type understands (e.g. `enabled: false`). Override items with an unknown id or no
  id are warned about and ignored. Ids must be written in the file; StoneStore never generates them.

Then the tokens `$file` / `$name` are substituted throughout `config`, `$router` route arrays and
`mount`.

## Validation

Sync is all-or-nothing: structure and each type's `configSchema()` are checked up front. Any problem
aborts the sync with the current stones untouched, and every finding is reported in one error.
Schemas see expanded entries, so a group's base `config` is only checked through its files; a group
that matches no file isn't schema-checked at all.

## Editors: previewing unsaved entries

`store.previewEntry(key, flatEntry)` / `revertEntry(key)` apply a config to live stones without
saving. For an unsaved *raw* entry (as authored, `each` and `overrides` included), let the store do
the expansion instead of re-implementing the merge rules:

- `await store.expandRaw(rawEntry)` → the flat entries (`{ key, type, config, mount }`) a sync would
  build, with merged, token-substituted configs. Touches no stone.
- `await store.previewRaw(rawEntry, ?keys)` → same, then previews those entries (or only `keys`).
  Resolves with *all* expanded entries, for showing effective configs.

Both validate first (structure and schema), so a broken edit rejects before anything changes. A
group reuses the last sync's directory scan of its id; it rescans only if `each` itself was edited
or the group isn't synced yet.

## Builder `update` hooks

A `StoneRegistry.registerBuilder` builder may return an `update(key, revivedConfig, existing)` hook
that applies a changed config to the existing stones in place. If the hook can't (the change alters
which stones exist), it returns `false` without mutating anything, and the entry is recreated, as for
a type with no hook.
