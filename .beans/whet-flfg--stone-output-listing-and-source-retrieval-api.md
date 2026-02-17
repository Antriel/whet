---
# whet-flfg
title: Stone output listing and source retrieval API
status: completed
type: task
priority: normal
created_at: 2026-02-17T08:33:04Z
updated_at: 2026-02-17T09:03:06Z
parent: whet-juli
blocked_by:
    - whet-pepc
---

Add introspection methods to query stone outputs and retrieve source data:

- listStoneOutputs(id) — list output IDs/paths without necessarily generating (use stone.list() or equivalent routed query).
- getStoneSource(id, sourceId?) — retrieve actual source data for a specific output (or all if no sourceId).

These are the core data-access methods the inspector protocol will call.

Tests: test listing outputs of a Files stone; test retrieving a specific source by ID.

## Summary of Changes\n\nAdded two methods to `Project.hx`:\n\n- `listStoneOutputs(id:String):Promise<Null<Array<SourceId>>>` — looks up stone by ID and delegates to `stone.list()`. Returns null if stone not found.\n- `getStoneSource(id:String, ?sourceId:SourceId):Promise<Null<Source>>` — looks up stone by ID and delegates to `stone.getSource()`. Returns null if stone not found. Callers use `source.get(sourceId)` to filter to a specific output.\n\nBoth methods follow the same null-if-not-found pattern as `getStone()`.
