---
# whet-j8n9
title: 'Phase 1: Core Profiler'
status: completed
type: feature
priority: normal
created_at: 2026-03-28T06:51:38Z
updated_at: 2026-03-28T09:39:50Z
parent: whet-mosz
---

Implement the core profiling infrastructure in Haxe. This is the foundation -- everything else builds on it.

### Deliverables

- [x] `SpanOp` abstract enum over String (zero-overhead op names, compiles to string literals)
- [x] Metadata typedefs per op: `LockWaitMeta`, `LockHeldMeta`, `HashMeta`, `GenerateMeta`, `GeneratePartialMeta`, `DepResolveMeta`, `CacheWriteMeta`, `ListMeta`, `ServeMeta`
- [x] `Span` class with `estimatedDuration` field (populated from historical stats on start)
- [x] `SpanRecorder` with ring buffer using `haxe.ds.Vector` (pre-allocated, default 10K)
- [x] `SpanStats` -- incremental per-{stoneId, op} timing tracker (`lastDuration`, `avgDuration`, `count`)
- [x] `SpanEvent` type (Start + End) and `SpanEventType` enum
- [x] `Profiler` class:
  - `withSpan(stone, op, fn, ?meta)` -- primary API, wraps fn in ALS context + timing
  - `startSpan(stone, op, ?meta)` / `endSpan(span)` -- secondary, for LockWait only
  - `subscribe(listener)` / `emit(type, span)` -- synchronous event bus
- [x] `AsyncLocalStorage` JS extern for Haxe
- [x] `ProfilerConfig` typedef + `Project.enableProfiling()` / `disableProfiling()`
- [x] Instrument `Stone.hx`:
  - `acquire()`: LockWait (manual startSpan/endSpan) + LockHeld (withSpan wrapping run callback)
  - `generateSource()`: DependencyResolve (withSpan wrapping `Promise.all(deps)`)
  - Inline helpers: `profilerWithSpan`, `profilerStartSpan`, `profilerEndSpan` on Stone (null-check profiler)
- [x] Instrument `BaseCache.hx`:
  - `get()`: Hash (wrapping `finalMaybeHash`), Generate (wrapping `generateSource`), CacheWrite (wrapping `set`)
  - `getPartial()`: Hash (wrapping `finalMaybeHash`), GeneratePartial (wrapping `generatePartialSource`)
  - `completePartialEntry()`: List (wrapping `stone.list()`)
- [x] Verify compiled JS output: inline null checks expand correctly, no unexpected overhead

## Summary of Changes

Implemented the core profiling infrastructure for Whet:

**New files:**
- `src/whet/profiler/Span.hx` — `Span` class, `SpanOp` abstract enum (compiles to string literals), `SpanStatus` enum, `SpanEvent`/`SpanEventType` types, and all metadata typedefs
- `src/whet/profiler/SpanRecorder.hx` — Ring buffer storage using `haxe.ds.Vector` (default 10K spans)
- `src/whet/profiler/SpanStats.hx` — Incremental per-{stoneId, op} timing tracker
- `src/whet/profiler/Profiler.hx` — Main profiler with `withSpan` (ALS context + timing), `startSpan`/`endSpan`, synchronous event bus
- `externs/js/node/AsyncLocalStorage.hx` — Node.js `AsyncLocalStorage` extern

**Modified files:**
- `src/whet/Project.hx` — Added `profiler` field, `enableProfiling()`/`disableProfiling()`, `ProfilerConfig` in `ProjectConfig`
- `src/whet/Stone.hx` — Added inline helpers (`profilerWithSpan`, `profilerStartSpan`, `profilerEndSpan`); instrumented `acquire()` with LockWait/LockHeld spans; instrumented `generateSource()` with DependencyResolve span
- `src/whet/cache/BaseCache.hx` — Instrumented `get()` with Hash/Generate/CacheWrite spans; `getPartial()` with Hash/GeneratePartial; `completePartialEntry()` with List

**Design decisions:**
- Dropped GADT type parameter from `SpanOp<T>` — Haxe abstract enums don't support GADT unification for storage in `Span<Dynamic>`. Used unparameterized `SpanOp` with `Dynamic` metadata, which still provides zero-overhead string literals in compiled JS
- All instrumentation uses `inline` functions that expand to null checks at callsites — zero overhead when profiler is disabled
