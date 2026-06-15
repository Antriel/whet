---
# whet-wjnl
title: Cache-metadata-backed listIds() fast path (perf §2.1)
status: completed
type: task
priority: normal
created_at: 2026-06-13T07:37:11Z
updated_at: 2026-06-13T07:41:24Z
---

From PERFORMANCE_REVIEW.md §2.1. `Stone.listIds()` falls back to a full `getSource()` (reading every file of a FileCache entry) when `list()` returns null — notably for ScryMultiAtlas. But `RuntimeFileCacheValue.files[].id` already holds the id list. Add a cache fast path that answers `listIds()` from metadata with zero file reads / zero generation.

## Plan
- [x] Add `getValueIds(value):Array<SourceId>` abstract to `BaseCache`; implement in `FileCache` and `MemoryCache`.
- [x] Add `tryListIds(stone)` to `BaseCache` (gated on non-null hash + complete matching entry, no lock/durability side effects).
- [x] Add `tryListIds` to `Cache` interface and `CacheManager`.
- [x] Wire into `Stone.listIds()` between `list()`==null and the `getSource()` fallback.
- [x] Tests added (FileCache files-deleted + InMemory: listIds does not regenerate; cold-cache still falls back). fs.readFile spy dropped — compiled output uses `import * as Fs from "fs"` (read-only ESM namespace); generateCount via deleted-files is the robust signal.
- [x] Build clean; full suite 178/178 pass.

## Correctness
Sound because the output id-set is a pure function of the stone hash; a complete matching-hash entry's `files` is authoritative. Stale/missing files are handled at fetch time (getPartialSource still stat-validates + regenerates). Gated on non-null `finalMaybeHash()`; only complete entries used.

## Summary of Changes

- `Cache.hx`: added `tryListIds(stone)` to the interface.
- `BaseCache.hx`: implemented `tryListIds` (compute `finalMaybeHash()`; null hash or no `complete` matching-hash entry → null; else `getValueIds(value)`). Added abstract `getValueIds(value)`. No lock, no use-order/durability mutation.
- `FileCache.hx` / `MemoryCache.hx`: implemented `getValueIds` (`value.files[].id` / `value.data[].id`).
- `CacheManager.hx`: `tryListIds` dispatch (None→null, InMemory→memCache, InFile/AbsolutePath→fileCache).
- `Stone.hx`: `listIds()` now tries `cache.tryListIds(this)` before the `getSource()` fallback.
- `test/partial.test.mjs`: 3 new tests under the §2.1 heading.

Result: a warm cache answers `listIds()` from metadata with zero file reads / zero generation. Verified the two metadata tests fail when the fast path is removed.
