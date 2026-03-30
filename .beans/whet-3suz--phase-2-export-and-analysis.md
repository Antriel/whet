---
# whet-3suz
title: 'Phase 2: Export and Analysis'
status: completed
type: feature
priority: normal
created_at: 2026-03-28T06:51:38Z
updated_at: 2026-03-30T07:09:40Z
parent: whet-mosz
blocked_by:
    - whet-j8n9
---

Export profiling data for post-hoc analysis and visualization.

### Deliverables

- [x] JSON export format: array of spans with parent references + summary metadata (spanCount, stoneCount, totalGenerations, cacheHitRate)
- [x] Chrome Trace export format for chrome://tracing flame charts
  - Timestamp conversion: capture `baseEpochUs = Date.now() * 1000` and `basePerfUs = performance.now() * 1000` at Profiler construction
  - Per span: `ts = baseEpochUs + (span.startTime * 1000 - basePerfUs)` for epoch microseconds
- [x] `getSummary()` method: aggregate from `SpanStats` -- byStone (generates, avgDuration, cacheHits, lastDuration), byOperation (count, totalMs), cacheHitRate
- [x] `getSpansSince(sinceId)` method: return spans from ring buffer newer than span ID (for polling)
- [x] CLI `--profile` flag: enable profiling for the run, export to whet-profile.json on exit
- [x] CLI `profile` command: export current profiler state (supports --format json|trace)


## Summary of Changes

### Profiler.hx — Export and analysis methods
- `export(format)` — exports spans as JSON (with serialized status enums, parent refs, and summary meta) or Chrome Trace format (with epoch microsecond timestamps, per-stone thread IDs)
- `getSummary()` — aggregates byStone (generates, avgDuration, lastDuration, cacheHits), byOperation (count, totalMs), cacheHitRate from recorded spans
- `getSpansSince(sinceId)` — delegates to SpanRecorder for polling-based consumers
- Base timestamp capture (`baseEpochUs`, `basePerfUs`) at construction for Chrome Trace epoch conversion

### Whet.hx — CLI integration
- `--profile` flag: enables profiling on all projects, writes `whet-profile.json` on process exit
- `profile` command: dumps current profiler state to stdout with `--format json|trace` option

### Tests — 7 new tests (20 total profiler tests, 127 total)
- JSON export structure (spans array, meta fields, field serialization)
- Chrome Trace format (traceEvents, epoch microseconds, per-stone tids)
- getSummary aggregation (byStone, byOperation, cacheHitRate, cache hit tracking)
- getSpansSince delegation
