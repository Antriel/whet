---
# whet-giem
title: 'ConfigStore: persistent per-stone config patches'
status: todo
type: feature
created_at: 2026-02-17T08:33:20Z
updated_at: 2026-02-17T08:33:20Z
parent: whet-juli
blocked_by:
    - whet-v815
---

Implement ConfigStore that manages per-stone config patches:

- Store patches in JSON keyed by stone.id.
- Deep-merge patches into base config to produce effective runtime config.
- Flush to disk on request (not auto-save).
- Load on startup if file exists.

Patch semantics: deep merge baseline. Exact array/object merge rules TBD during implementation (start simple: object merge, array replace).

Location: likely .whet/config-patches.json or similar.

The store is the persistence backend. The API entry points (whet-a2d8) call into this.

Tests: test patch application produces correct merged config; test flush/load round-trip; test that removing a patch reverts to base config.
