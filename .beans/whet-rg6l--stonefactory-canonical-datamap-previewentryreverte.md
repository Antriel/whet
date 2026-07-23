---
# whet-rg6l
title: 'StoneFactory: canonical dataMap + previewEntry/revertEntry (generic live preview)'
status: todo
type: feature
priority: high
created_at: 2026-07-23T07:06:03Z
updated_at: 2026-07-23T07:06:03Z
parent: whet-1vzf
---

Generic ConfigStore-style preview/revert on the `StoneFactory` base class, per scry-app-y4be §A. Unblocks the audio-manager live-preview (scry-app repo waits on this) with **zero AudioDb changes**, and StoneStore (sibling bean) inherits it for free.

File: `src/whet/stones/StoneFactory.hx`. Design frozen — implement, don't re-decide. See epic whet-1vzf for build/test conventions.

## Design

State added to `StoneFactory<D, E>`:
- `dataMap:js.lib.Map<String, D>` — canonical (last-synced) data per key.
- `previewedKeys:js.lib.Set<String>` — keys whose live stones diverge from dataMap.

### `sync(data, keyFn)` changes (signature unchanged; still returns removed keys)

- For each item: before calling `updateEntry` on an existing key, call new protected hook `shouldUpdateEntry(key:String, newData:D):Bool`. Default implementation: `true` when `haxe.Json.stringify(cast newData) != haxe.Json.stringify(cast dataMap.get(key))` **OR** `previewedKeys.has(key)` (a sync must always reassert canonical over a preview). Subclasses may override (StoneStore adds a dependency cascade).
- After create/update (or skip), set `dataMap.set(key, item)`. Routes are still added for every key regardless of skip, exactly as today (`route(entry.routes)` — routes were cleared at the top of sync).
- Removed keys: also `dataMap.delete(key)` and `previewedKeys.delete(key)`.
- At the end: `previewedKeys.clear()`.
- Note: a spurious `true` from the JSON comparison (e.g. key-order difference) is harmless — it just runs `updateEntry` as every sync did before this change.

### New public methods (all `@:keep`, so DCE keeps them)

- `previewEntry(key:String, data:D):Void` — if `entryMap.has(key)`: `updateEntry(key, data, entryMap.get(key))`; else: `entryMap.set(key, createEntry(key, data))` and `route(entry.routes)` when routes non-null (previewing a not-yet-synced key must work — y4be "new/unsynced key" case). Never touches `dataMap`. Adds key to `previewedKeys`. No regeneration is triggered here — whet's hash cache regenerates affected sub-stones lazily on next `getSource()` because their configs (and thus hashes) changed.
- `revertEntry(key:String):Bool` — if `dataMap.has(key)`: `updateEntry(key, dataMap.get(key), entryMap.get(key))`, `previewedKeys.delete(key)`, return true. Else if `entryMap.has(key)` (preview-created, no canonical): `removeEntry(key)`, then `rebuildRoutes()`, return true. Else return false.
- `revertAllPreviews():Void` — revertEntry for each key in previewedKeys (copy the set first — revertEntry mutates it).
- `isPreviewDirty(?key:String):Bool` — with key: membership in previewedKeys; without: `previewedKeys.size > 0`.
- `rebuildRoutes():Void` — `clearRoutes()`; `addBaseRoutes()`; for each entry in `entryMap` insertion order, `route(entry.routes)` when non-null. Used by the revert-removal path (leave `sync()`'s inline route building as-is; iteration order differs and sync's contract is already covered).

## Compatibility

- AudioDb (`gooye-2/scry/whetstones/assets/AudioDb.mjs`) overrides only `createEntry`/`updateEntry`/`addBaseRoutes` — none change signature. Its `syncStones()` → `sync(flat, e => e.name)` populates dataMap automatically; the scry-side plugin then calls `factory.previewEntry(name, mergedEntryData)` / `revertEntry(name)` directly.
- The skip-unchanged default is a mild behavior change (updateEntry no longer runs for JSON-identical data). For AudioDb this is safe (its updateEntry only reassigns identical configs) and is actually the fix for y4be friction #1 (whole-DB set churning every entry).

## Todos

- [ ] Implement dataMap/previewedKeys + sync changes + shouldUpdateEntry hook
- [ ] Implement previewEntry/revertEntry/revertAllPreviews/isPreviewDirty/rebuildRoutes
- [ ] Tests in `test/stone-factory-preview.test.mjs` (JS subclass of StoneFactory wrapping MockStone; track createEntry/updateEntry call counts):
  - preview changes a sub-stone's served output (getSource reflects new config); revert restores canonical output
  - preview of unknown key creates entry + routes; revert removes it and its routes
  - sync() after preview reasserts canonical even when incoming data JSON-equals dataMap (previewedKeys forces update)
  - skip-unchanged: updateEntry NOT called for JSON-equal non-previewed key; called when data changed
  - removed keys are dropped from dataMap/previewedKeys; sync return value unchanged
- [ ] Rebuild (`haxe build.hxml`) + full test run green
