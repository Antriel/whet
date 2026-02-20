---
# whet-h63a
title: HTTP routes for direct binary asset serving
status: completed
type: task
priority: normal
created_at: 2026-02-17T08:34:15Z
updated_at: 2026-02-19T09:42:39Z
parent: whet-juli
blocked_by:
    - whet-flfg
---

Add HTTP endpoints to StoneInspectorPlugin for direct binary content access:

- GET /api/stones/ — list all stones (convenience, JSON)
- GET /api/stones/:id/source/:sourceId — serve raw binary output

This lets Scry display stone outputs as plain <img src=...>, <audio src=...>, <iframe src=...> elements instead of base64-encoding over WS. Much better for large assets.

Uses UwsServerStone's registerRoutes(app, stone, sendJson) plugin API.

## Work Plan

- [x] Add `GET /api/stones/` list endpoint to `registerRoutes`
- [x] Update class JSDoc to document the new route

## Summary of Changes

Added `GET /api/stones/` HTTP endpoint to `StoneInspectorPlugin.registerRoutes`:

- Uses `stone.registerApiRoute` to handle both `/api/stones/` and redirect from `/api/stones`
- Calls `this.project.describeStones()` and returns the result via `sendJson`
- Registered before the existing `GET /api/stones/*/source` route (exact match wins over wildcard)
- Updated class JSDoc to document the new route
