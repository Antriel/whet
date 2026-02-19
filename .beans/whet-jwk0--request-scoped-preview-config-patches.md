---
# whet-jwk0
title: In-memory preview config patches (non-flushed ConfigStore state)
status: completed
type: task
priority: normal
created_at: 2026-02-17T08:33:44Z
updated_at: 2026-02-18T15:06:56Z
parent: whet-juli
blocked_by:
    - whet-a2d8
---

Implement preview mode as direct ConfigStore in-memory updates without flush.

## Decision Update

This bean replaces the previous request-scoped design. For current single-user inspector workflows, request-keyed preview overlays are unnecessary complexity.

Preview is now:
- `setStoneConfig(..., "preview")` updates ConfigStore entry in memory.
- No flush to disk.
- Effective config for stone operations reads this current in-memory state naturally through existing ConfigStore application.

Persist remains:
- `setStoneConfig(..., "persist")` updates in memory and flushes.

## Scope

1. Ensure preview mode does not introduce separate overlay structures in Stone.
2. Ensure no request/session IDs are required in runtime APIs.
3. Keep optional dirty tracking (`isDirty`) for UI.
4. Provide explicit clear operation for preview/reset:
- `clearStoneConfigPreview(id)` at Project entry points.

## Effective Config

`base (Project.mjs) <- persisted file entry <- current in-memory ConfigStore entry`

In preview mode, the in-memory entry diverges from file content until persisted or cleared.

## Implementation Notes

- ConfigStore tracks `persistedData` (file snapshot) vs `data` (current in-memory state).
- `setEntry` modifies only `data`. No proactive stone update needed — `ensureApplied` (called lazily on next getSource/getHash) detects mismatch vs `appliedPatches` and reapplies.
- `clearEntry` restores `data[stoneId]` from `persistedData[stoneId]`, enabling per-stone clear without affecting other stones.
- `flush()` is the only operation that makes preview changes persistent (writes `data` to file, updates `persistedData`).
- `isDirty` compares `data` vs `persistedData` for inspector UX.
- Existing hash/source paths remain unchanged; they already re-check and apply ConfigStore state via `finalMaybeHash`.

## Test Checklist

- Preview updates generation behavior immediately.
- Preview does not write file.
- Preview survives across multiple WS/HTTP operations until changed or cleared.
- Clear operation restores behavior from persisted file state.
- Persist after preview writes the current in-memory entry.
