---
# whet-h63a
title: HTTP routes for direct binary asset serving
status: todo
type: task
created_at: 2026-02-17T08:34:15Z
updated_at: 2026-02-17T08:34:15Z
parent: whet-juli
blocked_by:
    - whet-flfg
---

Add HTTP endpoints to StoneInspectorPlugin for direct binary content access:

- GET /api/stones/ — list all stones (convenience, JSON)
- GET /api/stones/:id/source/:sourceId — serve raw binary output

This lets Scry display stone outputs as plain <img src=...>, <audio src=...>, <iframe src=...> elements instead of base64-encoding over WS. Much better for large assets.

Uses UwsServerStone's registerRoutes(app, stone, sendJson) plugin API.
