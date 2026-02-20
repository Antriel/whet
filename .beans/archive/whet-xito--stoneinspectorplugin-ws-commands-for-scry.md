---
# whet-xito
title: 'StoneInspectorPlugin: WS commands for Scry'
status: completed
type: feature
priority: normal
created_at: 2026-02-17T08:33:57Z
updated_at: 2026-02-19T09:28:51Z
parent: whet-juli
blocked_by:
    - whet-flfg
    - whet-a2d8
---

Create StoneInspectorPlugin.mjs as a ScryStone CommandRegistry plugin. WS commands:

- stones:list — calls project.describeStones()
- stones:list-outputs — calls listStoneOutputs(id)
- stones:get-source — calls getStoneSource(id, sourceId)
- stones:get-config — calls getStoneConfig(id)
- stones:set-config — calls setStoneConfig(id, patch, mode)
- stones:refresh — force regeneration and return result
- stones:preview — set-config + refresh + return output (convenience for live preview)

Lives in the game project's scry/ directory (not Whet core). Uses the same CommandRegistry pattern as AudioDbPlugin.

Wire into ScryDevTools constructor.

## Summary of Changes

- Created `scry/whetstones/plugins/StoneInspectorPlugin.mjs` in the shared scry submodule (scry-app). Implements 7 WS commands (`stones:list`, `stones:list-outputs`, `stones:get-source`, `stones:get-config`, `stones:set-config`, `stones:refresh`, `stones:preview`) and a binary HTTP route `GET /api/stones/*/source?sourceId=...` for streaming stone output.
- Added `enableStoneInspector(project)` method to `scripts/ScryDevTools.mjs` + import.
- Wired up with `scry.enableStoneInspector(p)` in the game `Project.mjs` (debug mode only).

Key design notes:
- `OutputMeta` (JSON): `{ sourceId, url, size }` — binary served via HTTP only, not WS
- `stones:preview` applies config as 'preview' mode (in-memory, changes hash → triggers regen); does not auto-clear
- `stones:refresh` uses hash-based caching (no forced bypass in V1)
- Binary serving follows the `UwsServerStone.serveRouteResult` pattern with full backpressure handling
