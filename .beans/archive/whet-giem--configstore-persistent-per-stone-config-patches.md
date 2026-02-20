---
# whet-giem
title: 'ConfigStore: persistent per-stone config patches'
status: completed
type: feature
priority: normal
created_at: 2026-02-17T08:33:20Z
updated_at: 2026-02-18T09:37:50Z
parent: whet-juli
blocked_by:
    - whet-v815
---

## Overview

Implement **ConfigStore** — a persistent, per-stone config patching system that externalizes tweakable parameters from scripts into committable JSON files. This replaces ad-hoc patterns like AudioDb's JSON database with a general-purpose mechanism built into Whet.

The name "ConfigStore" is working — in the future the backing store might become SQLite or similar, but JSON files are the first iteration.

ConfigStore is a Haxe class in whet core (not JS-only).

## Motivation

- Move data-like configuration away from Project.mjs scripts into editable, committable files.
- Avoid dev server restarts when tweaking parameters (operations, encoding settings, etc.).
- Better organize config data — e.g. texture params separate from audio params.
- Position config store files next to source assets for natural project structure.
- Replace the awkward AudioDb JSON pattern with something Whet supports natively.

## Core Design Decisions

### Naming: ConfigStore
Describes what it is — a store that holds config. May evolve into a DB-backed store later.

### File location: user-provided, committable
NOT in `.whet/` (that directory is temporary). Files should be committed to version control. Users specify the path. Multiple ConfigStore instances are supported, positioned naturally next to source assets:
```js
const texConfig = new ConfigStore('assets/textures/config.json');
const audioConfig = new ConfigStore('assets/audio/config.json');
```

### Data structure: always a map
Always `{ [stoneId]: { ...patch } }`, even for single-stone files. One format, consistent, safe. Not meant to be hand-edited primarily, but human-readable JSON for when needed.

### Multiple files supported
Each ConfigStore instance = one JSON file. Multiple stones can share a file (keyed by stone.id). A stone could also have its own dedicated file. User wires this up in Project.mjs.

### Instance sharing: by reference, user-managed
Users create ConfigStore instances and pass the same instance to multiple stones. Same object = shared file data and mtime cache naturally. No registry or factory pattern. If user accidentally creates two instances for the same path, they just do redundant file reads — not broken, just slightly wasteful.

```js
const audioConfig = new ConfigStore('assets/audio/config.json');
new AudioWav({ source: ..., configStore: audioConfig });
new Audio({ source: ..., configStore: audioConfig });
```

### Loading: lazy, on-demand
No auto-loading. ConfigStore is constructed with just a path string — lightweight, no I/O at construction time. The backing JSON file is loaded lazily on first access (when a stone's hash/source is requested). Subsequent accesses check file mtime and reload only if changed.

No `readFileSync` — all I/O is async, triggered by the existing async hash/generation flow.

## Config Field Categories

From examining real stones, config fields fall into two categories:

**Structural/wiring fields** (live object instances, set once in script):
- `source: Router`, `pngs: Router`, `svg: Router` — data sources
- `dependencies`, `project`, `cacheStrategy` — framework wiring

**Data/parameter fields** (plain values, the tweakable knobs):
- `operations`, `operationsMap`, `keepOriginalIfNoOps`, `outputs` (SharpStone)
- `preprocess: { startTime, duration }` (AudioWav)
- `container`, `encoder`, `encodingOptions` (Audio)
- `ids: [{id, scale, name}]` (Inkscape)

ConfigStore can only patch the data fields. Structural fields (Router, Stone instances, functions) are never in JSON.

**Non-patchable data fields:**
- `paths` (Files) — while technically data, it's used to instantiate a Files Stone at construction time. The Files stone's `id` isn't unique and is derived from the path, making runtime modification awkward. This stays non-modifiable; dynamic router upgrades are a possible future extension.

## ConfigStore on StoneConfig and ProjectConfig

ConfigStore is a field on **StoneConfig** and **ProjectConfig**. It is transparent to stone implementations — the field is handled internally by the framework (excluded from hashing via `fromConfig`, not patchable by ConfigStore itself).

```js
// Project-level: applies to any stone without an explicit configStore
new Project({
    configStore: new ConfigStore('whet-config.json'),
});

// Stone-level: overrides project-level for this stone
new SharpStone({
    source: ...,
    configStore: new ConfigStore('assets/textures/config.json'),
});
```

**Lookup chain** in a stone: `this.config.configStore ?? this.config.project?.configStore ?? null`

Note: `project.config` is CLI/options runtime state (from `program.opts()`), not construction config. So `configStore` is a first-class field on `Project` itself (like `cache`, `rootDir`), populated from `ProjectConfig`.

Stone-level overrides project-level. The project-level store naturally serves as a "global" store — no explicit binding to all stones needed, they just fall through to it on demand.

## Patching & Idempotency

**Eager materialization with in-place sync.** No Proxy (bad for debugging, performance, behavior clarity). No `effectiveConfig` indirection. `stone.config` stays the single source of truth, mutated in place.

### Flow

1. **Baseline capture** (once, on first `ensureApplied` call): Deep-clone all JSON-serializable config keys from `stone.config` (skip Routers, Stones, functions). Store as the stone's baseline on the ConfigStore.
2. **Apply**: For each key in baseline, compute `merged = deepMerge(baseline[key], patch[key])` and set on `stone.config`. Keys added by old patch but absent from new patch and not in baseline are deleted.
3. **Re-apply** (file changed): Same as apply — recompute merged values from baseline + new patch. Baseline never changes. Idempotent.
4. **No unbind**: ConfigStore is a config field, always present once set. No explicit unbind/remove flow.

### Deep merge semantics
- Objects: recursive merge (patch keys override base keys)
- Arrays: replace (patch array replaces base array entirely)
- Primitives: replace
- `null` value in patch: sets the key to `null` (no special delete semantics — omit key from patch to restore baseline)

## State Split

**On ConfigStore instance** (shared across all stones using this store):
- `path: string` — file path
- `data: object | null` — parsed JSON content of the whole file
- `mtimeMs: number | null` — last known file modification time (milliseconds)
- `size: number | null` — last known file size (bytes, for invalidation alongside mtimeMs)

**On ConfigStore, per-stone** (via WeakMap, keyed by stone):
- `baselines: WeakMap<Stone, object>` — original config values before any patch
- `appliedPatches: WeakMap<Stone, object>` — last applied patch entry (for change detection)

WeakMap ensures: no memory leak if stones are GC'd (relevant for AudioDb-style dynamic stones), and all patching logic lives on ConfigStore rather than scattered across stones. The stone itself only has `config.configStore` — a plain reference.

## Integration with Hash / Cache: Hook Point

The natural hook point is **`finalMaybeHash()`** in `Stone.hx`. This is the true upstream chokepoint — all cache paths (`BaseCache.get()`, `BaseCache.getPartial()`, `CacheManager` for None strategy) call `stone.finalMaybeHash()` directly, never `stone.getHash()`. Before computing the hash, we ensure config reflects the current state of the backing file.

```haxe
// In Stone.finalMaybeHash(), before existing logic:
var store = config.configStore ?? config.project?.configStore;
var patchPromise = if (store != null) store.ensureApplied(this) else Promise.resolve(null);
return patchPromise.then(_ -> generateHash().then(hash -> finalizeHash(hash)));
```

### `ensureApplied(stone)` flow:
1. No data loaded? → `fs.stat` + `fs.readFile`, parse JSON, capture baseline from stone's current config, apply patch for `stone.config.id`
2. Data loaded? → `fs.stat`, compare mtimeMs + size → changed: reload file, re-apply from baseline → unchanged: no-op (also compare entry to `_appliedPatches` — file might have changed but this stone's entry didn't)
3. Entry same as last applied? → no-op, return immediately

**Concurrency**: Multiple stones sharing one ConfigStore could trigger concurrent `stat`/`readFile` calls. The ConfigStore holds a single in-flight promise for the reload operation — if a reload is already in progress, subsequent callers await the same promise (single-flight pattern).

### Why this works for both hash paths:
- **Stones with `generateHash()`**: They read `this.config` which has patched values → hash reflects patches naturally.
- **Stones without `generateHash()`**: Falls through to output byte hash via `getSource()` → `generateSource()`. But `finalMaybeHash()` runs first (called by cache), so config is patched before `generate()` reads it. Output reflects patches → byte hash reflects patches.

### No direct hash injection needed
We do NOT inject the config store entry hash separately. Modifying config values is sufficient — the existing hash mechanisms (`fromConfig`, custom `generateHash`, or output byte hash) pick up the changed values naturally. This avoids the problem of the whole ConfigStore file affecting unrelated stones' hashes.

### Interaction with commands
Config store patches are applied lazily via `finalMaybeHash()`/`getSource()`, so any code path that reads config after these calls sees patched values. Most commands trigger hash/source generation and get patches applied naturally. No separate per-command wrapping mechanism is needed — the `finalMaybeHash()` hook covers all paths.

## Relationship to Other Beans

- **whet-a2d8** (Config read/update entry points): Provides the API surface (`getStoneConfig`, `setStoneConfig` with preview/persist modes). Preview patches are request-scoped and don't touch ConfigStore. Persist mode calls into ConfigStore.
- **whet-juli** (parent epic): Stone Inspector & Dynamic Configuration.
- **AudioDb migration**: See below.

### AudioDb Migration Path
AudioDb's per-entry audio config (opusConfig, aacConfig, preprocess) moves into ConfigStore. The wav/sox, aac, opus stones become batch stones working off a Router with whole-directory input, with per-file config maps via ConfigStore. AudioDb can then go away — partial generation + ConfigStore enables per-file editing and generation with just 3 stones instead of dynamic stone creation.

Note: whole batch hash changes when any entry changes (acceptable trade-off), but `generatePartial` means only the requested file is actually processed. Quick iteration, simpler architecture. Future improvement for per-entry hash granularity is planned separately.

### Audio.mjs helper method edge case
For `setOpusConfig()`/`setAacConfig()` style helpers that have logic: turn the computed values into defaults directly in the code. Use `perFileConfig.field ?? fieldDefault` per field based on output type. ConfigStore patches the plain data fields (`bitrate`, `cutoff`, etc.) directly. This is cleaner than the current setter pattern regardless of ConfigStore.

## Tests

- [x] Patch application produces correct merged config (nested objects, arrays, primitives)
- [x] `null` in patch sets key to `null` (no special delete semantics)
- [x] Flush writes JSON to expected path; load reads it back (round-trip)
- [x] Re-apply from baseline is idempotent (changing file content applies cleanly)
- [x] Structural fields (Router, Stone instances) are excluded from baseline/patching
- [x] Unknown stone IDs in the file are preserved (forward compat)
- [x] Multiple stones sharing same ConfigStore instance work independently
- [x] Project-level ConfigStore applies to stones without explicit configStore
- [x] Stone-level configStore overrides project-level
- [x] Stale file detection: mtime change triggers reload and re-apply
- [x] Entry unchanged after file reload: no unnecessary config mutation
- [x] WeakMap cleanup: GC'd stones don't leak baseline/patch state (by design — WeakMap)
- [x] `configStore` field itself excluded from `fromConfig` hashing
- [x] Config patching happens before command execution

## Open Questions (for future sessions)

### Re-apply triggers beyond builds
Currently, config is patched lazily when `finalMaybeHash()`/`getSource()` is called. For the inspector UI (Scry), an explicit WS/API endpoint can trigger re-evaluation of affected stones. File watching is not in scope for v1 — explicit triggers only.

### Dynamic router upgrades
`paths` and similar structural fields that instantiate Routers/Files stones at construction time can't be patched by ConfigStore. A future extension could support dynamic router reconfiguration, but this is a separate concern.

## Reference: Real Stone Config Patterns

Key files examined during planning:
- `SharpStone.mjs`: operations pipeline, operationsMap, outputs, keepOriginalIfNoOps — all pure data, ideal ConfigStore target
- `Audio.mjs`: container, encoder, encodingOptions — data, set via helper methods (to be refactored to defaults)
- `AudioWav.mjs`: preprocess (startTime, duration) — simple data
- `AudioDb.mjs`: dynamic stone creation from JSON — to be replaced by batch stones + ConfigStore
- `Inkscape.mjs`: ids array [{id, scale, name}] — data, good ConfigStore target
- `Files.hx`: paths, recursive — `paths` is structural (non-patchable), `recursive` is data
- `Stone.hx`: base StoneConfig (cacheStrategy, id, project, dependencies) — all structural, never patched

## Summary of Changes

Implemented ConfigStore — a persistent, per-stone config patching system.

**New files:**
- `src/whet/ConfigStore.hx` — Core class with lazy file loading, baseline capture, deep merge patching, WeakMap-based per-stone state, and single-flight reload.
- `test/config-store.test.mjs` — 13 tests covering all spec requirements.

**Modified files:**
- `src/whet/Stone.hx` — Added `configStore` to `StoneConfig`; hooked `finalMaybeHash()` to call `store.ensureApplied()` before hash computation.
- `src/whet/SourceHash.hx` — Added `configStore` to `fromConfig` skip list.
- `src/whet/Project.hx` — Added `configStore` to `ProjectConfig` and `Project` class for project-level store.
- `build.hxml` — Added `whet.ConfigStore` for compilation/exposure.
- `test/helpers/mock-stone.mjs` — Added `configStore` passthrough in constructor.
