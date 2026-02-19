---
# whet-a2d8
title: Config read/update entry points (preview + persisted modes)
status: completed
type: task
priority: normal
created_at: 2026-02-17T08:33:11Z
updated_at: 2026-02-18T15:02:45Z
parent: whet-juli
blocked_by:
    - whet-pepc
---

Define Project-level config read/update entry points for Stone Inspector and external tooling.

## Final Decisions

1. API placement: on `Project`.
2. Not-found behavior: `getStoneConfig` returns `null`; `setStoneConfig` returns `false`.
3. Patch semantics for this phase: replace, not merge.
4. Preview mode is not request-scoped. It updates ConfigStore in-memory state only and does not flush.
5. Persist mode updates ConfigStore in-memory state and flushes to disk.
6. Config response should include editable config and metadata, with runtime objects excluded from editable payload.

## API Shape

Add methods to `src/whet/Project.hx`:

```haxe
public function getStoneConfig(id:String):Promise<Null<StoneConfigView>>;
public function setStoneConfig(id:String, patch:Dynamic, mode:ConfigPatchMode):Promise<Bool>;
public function clearStoneConfigPreview(id:String):Promise<Bool>;
```

Types:

```haxe
enum abstract ConfigPatchMode(String) {
    var Preview = "preview";
    var Persist = "persist";
}

typedef StoneConfigView = {
    var id:String;
    var editable:Dynamic;
    var meta:StoneConfigMeta;
}

typedef StoneConfigMeta = {
    var className:String;
    var cacheStrategy:CacheStrategy;
    var dependencyIds:Array<String>;
    var hasStoneConfigStore:Bool;
    var hasProjectConfigStore:Bool;
    var ?uiHints:Dynamic;
}
```

Notes:
- `editable` contains only patchable JSON-compatible fields.
- `meta` is read-only informational data for UI display and future rendering hints.
- `uiHints` can be supplied later by optional stone metadata methods; this bean only defines carrier shape.

## Behavior

Effective editable config seen by tools is based on Stone runtime state after ConfigStore application:

`base (Project.mjs) <- persisted entry <- in-memory current entry`

Mode behavior:
- `preview`: replace the stone's ConfigStore entry in memory only; no file flush.
- `persist`: replace the stone's ConfigStore entry in memory, then flush store file.

If no ConfigStore exists for the stone (stone-level or project-level), return `false` for set/clear and `null` for get.

## Implementation Plan

1. Add lightweight patchability helper in core
- Reuse ConfigStore's JSON-serializable field filtering rules to produce `editable`.
- Exclude structural/runtime fields (`project`, `dependencies`, `configStore`, Routers, Stone instances, functions).

2. Extend ConfigStore with persistedData tracking and entry operations
- Add `persistedData` snapshot: deep clone of `data` updated only on file read and file write. This enables per-stone clear without affecting other stones' preview state.
- `getEntry(stoneId:String):Dynamic` public accessor to current in-memory data entry.
- `setEntry(stoneId:String, patch:Dynamic):Void` updates `data` in memory only. Does NOT call applyPatch — the next `ensureApplied` (triggered lazily by getSource/getHash) detects the mismatch vs `appliedPatches` and reapplies automatically.
- `clearEntry(stoneId:String):Void` restores `data[stoneId]` from `persistedData[stoneId]` (or removes if not persisted). Again, lazy reapplication via `ensureApplied`.
- `flush():Promise<Nothing>` writes current `data` to file and updates `persistedData` snapshot.
- `isDirty(?stoneId:String):Bool` compares `data` vs `persistedData` (per-stone or global).

3. Implement Project entry points
- Resolve stone by `getStone(id)`.
- Resolve effective store via `stone.config.configStore ?? project.configStore`.
- Build `StoneConfigView` from current stone state.
- Route `setStoneConfig` mode to ConfigStore set + optional flush.

4. Metadata path for UI
- Populate `meta` with stable runtime info from Stone/Project.
- Reserve `uiHints` slot without enforcing hint schema yet.

5. Wire tests
- Add tests in `test/project-config-api.test.mjs` or expand existing inspector tests.

## Test Checklist

- [x] `getStoneConfig` returns `null` for unknown stone ID.
- [x] `setStoneConfig` returns `false` for unknown stone ID.
- [x] `setStoneConfig` returns `false` when no ConfigStore is available.
- [x] `preview` updates effective config for generation and does not write file.
- [x] `persist` updates effective config and writes file.
- [x] `persist` is replace semantics for the whole entry.
- [x] `getStoneConfig` excludes runtime objects from `editable`.
- [x] `getStoneConfig` includes metadata (`className`, dependency IDs, store flags).
- [x] `clearStoneConfigPreview` removes in-memory entry and restores baseline/persisted result.

## Relationship to Other Beans

- Depends on `whet-pepc` (`Project.getStone(id)`), already completed.
- Uses `whet-giem` ConfigStore implementation.
- Supersedes old request-scoped preview direction in `whet-jwk0`; `whet-jwk0` now follows the same in-memory non-flush model.

## Summary of Changes

Implemented config read/update entry points on Project with full test coverage (16 tests).

### ConfigStore extensions (`src/whet/ConfigStore.hx`)
- Added `persistedData` snapshot tracking (updated on file read/write)
- `getEntryById(stoneId)` — public read access to current in-memory entry
- `setEntry(stoneId, patch)` — in-memory data update only (no file write, no stone reapplication)
- `clearEntry(stoneId)` — restores entry from persistedData snapshot (per-stone, no side effects)
- `flush()` — writes data to file, updates persistedData
- `isDirty(?stoneId)` — compares data vs persistedData (per-stone or global)
- Made `isJsonSerializable`, `deepClone`, `BASE_CONFIG_KEYS` public static for reuse

### Project entry points (`src/whet/Project.hx`)
- `getStoneConfig(id)` — returns StoneConfigView with editable config + metadata, or null
- `setStoneConfig(id, patch, mode)` — preview (in-memory) or persist (in-memory + flush)
- `clearStoneConfigPreview(id)` — restores persisted/baseline state
- New types: ConfigPatchMode, StoneConfigView, StoneConfigMeta

### Tests (`test/project-config-api.test.mjs`)
16 tests covering all checklist items plus edge cases (multi-stone preview isolation, deep clone safety, isDirty tracking).
