---
# whet-j8n9
title: 'Phase 1: Core Profiler'
status: todo
type: feature
priority: normal
created_at: 2026-03-28T06:51:38Z
updated_at: 2026-03-28T09:25:09Z
parent: whet-mosz
---

Implement the core profiling infrastructure in Haxe. This is the foundation -- everything else builds on it.

### Deliverables

- [ ] `SpanOp<T>` abstract enum over String (GADT pattern for type-safe metadata)
  - Test whether type parameter unification works (`SpanOp<GenerateMeta>` → `SpanOp<Dynamic>`)
  - If not, fall back to `Dynamic` metadata; abstract-over-String still gives zero-overhead op names
- [ ] Metadata typedefs per op: `LockWaitMeta`, `LockHeldMeta`, `HashMeta`, `GenerateMeta`, `GeneratePartialMeta`, `DepResolveMeta`, `CacheWriteMeta`, `ListMeta`, `ServeMeta`
- [ ] `Span<T>` class with `estimatedDuration` field (populated from historical stats on start)
- [ ] `SpanRecorder` with ring buffer using `haxe.ds.Vector` (pre-allocated, default 10K)
- [ ] `SpanStats` -- incremental per-{stoneId, op} timing tracker (`lastDuration`, `avgDuration`, `count`)
- [ ] `SpanEvent` type (Start + End) and `SpanEventType` enum
- [ ] `Profiler` class:
  - `withSpan<T,R>(stone, op, fn, ?meta)` -- primary API, wraps fn in ALS context + timing
  - `startSpan<T>(stone, op, ?meta)` / `endSpan(span)` -- secondary, for LockWait only
  - `subscribe(listener)` / `emit(type, span)` -- synchronous event bus
- [ ] `AsyncLocalStorage` JS extern for Haxe
- [ ] `ProfilerConfig` typedef + `Project.enableProfiling()` / `disableProfiling()`
- [ ] Instrument `Stone.hx`:
  - `acquire()`: LockWait (manual startSpan/endSpan) + LockHeld (withSpan wrapping run callback)
  - `generateSource()`: DependencyResolve (withSpan wrapping `Promise.all(deps)`)
  - Inline helpers: `withSpan`, `startSpan`, `endSpan` on Stone (null-check profiler)
- [ ] Instrument `BaseCache.hx`:
  - `get()`: Hash (wrapping `finalMaybeHash`), Generate (wrapping `generateSource`), CacheWrite (wrapping `set`); cache hit/miss as metadata on LockHeld span
  - `getPartial()`: GeneratePartial (wrapping `generatePartialSource`)
  - `completePartialEntry()`: List (wrapping `stone.list()`)
- [ ] Verify compiled JS output: inline null checks expand correctly, no unexpected overhead
