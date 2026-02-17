---
# whet-xito
title: 'StoneInspectorPlugin: WS commands for Scry'
status: todo
type: feature
created_at: 2026-02-17T08:33:57Z
updated_at: 2026-02-17T08:33:57Z
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
