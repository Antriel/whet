---
# whet-a2d8
title: Config read/update entry points (preview + persisted modes)
status: todo
type: task
created_at: 2026-02-17T08:33:11Z
updated_at: 2026-02-17T08:33:11Z
parent: whet-juli
blocked_by:
    - whet-pepc
---

Add stone config access methods:

- getStoneConfig(id) — return current effective config for a stone.
- setStoneConfig(id, patch, mode) — apply a config patch. Mode is 'preview' (request-scoped, temporary) or 'persist' (saved to ConfigStore).

Preview patches are request-scoped — no global mutable overlay. Persisted patches go through ConfigStore (see ConfigStore bean).

Effective config = base (Project.mjs) ← persisted patch ← preview patch.

This bean covers the entry point API shape. ConfigStore implementation is a separate bean.
