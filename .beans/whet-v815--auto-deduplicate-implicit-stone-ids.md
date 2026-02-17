---
# whet-v815
title: Auto-deduplicate implicit Stone IDs
status: completed
type: task
priority: normal
created_at: 2026-02-17T08:32:44Z
updated_at: 2026-02-17T08:43:11Z
parent: whet-juli
---

Stones with no explicit config.id get class-name-based IDs that collide (all SharpStones are 'SharpStone'). Auto-append :N suffix for duplicates (SharpStone, SharpStone:2, SharpStone:3). Explicit config.id collisions should warn.

Changes in Stone.hx constructor: after determining base ID, check project.stones for collisions, append :N if needed.

Considerations:
- FileCache keys by stone.id — only newly auto-deduped stones affected, existing explicit IDs unchanged.
- Stability across restarts is best-effort (construction order). Persistent refs should use explicit config.id.

Tests: unit test that multiple stones of same class get unique IDs; test that explicit config.id is preserved; test collision warning for duplicate explicit IDs.

## Summary of Changes

Auto-deduplication of implicit Stone IDs implemented in `Stone.hx` constructor:

- After determining the base ID, scans `project.stones` for existing stones with the same ID (or already-suffixed variants like `Name:2`, `Name:3`).
- For implicit IDs (class-name-based): appends `:N` suffix (e.g., `SharpStone`, `SharpStone:2`, `SharpStone:3`).
- For explicit `config.id` collisions: logs a warning but preserves the ID as-is.
- The first stone of each class keeps its unsuffixed name for backward compatibility.
