---
# whet-p1bj
title: Data-driven workflow improvements (AudioDb migration)
status: completed
type: feature
priority: low
created_at: 2026-02-17T08:34:45Z
updated_at: 2026-04-07T12:10:42Z
parent: whet-juli
---

Migrate AudioDb to use the new StoneFactory base class (whet-6s58), replacing ad-hoc dynamic stone management:

- AudioDb extends StoneFactory instead of Router
- `createEntry(key, data)` replaces `_syncSingleStone` creation path
- `updateEntry(key, data, existing)` handles in-place config updates
- `addBaseRoutes()` adds the db.json route (replaces `getResults()` override)
- `syncStones()` expands groups then calls `this.sync(flatEntries, e => e.name)`
- Explicit stable stone IDs for ConfigStore compatibility
- Eliminates: `routes.length = 0` hack, `getResults()` override, manual stoneMap, orphan stones

Depends on StoneFactory (whet-6s58) which is now completed.


## Summary of Changes

### AudioDb.mjs (migrated)
- Now extends `StoneFactory` instead of `Router`
- `createEntry(key, data)` — creates the full AudioWav→AudioSox→Audio(ogg/m4a)→AudioMeta chain with explicit stable IDs (`audio:${key}:wav`, etc.)
- `updateEntry(key, data, existing)` — updates stone configs in-place, preserving cache
- `addBaseRoutes()` — routes the db.json file
- `syncStones()` — async: expands groups via `_expandGroups()`, then calls `this.sync(flatEntries, e => e.name)`
- `_expandGroups()` — extracted from old `syncStones`, flattens group+single entries into uniform array

### What was eliminated
- `this.routes.length = 0` hack
- `getResults()` override with lazy route building
- `this.stoneMap` manual Map management
- Orphan stones in `project.stones` on entry removal

### What was preserved (no changes needed)
- `GameAssets.mjs` — AudioDb is still a Router, same wiring works
- `AudioDbPlugin.mjs` — all accessed APIs preserved (`.db.data`, `.groupMatches`, `.syncStones()`, `.scanFiles()`, `.db.getSource()`)
- `AudioManagerTool.svelte` — no changes, talks through plugin WebSocket
- `addCommands()` method — kept for backward compat, was never auto-called (dead code)
