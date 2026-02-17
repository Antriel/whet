---
# whet-flfg
title: Stone output listing and source retrieval API
status: todo
type: task
created_at: 2026-02-17T08:33:04Z
updated_at: 2026-02-17T08:33:04Z
parent: whet-juli
blocked_by:
    - whet-pepc
---

Add introspection methods to query stone outputs and retrieve source data:

- listStoneOutputs(id) — list output IDs/paths without necessarily generating (use stone.list() or equivalent routed query).
- getStoneSource(id, sourceId?) — retrieve actual source data for a specific output (or all if no sourceId).

These are the core data-access methods the inspector protocol will call.

Tests: test listing outputs of a Files stone; test retrieving a specific source by ID.
