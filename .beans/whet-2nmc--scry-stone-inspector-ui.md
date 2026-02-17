---
# whet-2nmc
title: 'Scry: Stone Inspector UI'
status: draft
type: feature
priority: low
created_at: 2026-02-17T08:34:57Z
updated_at: 2026-02-17T08:34:57Z
parent: whet-juli
blocked_by:
    - whet-xito
    - whet-h63a
---

Build the Stone Inspector tool in Scry app (SvelteKit + Svelte 5 runes):

- Register as new tool: { id: 'stone-inspector', requiresWhet: true }
- StoneBridge: WS command wrapper following AudioBridge pattern (Promise-based req/res via sendServerCommand + requestId).
- State: stoneInspector.svelte.ts following audioDb.svelte.ts pattern.

UI components:
- Stone list panel (flat or grouped by type)
- Stone detail panel (config, outputs, dependencies)
- Multi-format output viewers (PNG/JPEG/WebP → image viewer, HTML → iframe, JSON → formatted viewer, audio → player, code → syntax highlight)
- Config editor for SharpStone (sliders for scale, blur, etc.)
- Live preview: edit config → see output update

Uses HTTP endpoints for binary content display (<img src=...> etc.) and WS for commands/config.

Key Scry files: src/lib/tools/stone-inspector/, src/lib/api/stone-bridge.ts, src/lib/tools/stone-inspector/state/stones.svelte.ts

This is the end-user-facing piece — Phase 7 of the plan.
