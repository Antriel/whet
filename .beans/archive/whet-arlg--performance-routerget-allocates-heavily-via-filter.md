---
# whet-arlg
title: 'Performance: Router.get allocates heavily via filter cloning and full list scans'
status: completed
type: task
priority: high
created_at: 2026-02-14T08:29:36Z
updated_at: 2026-02-17T07:49:49Z
parent: whet-4ve1
---


Router cloned Filters per route and again per source entry (`Router.hx:35`, `Router.hx:63`) after calling `stone.list()` for every candidate. Complexity grew with route fanout and asset count.

## What was done

1. **Zero-copy `clone()`**: `pathSoFar` and `remDirs` are effectively immutable (always replaced via `concat`, never mutated in-place). Removed `.copy()` from clone; changed `add()` to use `concat` instead of `push` for `remDirs` to maintain that invariant.
2. **`tryFinalize()` replaces inner clone**: Instead of clone+finalize+getServeId per sourceId, saves scalar refs, runs finalize, extracts result, restores. Single-filter fast path (the common case) uses zero extra allocations.

Wall-clock improvement ~6-14% depending on access pattern (20 routes × 200 assets benchmark). Modest because minimatch matching dominates; the real win is reduced GC pressure under sustained load.

## Remaining opportunities (not yet implemented)

The dominant cost is now minimatch — `filter.match()` is called for every sourceId × filter combination. Potential next steps:

- **Early prefix rejection**: Before calling `minimatch.match()`, check if the path shares a common prefix with the pattern using a simple string comparison. Most non-matching paths fail on the first directory segment.
- **Batch `list()` with pattern push-down**: Instead of `stone.list()` returning all sourceIds then filtering, pass the query pattern into `list(pattern)` so stones with known structure (e.g. Files stone backed by a directory) can use `fs.glob` or skip subtrees.
- **Cached list results**: `stone.list()` re-generates the full source list on every `router.get()` call even when the stone hash hasn't changed. A lightweight list cache (invalidated by hash) would avoid repeated work for multi-query scenarios (server serving many requests).
