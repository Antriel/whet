---
# whet-31lx
title: 'StoneStore: JSON-entry-driven stone graphs over StoneFactory'
status: todo
type: feature
priority: normal
created_at: 2026-07-23T07:07:21Z
updated_at: 2026-07-23T07:08:28Z
parent: whet-1vzf
blocked_by:
    - whet-hnde
    - whet-np9d
    - whet-rg6l
---

The StoneStore itself: a `StoneFactory` whose entries are generic JSON stone declarations, per `docs/ecosystem-review-2026-07/03-data-driven-stones.md` with the frozen deltas from epic whet-1vzf. Preview/revert arrives free from the StoneFactory preview bean (whet-rg6l) — write an end-to-end test for it here.

File: `src/whet/stones/StoneStore.hx`, exposed. Uses StoneRegistry + ConfigReviver (whet-hnde) and JsonDb (whet-np9d).

## File format (JsonDb-backed array, e.g. `assets/stone-store.json`)

```jsonc
[
  {
    "id": "sharpstone-ui",       // required; unique; becomes the created stone's id (or id prefix once `each` lands)
    "type": "SharpStone",        // required; a StoneRegistry type name
    "disabled": false,            // optional; entry fully ignored when true (stones removed as if deleted)
    "config": {                   // JSON config; $stone/$router refs revived; passed to the type's builder
      "pngs": { "$router": [["/", "assets/ui/", "**/*.png"]] }
    },
    "mount": "ui/"               // optional; see Mounts. NO "$self" — the entry's mainStone is implicit.
    // "each"/"overrides" are reserved for the expansion bean — expandEntries() below is identity for now
  }
]
```

## Class spec

`class StoneStore extends StoneFactory<FlatEntryData, StoreEntry>` where `FlatEntryData = {key, type, config, mount}` (plain JSON) and `StoreEntry` = the registry's `BuiltEntry` (FactoryEntry + ?mainStone + ?update).

- `public var db:JsonDb` — created in initConfig (id from `config.dbId ?? 'stone-store.json'`).
- `load(path:String):Promise<StoneStore>` (`@:keep`) — `db.load(path)` then `syncEntries()`, resolve this.
- `flushDb():Promise` (`@:keep`) — `db.flush()`.
- `addBaseRoutes()` override: `route([[db.id, db]])` (mirrors AudioDb).
- `syncEntries():Promise<Array<String>>` (`@:keep`, async, returns removed keys):
  1. **Validate** `db.data`: is an array; every entry has non-empty string `id`, ids unique (error lists duplicates); `type` is a registered name (error names the type AND the registered names from `StoneRegistry.list()`); `mount` present only when meaningful (see Mounts). Collect ALL problems and throw one `js.lib.Error` joining them — sync is all-or-nothing; current stones stay untouched on validation failure.
  2. Drop `disabled` entries.
  3. `expandEntries(entries):Promise<Array<FlatEntryData>>` — protected; v1 maps 1:1 to `{key: entry.id, type, config, mount}`. (The `each` bean replaces this.)
  4. **Topo-sort** flat entries: edges = `ConfigReviver.collectStoneRefs(e.config)` intersected with store keys. Cycle → error printing the cycle path (`a -> b -> a`). Refs that aren't store keys are left to revive-time resolution (script/project stones).
  5. `sync(sortedFlat, e -> e.key)`.

### createEntry(key, data)

- `resolve = id -> entryMap.get(id)?.mainStone ?? project.getStone(id) ?? throw` (error names the referring entry and the missing id; also throw when the target entry exists but has no mainStone).
- `revived = ConfigReviver.revive(data.config, resolve)`; `entry = StoneRegistry.get(data.type).builder(key, revived)`.
- Mount routes (below) are appended to `entry.routes`. Warn on ConfigStore overlap (below). Return entry.

### updateEntry(key, data, existing) — id-stable recreate by default

- If the registry type provided `existing.update`: call `existing.update(key, revived, existing)` (in-place path, e.g. future AudioDb).
- Else: `removeEntry(key)` then `entryMap.set(key, createEntry(key, data))`. Same ids + same config → same cache keys, so recreate is cache-neutral. Remove BEFORE create (Stone ctor warns on duplicate explicit ids).

### shouldUpdateEntry override — the reference-consistency cascade (REQUIRED)

Track `touchedKeys:Set<String>` per sync pass (cleared at start; add every key that went through createEntry/updateEntry). Return `super.shouldUpdateEntry(...) || collectStoneRefs(data.config).some(id => touchedKeys.has(id))`. Topo order guarantees dependencies are processed first, so this is a single forward pass. Without it, an unchanged entry keeps a dead instance of a recreated dependency.

### previewEntry override — preview cascade

`previewEntry(key, data)`: call super, then re-update dependents transitively: every synced entry whose `collectStoneRefs(dataMap-entry.config)` (transitively) reaches `key` gets `updateEntry(k, dataMap.get(k), entryMap.get(k))` in topo order — they must re-revive to capture the recreated instance. (Dependents are NOT added to previewedKeys — their canonical data is unchanged.) Same cascade applies inside `revertEntry` via the same helper.

### Mounts

`mount: string | Array<[routeUnder, filter?, extractDirs?]>` → factory routes `[routeUnder, mainStone, filter?, extractDirs?]` appended to entry.routes (string form = single dir/file mount, no filter). Validation error when the entry's type builder returns no `mainStone` (composite types route via builder-returned routes instead).

### ConfigStore interplay (doc 03 rule)

In createEntry, for each created stone: if `(project.configStore)?.getEntryById(stone.id) != null` → `Log.warn('StoneStore-defined stone also has a ConfigStore patch — two sources of truth; edit the store entry instead.', {id})`.

### Cache cleanup (doc 01 §4)

Config flag `?clearCacheOnRemove:Bool` (default false). When true, capture each removed entry's stone list before removal and call `project.cache.clearStone(stone)` for each (verify exact CacheManager method name in `src/whet/cache/CacheManager.hx`).

## Script usage (document in class header doc-comment)

```js
const store = await new StoneStore({ id: 'assets-store' }).load('assets/stone-store.json');
bundle.route([['/', store]]); // single mount point; store IS a Router
```
Script must reference the store (or entry outputs via routes), never capture inner store-created stone instances — recreate-on-sync invalidates captured instances by design.

## Todos

- [ ] Implement StoneStore per spec (validation, expansion hook, topo sort, create/update, cascade, mounts, warnings, cache flag)
- [ ] Tests `test/stone-store.test.mjs` (register MockStone as a type; createTestProject):
  - two entries, B's `$router` config references A via `{"$stone": "a"}` → B's output flows from A's
  - edit db.data for A only + syncEntries → A updated AND B force-updated (cascade); untouched entry C's updateEntry skipped
  - entry referencing a script-defined project stone resolves
  - disabled entry's stones are removed; re-enabling recreates them
  - duplicate id / unknown type / cycle / mount-without-mainStone each produce the specified aggregated error, and stones stay untouched
  - mount string + array forms serve outputs under prefixes; db.json served via base route
  - previewEntry on A → B serves preview-derived output (cascade); revertEntry restores; flushDb persists only canonical data
  - ConfigStore-overlap warning fires
- [ ] Rebuild + full test run green
