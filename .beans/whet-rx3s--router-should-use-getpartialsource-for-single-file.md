---
# whet-rx3s
title: Router should use getPartialSource for single-file requests
status: completed
type: task
priority: normal
created_at: 2026-02-17T13:56:26Z
updated_at: 2026-02-19T10:27:51Z
blocked_by:
    - whet-8gja
---

RouteResult.get() (src/whet/route/RouteResult.hx:14) currently calls source.getSource() and then filters to sourceId. This bypasses partial generation entirely — the main runtime gain for preview-style single-file requests.

Switch RouteResult.get() to call source.getPartialSource(sourceId) instead. The fallback behavior (full gen + filter for stones without generateHash/generatePartial) is already handled inside Stone.getPartialSource, so this is a safe drop-in change.

## Changes
- `src/whet/route/RouteResult.hx:14`: `source.getSource().then(data -> data.get(sourceId))` → `source.getPartialSource(sourceId)`
- Handle null return (sourceId not found) — return null SourceData to match current contract where `Source.get()` can return null
