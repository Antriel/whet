---
# whet-3suz
title: 'Phase 2: Export and Analysis'
status: todo
type: feature
priority: normal
created_at: 2026-03-28T06:51:38Z
updated_at: 2026-03-28T09:25:20Z
parent: whet-mosz
blocked_by:
    - whet-j8n9
---

Export profiling data for post-hoc analysis and visualization.

### Deliverables

- [ ] JSON export format: array of spans with parent references + summary metadata (stoneCount, totalGenerations, cacheHitRate)
- [ ] Chrome Trace export format for chrome://tracing flame charts
  - Timestamp conversion: capture `baseEpochUs = Date.now() * 1000` and `basePerfUs = performance.now() * 1000` at Profiler construction
  - Per span: `ts = baseEpochUs + (span.startTime * 1000 - basePerfUs)` for epoch microseconds
- [ ] `getSummary()` method: aggregate from `SpanStats` -- byStone (generates, avgDuration, cacheHits, lastDuration), byOperation (count, totalMs), cacheHitRate
- [ ] `getSpansSince(timestamp)` method: return spans from ring buffer newer than timestamp (for polling)
- [ ] CLI `--profile` flag: enable profiling for the run, export on exit
- [ ] CLI `profile` command: export current profiler state (for long-lived processes)
