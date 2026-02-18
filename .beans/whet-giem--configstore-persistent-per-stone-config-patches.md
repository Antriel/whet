---
# whet-giem
title: 'ConfigStore: persistent per-stone config patches'
status: todo
type: feature
priority: normal
created_at: 2026-02-17T08:33:20Z
updated_at: 2026-02-17T16:52:24Z
parent: whet-juli
blocked_by:
    - whet-v815
---

## Overview

Implement **ConfigStore** — a persistent, per-stone config patching system that externalizes tweakable parameters from scripts into committable JSON files. This replaces ad-hoc patterns like AudioDb's JSON database with a general-purpose mechanism built into Whet.

The name "ConfigStore" is working — in the future the backing store might become SQLite or similar, but JSON files are the first iteration.

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

### Loading: both auto and explicit
- Auto-load: a project-level default/global ConfigStore loads automatically.
- Explicit: users can create and load custom ConfigStores from `onInit()` for conditional scenarios (debug vs release, etc.).
- Sync read (`readFileSync`) is acceptable since these are small JSON files.

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
- `paths`, `recursive` (Files)

ConfigStore can only patch the data fields. Structural fields (Router, Stone instances, functions) are never in JSON.

## Patching & Idempotency

When a ConfigStore is bound to a stone:

1. **Baseline capture**: Snapshot current values of all JSON-serializable config keys (skip Routers, Stones, functions). Cheap — just the data fields.
2. **Apply**: For each key in the patch, set it on `stone.config`.
3. **Re-apply** (file changed externally): For each key in the *previous* patch not in new patch, restore from baseline. Then apply new patch. Idempotent.
4. **Remove**: Restore all baselined keys. Stone reverts to original config.

This means `stone.config` stays the single source of truth. No `effectiveConfig` indirection. No Stone API changes. Stones that do `this.config.operations` just work transparently.

### Deep merge semantics
- Objects: recursive merge (patch keys override base keys)
- Arrays: replace (patch array replaces base array entirely)
- Primitives: replace
- `null` value in patch: deletes the key from effective config

## Binding Model

ConfigStore is NOT on StoneConfig (stays transparent to Stone implementations). Binding is done externally:
```js
configStore.bind(sharpStone);
```

For **catch-all/global store**: `project.configStore` — a default ConfigStore at a project-level path for patching any stone without explicit binding. Created automatically with sensible default path, but path is configurable.

## Integration with Hash / Cache

When a persisted patch changes a stone's config, the stone's hash changes naturally (config values flow through `SourceHash.fromConfig()` or custom `generateHash()`). No special ConfigStore-awareness needed in the hash system.

## Relationship to Other Beans

- **whet-a2d8** (Config read/update entry points): Provides the API surface (`getStoneConfig`, `setStoneConfig` with preview/persist modes). Preview patches are request-scoped and don't touch ConfigStore. Persist mode calls into ConfigStore.
- **whet-juli** (parent epic): Stone Inspector & Dynamic Configuration.
- **AudioDb replacement**: ConfigStore handles the simpler case (patching existing stone configs). AudioDb-style "data defines which stones exist" is a higher-level pattern that might build on ConfigStore eventually but isn't directly replaced.

## Tests

- [ ] Patch application produces correct merged config (nested objects, arrays, primitives)
- [ ] `null` in patch removes key from effective config
- [ ] Flush writes JSON to expected path; load reads it back (round-trip)
- [ ] Removing a patch reverts stone to base config
- [ ] Re-apply is idempotent (changing file content applies cleanly)
- [ ] Structural fields (Router, Stone instances) are excluded from baseline/patching
- [ ] Unknown stone IDs in the file are preserved (forward compat)
- [ ] Multiple stones bound to same ConfigStore work independently
- [ ] Global/default ConfigStore patches any stone without explicit binding

## Open Questions (for future sessions)

### Binding API details
`configStore.bind(stone)` vs `stone.bindConfig(configStore)` vs something on Project? Leaning toward `configStore.bind(stone)` since ConfigStore is the active agent. But need to think through how the global config store's binding works (it binds to all stones? or on-demand?).

### Re-apply triggers
When the file changes externally, who triggers re-apply? Options:
- WS/API endpoint trigger from Scry/inspector (explicit)
- File watching (automatic, but adds complexity — is this Whet core's job or Scry's?)
- Manual reload command

### Global ConfigStore path default
What's the sensible default path for the project-level global ConfigStore? E.g. `whet-config.json` in project root? Or user must always specify?

### ConfigStore field in ProjectConfig
Should ProjectConfig grow a `configStore` or `configStores` field for declarative setup? Or is imperative (`new ConfigStore(...)`) sufficient?

### Interaction with commands
When a stone provides CLI commands, should the ConfigStore patch be applied before command execution too? We do know which stone a command belongs to (it's passed to `addCommand`). Probably yes for consistency, but needs verification.

### AudioDb migration path
How does AudioDb evolve once ConfigStore exists? The per-entry audio config (opusConfig, aacConfig, preprocess) could move into a ConfigStore. But AudioDb also creates/destroys stones dynamically, which ConfigStore doesn't handle. Is there a clean incremental path, or do they remain separate patterns?

### Edge cases with non-data config values
Some config fields are borderline — e.g. `encodingOptions: string[]` in Audio is data-like but set via `setOpusConfig()`/`setAacConfig()` helper methods that have logic. If a ConfigStore patches `encodingOptions` directly, the helper's logic is bypassed. Is this fine (user knows what they're doing) or do we need a hook system?

## Reference: Real Stone Config Patterns

Key files examined during planning:
- `SharpStone.mjs`: operations pipeline, operationsMap, outputs, keepOriginalIfNoOps — all pure data, ideal ConfigStore target
- `Audio.mjs`: container, encoder, encodingOptions — data, but set via helper methods
- `AudioWav.mjs`: preprocess (startTime, duration) — simple data
- `AudioDb.mjs`: dynamic stone creation from JSON — higher-level pattern, not directly ConfigStore's scope
- `Inkscape.mjs`: ids array [{id, scale, name}] — data, good ConfigStore target
- `Files.hx`: paths, recursive — mostly structural (paths = what to read)
- `Stone.hx`: base StoneConfig (cacheStrategy, id, project, dependencies) — all structural, never patched
