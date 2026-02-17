# Stone Inspector & Dynamic Configuration Plan (V2)

## Purpose

Keep all original goals in scope:
1. Discover and inspect all Stones from external tools (Scry first).
2. View outputs of any Stone type (image/audio/json/html/etc.).
3. Modify Stone configuration live.
4. Persist desired config changes without manually editing `Project.mjs`.
5. Preserve standalone Whet usage (`npx whet publish` etc.) with no Scry requirement.

This version refines how we achieve those goals: simpler Stone authoring, more power in Whet internals.

---

## Core Decisions

## 1) Unique Stone IDs are required

- Keep explicit `config.id` as-is.
- Auto-deduplicate implicit IDs (`SharpStone`, `SharpStone:2`, ...).
- Add project lookup/list APIs for inspector tooling.

Why:
- External tools need stable references.
- ConfigStore persistence needs unambiguous keys.

Notes:
- Stability across restarts is best-effort for auto IDs (construction order based).
- For persistent references, explicit `config.id` remains recommended.

## 2) Preserve “Stone as coherent unit” by default

- Keep current full-Source cache model as default behavior.
- No mandatory per-file cache layer for all Stones.

Why:
- Matches existing mental model and keeps most Stones simple.
- Avoids global cache complexity for little gain on non-batch Stones.

## 3) Add optional partial read/generate for batch Stones

- New optional API path for hot paths (e.g. Sharp, future audio batch flows):
  - request one output (`sourceId`) with optional preview config patch.
- Default fallback: full generation + pick requested output.

Why:
- Enables fast live preview/tweaking without forcing complexity on every Stone.

## 4) Unify Router/Stone query model via common routed asset abstraction

- Introduce a shared contract (working name: `IRouteSource`) and a routed result abstraction (working name: `AssetRef`).
- Stone and Router both provide routed assets through the same external-facing model.
- Keep existing internals (`Source`, `RouteResult`) during migration where practical.

Why:
- Removes friction when configs evolve between single-source and batch/routed behavior.
- Lets Router avoid over-generation when a source supports partial operations.
- Gives a clean long-term API without forcing immediate total rewrite.

## 5) Layered dynamic config with persistence

- Effective runtime config is layered:
  - Base scripted config (`Project.mjs`)
  - Persisted patch from ConfigStore
  - Temporary preview patch (request scoped)
- Stones still consume a single effective config object.
- Persistable patch layer is keyed by unique stone ID.

Why:
- Keeps structural graph scripted and flexible.
- Allows external tools to persist edits (AudioDb-style flush) safely.
- Avoids global mutable overlays needing manual revert.

## 6) Keep validation/versioning minimal initially

- Patching is permissive; invalid configs may fail at generation time.
- No mandatory schema/version migration system in first iteration.
- Manual migration remains acceptable initially.

Why:
- Lower scope and faster delivery.

---

## Architecture Overview

## A) Inspector/Introspection Surface

Project-level methods:
- `describeStones()`
- `getStone(id)`
- `listStoneOutputs(id)` (or equivalent routed query)
- `getStoneSource(id, sourceId?)`

Scry plugin protocol:
- `stones:list`
- `stones:list-outputs`
- `stones:get-source`
- `stones:get-config`
- `stones:set-config` (preview or persisted mode)
- `stones:refresh` / `stones:preview`

Transport:
- WS for commands and stateful operations.
- HTTP endpoints for direct binary streaming (`<img src=...>`, `<audio src=...>`).

## B) Unified Routed Asset Contract

Target direction:
- A routed asset reference object can represent both Stone-origin and Router-origin outputs.
- Supports:
  - `serveId`
  - stable reference to origin
  - lazy `getData()`
  - hash access

Migration strategy:
- Introduce shared interface first.
- Keep existing internals and adapt incrementally.

## C) Partial Generation Capability

Optional per-Stone capability:
- If implemented: generate/read only requested output(s).
- If not implemented: automatic fallback to current full generation behavior.

Caching behavior:
- Allow partial caching where supported.
- Include generation mode/context in hash namespace to avoid collisions.
- Full-generation path remains canonical.

## D) ConfigStore

Responsibilities:
- Store per-stone config patches in JSON (or equivalent).
- Apply patches into effective runtime config.
- Flush to disk on request.

Keying:
- Unique `stone.id`.

Patch semantics:
- Deep merge baseline; exact array/object merge rules to be finalized during implementation.

---

## Phase Plan

## Phase 1: Identity & Registry (Whet core)

Deliverables:
1. Auto-deduplicated implicit Stone IDs.
2. `Project.getStone(id)`.
3. `Project.describeStones()` / listing helper.

Outcome:
- Reliable stone addressing for inspector and ConfigStore.

## Phase 2: Introspection API (Whet core)

Deliverables:
1. Stone discovery/metadata API.
2. Output listing/query API.
3. Source retrieval API.
4. Config read/update entry points (preview + persisted modes).

Outcome:
- Stable programmatic surface for Scry and future tools.

## Phase 3: Inspector Protocol (Scry plugin)

Deliverables:
1. `StoneInspectorPlugin` WS commands.
2. HTTP routes for direct binary serving.
3. Integration into Scry DevTools.

Outcome:
- Real-time stone browsing and content viewing.

## Phase 4: Dynamic Config Runtime (Whet core + selected Stones)

Deliverables:
1. Layered effective config resolution (base + persisted + preview patch).
2. Request-scoped preview patches (no global mutable overlay requirement).
3. Stone config set/flush API via ConfigStore.

Outcome:
- Live editing plus durable persistence without `Project.mjs` rewriting.

## Phase 5: Unified Routed Assets + Partial Generation (Whet core)

Deliverables:
1. Shared routed-source interface (`IRouteSource` direction).
2. Routed asset reference abstraction (`AssetRef` direction).
3. Optional partial read/generate API with full fallback.
4. Router optimization hooks to exploit partial support when available.

Outcome:
- Better performance for batch scenarios while keeping default Stone simplicity.

## Phase 6: Data-Driven Workflows (Audio-first migration)

Deliverables:
1. Replace ad-hoc dynamic graph patterns where beneficial with batch-step stones.
2. Move per-asset editable params into generic ConfigStore flow.
3. Preserve route outputs and external editing UX.

Outcome:
- Lower code complexity than current AudioDb orchestration while retaining flexibility.

## Phase 7: Scry Inspector UI

Deliverables:
1. Stone list/detail UI.
2. Multi-format output viewers.
3. Live editor controls (Sharp first).
4. Apply/flush config UX.

Outcome:
- End-to-end inspector and editor workflow for real projects.

---

## How This Improves on the Original Plan

1. Same goals, cleaner model:
- Inspector, runtime edits, persistence, and standalone Whet remain in scope.

2. Better separation of concerns:
- Structural graph stays in script.
- Editable params live in a managed persisted layer.

3. Less global mutation risk:
- Request-scoped preview patches avoid fragile overlay lifecycle.

4. Performance scales where needed:
- Partial generation is optional and targeted.
- Router can exploit capabilities without burdening all Stones.

5. Cleaner evolution path:
- Unified routed source abstraction addresses long-term Stone/Router API friction.
- Migration can be incremental without breaking everything at once.

---

## Open Items (Intentional TBD)

1. Final method names/types for `IRouteSource` / `AssetRef`.
2. Exact patch merge semantics for arrays and nested objects.
3. Which Stones get partial APIs in first wave (Sharp first; audio next).
4. Cache mode namespacing details for partial vs full artifacts.
5. Backward compatibility adapters during migration.

---

## Non-Goals (for now)

1. Automatic schema migration/versioning for ConfigStore patches.
2. Strict config validation framework.
3. Runtime creation of arbitrary new Stone graph topology from UI.
4. Multi-user conflict resolution beyond simple last-write-wins behavior.
