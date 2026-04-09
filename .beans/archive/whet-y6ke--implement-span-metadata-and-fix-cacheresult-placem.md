---
# whet-y6ke
title: Implement span metadata and fix cacheResult placement
status: completed
type: task
priority: normal
created_at: 2026-03-30T14:30:11Z
updated_at: 2026-03-30T14:36:44Z
parent: whet-mosz
---

Populate metadata for all span operations (Hash, Generate, CacheWrite, List, LockHeld cacheResult). Remove cacheResult from GenerateMeta since Generate only fires on cache miss. Set cacheResult on LockHeld span via ALS context. Add tests for metadata.

## Summary of Changes

- Removed `cacheResult` from `GenerateMeta` — Generate spans only exist on cache miss, so it was always "miss"
- Added `Profiler.getCurrentSpan()` and `Stone.profilerGetCurrentSpan()` to access the current ALS span context
- Populated metadata on all span operations in `BaseCache`:
  - **LockHeld**: `cacheResult` ("hit", "miss", or "partial") set after cache lookup
  - **Hash**: `hashHex` set after hash computation
  - **Generate**: `outputCount` and `totalBytes` set after source generation
  - **List**: `resultCount` set after list() call
- Already-populated metadata confirmed working: LockWait (queuePosition/queueLength), DependencyResolve (dependencyIds), GeneratePartial (sourceId)
- Added 7 new tests covering metadata for Hash, Generate, LockHeld miss/hit, summary cache rate, DependencyResolve, and LockWait
