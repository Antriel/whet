---
# whet-6s58
title: Native dynamic Stone creation (AudioDb pattern replacement)
status: draft
type: feature
priority: low
created_at: 2026-02-18T08:04:06Z
updated_at: 2026-02-18T09:57:47Z
parent: whet-juli
---

Native Whet support for dynamically creating and managing Stones from external data, replacing ad-hoc patterns like AudioDb's syncStones().

## Problem

AudioDb (and potentially other data-driven workflows) dynamically creates Stone instances at runtime from external data (a JSON database). The current pattern is awkward and ad-hoc:

- `syncStones()` clears `routes.length = 0` and rebuilds the entire stone/route graph
- Stone instances are created/destroyed outside the normal lifecycle
- Route array manipulation is used as a cache invalidation hack
- The JSON database is external state that must be manually kept in sync with the Stone graph
- Adding/removing entries requires the host (AudioDb) to manage the full lifecycle

### Current AudioDb Architecture

AudioDb extends Router and manages a `stoneMap: Map<string, StoneEntry>`. Each audio asset gets a chain of stones:

```
AudioWav → AudioSox → Audio (ogg)
                    → Audio (m4a)
                    → AudioMeta (sox/ogg/m4a)
```

On `syncStones()`:
1. Routes are cleared (`this.routes.length = 0`)
2. For each entry in the JSON db, stones are created or updated via `_syncSingleStone()`
3. On next `getResults()`, routes are rebuilt from the stoneMap

This works but is fragile: the route-clearing is a cache invalidation side-effect, stone creation order matters for ID stability, and the pattern is entirely manual.

## Key Insight: Per-Item Stones Have Correct Cache Granularity

During implementation of partial generation for batch stones (whet-8gja), we discovered a fundamental tradeoff:

**Batch stone (e.g., SharpStone with 100 images)**:
- One stone hash covers all outputs
- Changing config for one sub-item (via `operationsMap`) changes the hash for the entire stone
- ALL cached outputs are invalidated, even unchanged ones
- Partial generation helps (generate on demand, not all at once) but unchanged items still regenerate on next request

**Per-item stones (e.g., AudioDb creating one Stone per audio file)**:
- Each item has its own stone with its own hash
- Changing config for one audio only invalidates that one stone's cache
- Other items are completely unaffected — correct granularity for free

This means converting AudioDb to a batch stone pattern would make caching *worse*. The per-item stone model is architecturally correct for data where each item has independent config. The problem is purely management ergonomics.

### When Batch Stones Are Right vs Per-Item Stones

**Batch stones** (SharpStone model): uniform or mostly-uniform processing of many inputs. Global config changes dominate. Per-item config (`operationsMap`) is the exception. Partial generation is a genuine win.

**Per-item stones** (AudioDb model): each item has distinct, independently editable config (compression settings, preprocessing, etc.). Cache granularity per item is essential. The problem is lifecycle management, not the model.

## Vision: Dynamic Stone Registry

Instead of stones being created ad-hoc in user code (AudioDb's `_syncSingleStone`), Whet could natively support a "stone factory" or "dynamic stone registry" pattern:

- A data source (JSON file, ConfigStore, etc.) describes what stones should exist and their config
- Whet creates/updates/removes stone instances automatically when the data changes
- Each dynamically created stone is a real Stone with its own hash, cache, lifecycle
- The factory/registry handles ID assignment, route registration, cleanup

This is conceptually similar to how ConfigStore (Phase 4) adds a dynamic layer for config — but for the stone *graph* itself.

### Relationship to ConfigStore

ConfigStore (Phase 4) handles: "this stone exists, but its config can change at runtime."

Dynamic Stone Registry handles: "what stones exist can change at runtime."

These are complementary. A dynamic stone could have its per-item config managed by ConfigStore, getting both dynamic creation and dynamic config editing.

### Sketch of Possible API

```javascript
// A factory that creates stones from data entries
const audioFactory = new StoneFactory({
  // Data source — could be a Stone (JsonStone), ConfigStore, or raw data
  dataSource: audioJsonStone,

  // Factory function: given an entry, return stone(s) for it
  create: (entry, name) => {
    const wav = new AudioWav({ source: new Router(entry.sourceFile), preprocess: entry.preprocess });
    const sox = new AudioSox({ source: new Router(wav), sox: entry.preprocess.sox });
    const ogg = new Audio({ source: new Router(sox) }).setOpusConfig(entry.opusConfig);
    const m4a = new Audio({ source: new Router(sox) }).setAacConfig(entry.aacConfig);
    return { sox, ogg, m4a }; // Returned stones get registered and routed
  },

  // How to derive the routing key from entry
  keyFrom: (entry) => entry.name,

  // Route mapping: which created stones map to which serve paths
  routes: (key, stones) => [
    [key + '.wav', stones.sox],
    [key + '.ogg', stones.ogg],
    [key + '.m4a', stones.m4a],
  ]
});
```

When `dataSource` changes (entry added, removed, or modified):
- New entries: `create()` is called, stones registered, routes added
- Removed entries: stones deregistered, routes removed, cache optionally cleaned up
- Modified entries: stone config updated (potentially via ConfigStore), cache invalidated per-stone

### Key Design Questions (TBD)

1. **Stone deregistration**: Currently stones are added to `project.stones` and never removed. Need a clean removal mechanism (remove from project.stones, clean up cache entries, remove routes).

2. **ID stability**: Dynamic stones need stable IDs across data changes. Could use the factory key (e.g., audio name) as the stone ID prefix. E.g., `AudioFactory:footstep:AudioSox`.

3. **Trigger mechanism**: How does the factory know data changed? Options:
   - File watching (data source is a JSON file on disk)
   - Explicit `sync()` call (like current AudioDb)
   - ConfigStore change events
   - Observable/reactive data source

4. **Stone update vs recreate**: When an entry's config changes, can we update the existing stone's config in place (preserving cache where applicable)? Or must we destroy and recreate? Update-in-place is more efficient but harder.

5. **Dependency tracking**: Dynamic stones may depend on the data source stone. Currently AudioDb passes `dependencies: this.db` to child stones. The factory should wire this automatically.

6. **Scope**: Should this be a Whet core primitive, or a user-space pattern with helper utilities? Core is cleaner but higher bar for API design.

## Relationship to Existing Plan

This feature refines **V2 Plan Phase 6** ("Data-Driven Workflows"). The original Phase 6 suggested "replace ad-hoc dynamic graph patterns where beneficial with batch-step stones" — but the analysis above shows that converting per-item patterns to batch stones would *worsen* cache granularity.

Instead, Phase 6 should:
- Keep per-item stones for data where each item has independent config
- Improve the management ergonomics (this feature)
- Reserve batch stones for genuinely uniform workloads (SharpStone, texture atlases)

## Prerequisites

- Unique Stone IDs (Phase 1) — needed for stable dynamic stone identification
- ConfigStore (Phase 4) — natural companion for per-item config management
- Possibly: stone deregistration API (new, not in current plans)

## Non-Goals (Initially)

- Automatic schema migration when data format changes
- Multi-level nesting of dynamic factories
- Real-time streaming of stone creation (batch sync is fine)
- Converting SharpStone to this pattern (it's correctly a batch stone)

---

## Assistant Reaction (Open Discussion, Not Part of Original Draft)

The notes below are my review comments only. They are intentionally separated from the original proposal.

### What Looks Strong

- The core insight is correct: per-item Stones keep the right cache invalidation granularity for independently editable items, while batch Stones couple invalidation through one hash.
- Reframing this as a lifecycle/ergonomics problem (instead of a modeling problem) is the right move.
- Separating dynamic config (ConfigStore) from dynamic topology (factory/registry) is a clean architectural split.

### Critical Gaps To Address Before Build

1. Removal lifecycle does not exist in core APIs today.
- Stones are appended to `project.stones` during construction and there is no official deregistration path.
- Router supports adding routes but there is no owner-scoped remove API.

2. Sync atomicity needs explicit design.
- A factory sync must avoid transient partial states.
- Recommended shape: compute diff (add/update/remove) against current snapshot, stage new routes/instances, then commit swap.

3. ID policy must be strict and deterministic.
- Dynamic IDs should be derived from stable keys and factory identity.
- Key rename semantics should be explicit: rename = remove old + create new (unless a migration mechanism is introduced later).

4. Cache cleanup policy must be explicit.
- On dynamic removal, decide whether to eagerly purge cache entries or rely on existing durability eviction.
- This should likely be a per-factory option (e.g. `purgeOnRemove: true|false`).

5. Introspection/ownership metadata is likely needed.
- `project.describeStones()` may need optional ownership fields so inspector tooling can group/filter dynamic children by factory.

### Suggested v1 Scope (Pragmatic)

- Keep this as the Phase 6 direction.
- Implement a minimal `StoneFactory` first:
  1. `sync()` with add/update/remove diffing
  2. deterministic ID convention
  3. route ownership + cleanup
  4. optional cache purge on remove
- Delay advanced topics (schema migration, nested factories, reactive source abstractions) until this baseline proves stable.

### Suggested Plan Text Adjustment

In `STONE_INSPECTOR_PLAN_v2.md`, replace/clarify wording that implies moving data-driven workflows to batch-step stones by default.

Proposed clarification:
- Keep per-item stones for independently editable assets (audio-like workflows), and improve lifecycle ergonomics via native dynamic factory support.
- Use batch stones where workload/config is predominantly uniform and partial generation provides meaningful wins.
