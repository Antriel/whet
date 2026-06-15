---
# whet-9ce4
title: Single-file partial reads + Files.generatePartial (perf §2.2/§2.3)
status: completed
type: task
priority: normal
created_at: 2026-06-13T07:47:49Z
updated_at: 2026-06-13T07:51:48Z
---

From PERFORMANCE_REVIEW.md §2.2 + §2.3. Serving one output of a multi-file entry currently reads every file of the entry; serving one static file from a `Files` directory reads the whole directory.

## §2.2 — single-file partial reads in FileCache
- [x] Extracted `readCachedFile(stone, file)` in `FileCache` (resolves SourceData/null; retired the `Invalid.` sentinel + throw hack).
- [x] `source()` rewritten on top of `readCachedFile` (null if any file invalid). Added `absolutePathInvalid` helper to dedupe the path check.
- [x] Added `sourcePartial` abstract; FileCache reads only the requested file, MemoryCache filterTo.
- [x] `getPartial` hit path reads only the requested file via `sourcePartial`; refactored the regenerate branch into a local `regenerate()` and route single-file invalidation into it (instead of returning null).

## §2.3 — Files.generatePartial
- [x] Added `Files.generatePartial` (resolves id via `walk()`, reads only that file).

## Tests
- [x] §2.2 tests: one-file-read on warm cache + valid file served when sibling missing (regen of missing one).
- [x] §2.3 test: Files over multi-file dir reads one file on getPartialSource.
- [x] Build clean; full suite 181/181. Verified all 3 new tests fail when fixes reverted in compiled output.

## Notes
fs spy infeasible (compiled uses read-only `import * as Fs from "fs"`); `SourceData` static methods are writable, so spy there. Depends on §2.1 (whet-wjnl).

## Summary of Changes

- `FileCache.hx`: `readCachedFile` (single-file stat+validate+read, resolves null on invalid — removed the `Invalid.` string-sentinel and `js.Syntax.code(throw)` hack); `source()` rebuilt on it; new `sourcePartial()` reads only the requested file; `absolutePathInvalid()` helper; `RuntimeFileEntry` typedef.
- `BaseCache.hx`: abstract `sourcePartial`; `getPartial` hit path now reads only the requested file and, on single-file invalidity, regenerates just it (local `regenerate()` extracted from the old else-branch) rather than returning null.
- `MemoryCache.hx`: `sourcePartial` = `value.filterTo`.
- `Files.hx`: `generatePartial` resolves the id via the same `walk()` listing and reads only that file.
- Tests: 2 in `partial.test.mjs` (§2.2), 1 in `cache.test.mjs` (§2.3), via writable-static `SourceData.fromFile`/`fromFileSkipHash` spies.

Behavior note: a stale/missing sibling no longer blocks serving a valid file (previously whole-entry validation returned null); per-file validation happens lazily as each file is requested.
