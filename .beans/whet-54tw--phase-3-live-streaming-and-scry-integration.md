---
# whet-54tw
title: 'Phase 3: Live Streaming and Scry Integration'
status: completed
type: feature
priority: normal
created_at: 2026-03-28T06:51:38Z
updated_at: 2026-04-01T10:53:51Z
parent: whet-mosz
blocked_by:
    - whet-j8n9
---

Integrate profiling with Scry for live dev server observability.

### Prerequisites (in ScryStone, not Whet core)

- [x] Store `clientRegistry` as instance property on ScryStone (currently local in `serve()`)

### Deliverables

- [x] `ProfilerPlugin` for ScryStone (at `scry/whetstones/plugins/ProfilerPlugin.mjs`):
  - `registerRoutes(app, stone, sendJson)`: instanceof assertion for ScryStone access to `clientRegistry`
  - REST: `/api/profiler/summary`, `/api/profiler/export?format=trace`, `/api/profiler/spans?since=<ts>`
  - WS: subscribe to profiler events, broadcast Start + End `SpanEvent`s to editor clients via `stone.clientRegistry.broadcastToType('editor', ...)`
  - `registerCommands(registry)`: `profiler:status`, `profiler:toggle` (calls `project.enableProfiling`/`disableProfiling`), `profiler:snapshot`
- [x] Browser `build-progress-plugin.mjs` (at `libraries/shards.client/whet/plugins/`):
  - Subscribe to profiler WS events via Scry connection
  - On Start event for Generate: show "Building game.js..." with `estimatedDuration` from historical stats
  - On End event: show timing breakdown from child spans ("Generated in 5.1s: hash 20ms, deps 1.2s, build 3.8s, cache 100ms")
- [x] Per-request span filtering: given a Serve span ID, walk descendants via parentId chain to get complete request profile
- [x] Runtime toggle via Scry UI: wire up `profiler:toggle` command to editor UI

## Summary of Changes

**ScryStone.mjs** — `clientRegistry` promoted to `this.clientRegistry` instance property so plugins can broadcast to connected editor clients.

**ProfilerPlugin.mjs** (`scry/whetstones/plugins/`) — New plugin for ScryStone:
- REST: `/api/profiler/summary`, `/api/profiler/export?format=json|trace`, `/api/profiler/spans?since=<id>`, `/api/profiler/request?spanId=<id>` (descendant walk)
- WS: subscribes to `project.profiler.subscribe()` and broadcasts `profiler:span` events to editor clients
- Commands: `profiler:status`, `profiler:toggle` (enables/disables + manages subscription), `profiler:snapshot`

**build-progress-plugin.mjs** (`libraries/shards.client/whet/plugins/`) — Browser DevClient plugin:
- Listens for `profiler:span` WS events
- On Generate start: shows bottom-right overlay "Building {stone}... (~Xs)"
- On Generate end: replaces with "Generated {stone} in Xs: hash Xms, deps Xs, build Xs, cache Xms" (auto-clears after 4s)
- Tracks child spans by walking parentId chain through active spans

**Scry app** (`src/lib/`) — New Profiler tool:
- `profiler-bridge.ts`: `ProfilerBridge` extends `RequestBridge` for `profiler:status/toggle/snapshot` commands
- `tools/profiler/index.ts` + `ProfilerTool.svelte`: toggle button wired to `profiler:toggle`, reflects current enabled state on connect
- `ToolSidebar.svelte`: added `Activity` icon for the profiler tool
