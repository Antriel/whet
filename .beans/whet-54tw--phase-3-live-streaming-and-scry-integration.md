---
# whet-54tw
title: 'Phase 3: Live Streaming and Scry Integration'
status: todo
type: feature
priority: normal
created_at: 2026-03-28T06:51:38Z
updated_at: 2026-03-28T09:25:37Z
parent: whet-mosz
blocked_by:
    - whet-j8n9
---

Integrate profiling with Scry for live dev server observability.

### Prerequisites (in ScryStone, not Whet core)

- [ ] Store `clientRegistry` as instance property on ScryStone (currently local in `serve()`)

### Deliverables

- [ ] `ProfilerPlugin` for ScryStone (at `scry/whetstones/plugins/ProfilerPlugin.mjs`):
  - `registerRoutes(app, stone, sendJson)`: instanceof assertion for ScryStone access to `clientRegistry`
  - REST: `/api/profiler/summary`, `/api/profiler/export?format=trace`, `/api/profiler/spans?since=<ts>`
  - WS: subscribe to profiler events, broadcast Start + End `SpanEvent`s to editor clients via `stone.clientRegistry.broadcastToType('editor', ...)`
  - `registerCommands(registry)`: `profiler:status`, `profiler:toggle` (calls `project.enableProfiling`/`disableProfiling`), `profiler:snapshot`
- [ ] Browser `build-progress-plugin.mjs` (at `libraries/shards.client/whet/plugins/`):
  - Subscribe to profiler WS events via Scry connection
  - On Start event for Generate: show "Building game.js..." with `estimatedDuration` from historical stats
  - On End event: show timing breakdown from child spans ("Generated in 5.1s: hash 20ms, deps 1.2s, build 3.8s, cache 100ms")
  - Fallback to polling `/api/profiler/spans?stone=<id>&active=true` if WS not connected
- [ ] Per-request span filtering: given a Serve span ID, walk descendants via parentId chain to get complete request profile
- [ ] Runtime toggle via Scry UI: wire up `profiler:toggle` command to editor UI
