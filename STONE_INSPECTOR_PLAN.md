# Stone Inspector & Dynamic Configuration Plan

## Vision

Enable Scry (and any external tool) to:
1. Discover and browse all Stones in a running Whet project
2. View the output of any Stone regardless of type (PNG, HTML, JSON, etc.)
3. Modify Stone configuration at runtime and see results immediately
4. All while Whet remains fully functional standalone (`npx whet publish` works without Scry)

---

## Key Context (for future sessions)

### Architecture Summary

- **Whet** is a Node.js build tool written in Haxe, compiled to JS ES6 modules. Core concept: everything is a **Stone** (asset, build, server, config).
- **Stones** are runtime objects, each with a `config`, `id` (string, from class name or explicit), and `generate()` method returning `Promise<Array<SourceData>>`.
- **Routers** compose Stones, applying glob filtering and path remapping. They are the main way to query Stone outputs.
- **Source/SourceData** represents generated output. SourceData has `id` (relative path), `data` (Buffer), `hash` (SHA-256).
- **CacheManager** handles caching (InMemory, InFile, AbsolutePath, None) with durability policies. Hash-based invalidation.
- **Project** is the top-level container. Stones auto-register into `project.stones[]` on construction. Projects can have CLI options and an `onInit` hook.

### Current State of Stone Identity

- `stone.id` is a string, derived from `config.id` or the JS class name (e.g. `"SharpStone"`, `"Files"`).
- **IDs are NOT unique** - multiple SharpStone instances all get id `"SharpStone"`. Only explicit `config.id` creates distinct names.
- `project.stones` is a flat array of all stones. No registry, no lookup by unique key.
- The Server stone's POST handler already does `project.stones.find(s -> s.id == stoneId)` - but this only works if IDs are unique.
- FileCache keys entries by `stone.id`, so non-unique IDs cause cache collisions (currently works because most stones with file caching have unique enough IDs in practice).

### Current External Tool Integration

- **Server stone** (`src/whet/stones/Server.hx`): HTTP-only. GET serves files, PUT executes CLI commands, POST modifies stone config and optionally returns source as base64 JSON. No WebSocket.
- **ScryStone** (game project, extends UwsServerStone): uWebSockets.js-based HTTP+WS server. Has a `CommandRegistry` plugin system where plugins register WS command handlers. Manages client registry (editors, previews).
- **AudioDb** (game project): Extends Router, dynamically creates Stones from a JSON database. Has `syncStones()` that recreates routes when DB changes. Exposes CLI commands (`audio-db-add`, `audio-db-set`, `audio-db-flush`). Scry's `AudioDbPlugin` registers WS commands for it.

### Dynamic Data Pain Points (AudioDb pattern)

- AudioDb reads a JSON file at startup, creates Stone instances per entry (AudioWav -> AudioSox -> Audio for each audio file).
- Adding/modifying entries requires `syncStones()` which clears and rebuilds routes.
- The JSON is external state that must be kept in sync with Stone graph.
- Editing config (e.g. compression settings) requires restarting the server currently.
- SharpStone operations are baked into the script - changing blur/scale/trim requires editing Project.mjs and restarting.

### File Locations

| What | Where |
|------|-------|
| Whet core | `C:\Users\peter\Dropbox\work\NextRealm\whet\` |
| Stone base class | `src/whet/Stone.hx` |
| Project | `src/whet/Project.hx` |
| Server stone | `src/whet/stones/Server.hx` |
| Router | `src/whet/route/Router.hx` |
| Cache system | `src/whet/cache/` |
| StoneId magic | `src/whet/magic/StoneId.hx` |
| Example game project | `C:\Users\peter\Dropbox\work\reboot\gooye-2\` |
| Game Project.mjs | `gooye-2\Project.mjs` |
| GameAssets.mjs | `gooye-2\scripts\GameAssets.mjs` |
| AudioDb.mjs | `gooye-2\libraries\shards.client\whet\assets\AudioDb.mjs` |
| SharpStone.mjs | `gooye-2\libraries\shards.client\whet\assets\SharpStone.mjs` |
| ScryStone.mjs | `gooye-2\scry\whetstones\ScryStone.mjs` |
| ScryDevTools.mjs | `gooye-2\scripts\ScryDevTools.mjs` |

---

## Phase 1: Unique Stone Identity

**Goal**: Every Stone gets a stable, unique identifier that works across processes.

### Problem

Stone IDs default to class name. Multiple instances of the same class (e.g. 5 SharpStones) all share the ID `"SharpStone"`. This makes it impossible to reference a specific Stone from an external tool.

### Approach

**Auto-generate unique IDs** when not explicitly provided, by appending a counter:

```
SharpStone        (first instance)
SharpStone:2      (second instance)
SharpStone:3      (third instance)
```

Changes needed in `Stone.hx` constructor:
- After determining the base ID (from config.id or class name), check `project.stones` for collisions.
- If collision found and no explicit `config.id`, append `:N` suffix.
- If collision found and explicit `config.id` was given, warn (or error).

### Considerations

- **Cache compatibility**: FileCache keys by `stone.id`. Changing IDs would invalidate existing caches. Mitigation: only new stones (without explicit IDs) get the new behavior. Existing explicit IDs are unchanged.
- **Stability across restarts**: Auto-IDs depend on instantiation order. If Project.mjs doesn't change, order is stable. If stones are added/removed, IDs shift. This is acceptable for dev-time tooling. For persistent references, users should set explicit `config.id`.
- **Alternative: require explicit IDs for inspectable stones**: Simpler but more burden on users. Not preferred.
- **Alternative: use WeakMap with integer keys**: Avoids string collision issues but IDs aren't human-readable. Not preferred.

### Deliverables

1. Modify `Stone.hx` constructor to auto-deduplicate IDs.
2. Add a `project.getStone(id)` lookup method.
3. Add a `project.listStones()` method returning `Array<{id, className, outputFilter}>`.

### Open Questions

- Should the separator be `:` or something else? (`:` is already used in `toString()` as `id:ClassName`)
- Should we add a `label` field to StoneConfig for human-friendly display names separate from the ID? E.g. `"char-frames-scaler"` vs `"SharpStone:2"`.
- Do we want to maintain ID stability via a `.whet/stone-ids.json` mapping file? This would map `(className, constructionOrder) -> stableId` and persist across restarts. More robust but adds complexity.

---

## Phase 2: Stone Introspection API

**Goal**: Provide a way to query the Stone graph and individual Stone metadata from external tools.

### API Design

Add to `Project.hx` (or a new `StoneRegistry` helper):

```javascript
// List all stones with metadata
project.describeStones() → [{
    id: "SharpStone:2",
    className: "SharpStone",
    label: "char-frames",          // optional human label
    outputFilter: { extensions: ["png", "webp"] },
    cacheStrategy: "InFile",
    dependencyIds: ["audio.json"],  // IDs of dependency stones
    configSchema: { ... },          // optional, for UI generation
}]

// Get stone outputs (list without generating)
project.getStoneOutputs(stoneId) → ["sprite1.png", "sprite2.png", ...]

// Get stone source data
project.getStoneSource(stoneId, sourceId?) → Source

// Force regeneration
project.refreshStone(stoneId) → Source
```

### Config Description

For Scry to render UI controls for Stone configuration, it needs to know what config fields exist and their types. Options:

**Option A: Convention-based** - Stones declare a `describeConfig()` method returning field metadata:
```javascript
describeConfig() {
    return {
        operations: { type: 'pipeline', items: ['extract','scale','trim','blur','outline'] },
        keepOriginalIfNoOps: { type: 'boolean', default: true },
    }
}
```

**Option B: Schema from JSDoc/TypeScript** - Extract config types from JSDoc typedefs at build time. More automatic but harder to implement.

**Option C: Reflect on config** - Just send the current config object and let Scry infer UI from the shape of the data. Quick and dirty, works for many cases.

**Recommendation**: Start with Option C (send raw config), add Option A for stones that need rich UI controls (like SharpStone's operation pipeline).

### Deliverables

1. `project.describeStones()` method.
2. `project.getStoneOutputs(id)` method.
3. `project.getStoneSource(id, sourceId?)` method.
4. `project.refreshStone(id)` method.
5. Optional: `stone.describeConfig()` for rich UI.

---

## Phase 3: WS-Based Inspector Protocol

**Goal**: Scry can discover and interact with Stones over WebSocket in real time.

### Why WebSocket (not HTTP)

- Stone generation can be slow (image processing, Haxe compilation). WS allows streaming progress updates.
- Scry already has WS infrastructure via ScryStone's CommandRegistry.
- Enables push notifications: when a Stone regenerates (e.g. source file changed), Scry can be notified instantly.

### Protocol Design

Commands registered via ScryStone's existing `CommandRegistry`:

```javascript
// Discovery
{ cmd: "stones:list" }
→ { stones: [{ id, className, label, outputFilter, cacheStrategy }] }

// Inspect a stone's outputs
{ cmd: "stones:list-outputs", stoneId: "SharpStone:2" }
→ { outputs: ["sprite1.png", "sprite2.png"] }

// Get a stone's source data (single output)
{ cmd: "stones:get-source", stoneId: "SharpStone:2", sourceId: "sprite1.png" }
→ { sourceId: "sprite1.png", mimeType: "image/png", data: "<base64>", hash: "abc123" }

// Get stone config
{ cmd: "stones:get-config", stoneId: "SharpStone:2" }
→ { config: { operations: { scale: { width: 280 } }, ... } }

// Update stone config (temporary, in-memory only)
{ cmd: "stones:set-config", stoneId: "SharpStone:2", config: { operations: { scale: { width: 150 } } } }
→ { ok: true }

// Force regeneration and get result
{ cmd: "stones:refresh", stoneId: "SharpStone:2" }
→ { outputs: [...], hash: "def456" }

// Get stone config + refresh + return output (convenience for live preview)
{ cmd: "stones:preview", stoneId: "SharpStone:2", sourceId: "sprite1.png", config: { ... } }
→ { data: "<base64>", hash: "..." }
```

### Where This Lives

**Option A: In Whet core** - Add a built-in `InspectorStone` or `InspectorPlugin` to Whet itself. Any Stone-based server could opt into it.

**Option B: In ScryStone** - Add as a ScryStone plugin (like AudioDbPlugin). Scry-specific.

**Recommendation**: Phase 3 implements as a **Scry plugin** (Option B) since the WS infrastructure is already there. Phase 5 (future) could promote the HTTP subset to Whet core.

### Implementation

New file: `scry/whetstones/plugins/StoneInspectorPlugin.mjs`

UwsServerStone plugins can implement both `registerCommands(registry)` for WS and `registerRoutes(app, stone, sendJson)` for HTTP. The Stone Inspector uses both:

```javascript
export default class StoneInspectorPlugin {
    constructor(project) {
        this.project = project;
    }

    // WS commands for interactive operations
    registerCommands(registry) {
        registry.on('stones:list', () => this.project.describeStones());
        registry.on('stones:list-outputs', (data) => this.project.getStoneOutputs(data.stoneId));
        registry.on('stones:get-config', (data) => this.getConfig(data));
        registry.on('stones:set-config', (data) => this.setConfig(data));
        registry.on('stones:preview', (data) => this.preview(data));
        // ...
    }

    // HTTP routes for direct binary content access (images, audio, etc.)
    registerRoutes(app, stone, sendJson) {
        // GET /api/stones/ - list all stones (convenience)
        app.get('/api/stones/', (res) => sendJson(res, this.project.describeStones()));

        // GET /api/stones/:id/source/:sourceId - serve raw output (for <img src=...>)
        app.get('/api/stones/*', (res, req) => {
            // Parse stoneId and sourceId from URL, fetch and serve binary
        });
    }
}
```

The HTTP routes let Scry display Stone outputs as plain `<img>` / `<audio>` / `<iframe>` elements pointing at URLs, avoiding base64 encoding entirely.

### Deliverables

1. `StoneInspectorPlugin.mjs` with WS commands + HTTP routes.
2. Wire into ScryDevTools constructor.
3. HTTP endpoints for binary content (images, audio) - no base64 needed.

### Open Questions

- Should config changes be persisted? Or always temporary (lost on restart)? Temporary is safer and simpler for now.
- How to handle Stones that take a long time to generate? Should we add progress events? (`stones:progress { stoneId, percent, message }`)
- Should we send diffs for large sources? Or always full base64?

---

## Phase 4: Dynamic Stone Configuration

**Goal**: Allow external tools to modify Stone config at runtime, with results visible immediately.

### The Core Problem

Currently, Stone configuration is set in Project.mjs at startup:

```javascript
const charFrames = new SharpStone({
    pngs: new Router([['/', 'assets/qwen-outputs/char-frames/', '**/*.png']]),
    operations: { scale: { width: 280 } }
});
```

Changing `width: 280` to `width: 150` requires editing the file and restarting the server.

### Approach: Config Overlay System

Add a **config overlay** mechanism. The base config stays as defined in Project.mjs. External tools can apply temporary overlays that override specific fields:

```
Effective config = base config ← overlay
```

When overlay is removed, config reverts to base. Overlays are in-memory only (not persisted).

### Implementation

Add to `Stone.hx`:

```haxe
// Store original config for revert
var baseConfig:T;

// Apply a partial config overlay
public function applyOverlay(partial:Dynamic):Void {
    if (baseConfig == null) baseConfig = cloneConfig(config);
    mergeInto(config, partial);
    invalidateCache();
}

// Revert to base config
public function revertConfig():Void {
    if (baseConfig != null) {
        config = baseConfig;
        baseConfig = null;
        invalidateCache();
    }
}

// Invalidate current cached output so next getSource() regenerates
private function invalidateCache():Void {
    // Implementation depends on cache strategy.
    // For InMemory: remove from memory cache.
    // For InFile: mark as stale (don't delete files, just force regen).
    cache.invalidate(this);
}
```

### Cache Invalidation Concern

When config changes, the hash changes, so the cache naturally misses. But we need:
1. `CacheManager.invalidate(stone)` - clear cached entries for a stone.
2. Or simply rely on hash mismatch (existing behavior) - if hash changes, cache won't match, and a new generation happens. Old cached entries get evicted by durability rules.

Option 2 (relying on hash mismatch) is simpler and already works. The only issue is that old cached versions linger until evicted. For dev tooling, this is fine.

### SharpStone-Specific: Live Image Preview

The killer use case: modify SharpStone operations and see the result on a specific image immediately.

Workflow in Scry:
1. Browse stones, select a SharpStone.
2. See list of input images.
3. Select an image, see current output.
4. Modify operations (e.g. change blur sigma via slider).
5. See updated output in real time.

For this to be fast:
- Use `stones:preview` command that takes config + specific sourceId.
- Apply config temporarily, generate only the requested sourceId.
- Don't regenerate the entire stone's output (could be 100+ images).

This requires a **per-source generation** capability:

```javascript
// Generate only one specific output from a stone
stone.generateSingle(sourceId, configOverlay?) → SourceData
```

SharpStone already has `getSources()` which resolves per-image pipelines. We'd add:

```javascript
async generateSingle(sourceId, configOverlay) {
    const savedConfig = this.config;
    if (configOverlay) Object.assign(this.config, configOverlay);
    try {
        const sources = await this.getSources();
        const target = sources.find(s => s.serveId === sourceId);
        if (!target) throw new Error(`Source ${sourceId} not found`);
        // Process just this one image
        const result = await this.processImage(target.source.data, target.pipeline, target.outputs, target.serveId);
        return result;
    } finally {
        this.config = savedConfig;
    }
}
```

### Deliverables

1. Config overlay system in `Stone.hx` (or as a mixin for JS stones).
2. `CacheManager.invalidate(stone)` method.
3. Per-source generation for SharpStone (`generateSingle`).
4. Update `StoneInspectorPlugin` to use overlay system.

### Open Questions

- Should overlays stack? (Multiple overlays from different tools) Probably not needed initially.
- Should the overlay be a deep merge or shallow? Deep merge is more useful for nested configs like SharpStone operations.
- Should we add an "undo" stack for overlays? Could be nice for Scry UI but adds complexity.
- How does this interact with Stones that have side effects (e.g. HaxeBuild running the compiler)? Config overlay on a build stone could trigger an expensive recompile. Might want to exclude certain stone types from config modification.

---

## Phase 5: Improving the Dynamic Data Pattern

**Goal**: Make it natural for Stones to be driven by external data (like AudioDb's JSON) with proper caching, hot-reload, and external editability.

### Current AudioDb Pattern - What Works and What Doesn't

**Works:**
- JSON file as source of truth for what audio to process.
- CLI commands to add entries and flush.
- Scry plugin for WS-based editing.

**Doesn't work well:**
- `syncStones()` creates/destroys Stone instances at runtime. This breaks assumptions (stones registered once at startup).
- Route array is cleared and rebuilt on every sync.
- No proper invalidation - relies on clearing `routes.length = 0` as cache bust.
- The pattern is manual and ad-hoc, not something Whet supports natively.

### Proposed: DataDrivenStone Pattern

A new abstract stone type that formalizes the "generate stones from data" pattern:

```javascript
class DataDrivenStone extends Stone {
    constructor(config) {
        super(config);
        // config.dataSource: Stone | Router that provides the "database" (JSON, etc.)
        // config.createStones: (data) => Map<string, Stone> - factory function
    }

    async syncFromData() {
        const data = await this.config.dataSource.getSource();
        const parsed = JSON.parse(data.data[0].data.toString());
        this.childStones = this.config.createStones(parsed);
        // Update routes, invalidate caches
    }
}
```

**However**, this might be over-engineering. The real issues are:

1. **Editing data externally should trigger re-sync automatically.**
2. **Adding/removing entries shouldn't require restart.**
3. **Per-entry config changes should regenerate only affected outputs.**

### Simpler Alternative: Observable Config + File Watching

Instead of a new Stone type, improve the existing primitives:

1. **File watching**: When AudioDb's JSON changes on disk, automatically call `syncStones()` and invalidate.
2. **Config change events**: When a Stone's config is modified (via overlay or directly), emit an event that dependents can listen to.
3. **Selective regeneration**: When one entry in AudioDb changes, only regenerate that entry's stones.

### Implementation Sketch

```javascript
// In AudioDb or similar:
class AudioDb extends Router {
    async loadDb(jsonDbPath) {
        // ... existing code ...

        // Watch the JSON file for changes
        this.watcher = fs.watch(this.db.cwdPath(jsonDbPath), async () => {
            const newData = await readFile(this.db.cwdPath(jsonDbPath), 'utf-8');
            this.db.data = JSON.parse(newData);
            await this.syncStones();
            // Notify any listeners (e.g. Scry) that data changed
            this.emit('dataChanged');
        });
    }
}
```

For Whet core, add a **simple event emitter** to Stone:

```haxe
// In Stone.hx
public var onChange:Array<Void->Void> = [];

function notifyChange():Void {
    for (cb in onChange) cb();
}
```

### Deliverables

1. File watching utility in Whet core (opt-in per stone).
2. Simple `onChange` event on Stone.
3. Refactor AudioDb to use file watching.
4. SharpStone: support `.meta.json` sidecar files with file watching for per-asset config.

### Open Questions

- Should file watching be in Whet core or left to user-space? Core is cleaner but increases scope.
- How granular should change events be? Per-stone is simple. Per-source-entry is harder but more efficient for large datasets.
- Should we support non-file data sources (e.g. a REST API, a database)? Probably not in scope.

---

## Phase 6: Scry Stone Inspector UI

**Goal**: Build the actual UI in Scry for browsing and inspecting Stones.

### UI Design (High Level)

```
┌─────────────────────────────────────────────────────┐
│ Stone Inspector                                      │
├──────────────┬──────────────────────────────────────┤
│ Stone List   │ Stone Detail                          │
│              │                                       │
│ ▸ Project    │ SharpStone:2 "char-frames"            │
│ ▸ JsonStone  │                                       │
│ ▸ SharpStone │ Config:                               │
│ ▾ SharpSt:2  │   operations: { scale: { w: 280 } }  │
│ ▸ SharpSt:3  │   [Edit Config]                       │
│ ▸ OxiPng     │                                       │
│ ▸ AudioDb    │ Outputs (12 files):                   │
│ ▸ GameBundle │   ☐ char-idle-1.png    12KB           │
│ ▸ HaxeBuild  │   ☐ char-idle-2.png    14KB           │
│              │   ☐ char-run-1.png     11KB            │
│              │   ...                                  │
│              │                                       │
│              │ Preview:                               │
│              │   [char-idle-1.png rendered]           │
│              │                                       │
│              │ Operations Editor:                     │
│              │   Scale width: [====280====]           │
│              │   Trim: [x]                           │
│              │   Blur sigma: [====0.0====]           │
│              │   [Apply] [Revert]                    │
└──────────────┴──────────────────────────────────────┘
```

### Viewer Types

Based on Stone output MIME type, show appropriate viewer:
- **PNG/JPEG/WebP/AVIF**: Image viewer with zoom, pixel inspector
- **HTML**: Iframe preview
- **JSON**: Formatted JSON viewer with syntax highlighting
- **JS/CSS**: Code viewer
- **Audio (OGG/M4A)**: Audio player with waveform
- **Binary/ZIP**: Hex viewer, file listing
- **Unknown**: Raw hex + size info

### Implementation

This is Scry-side work (not Whet). Scry already has an Electron/web UI. The Stone Inspector would be a new panel/tool.

### Deliverables

1. Stone list panel (tree view grouped by type or flat list).
2. Stone detail panel (config, outputs, dependencies).
3. Output viewer (multi-format).
4. Config editor for SharpStone (sliders for scale, blur, etc.).
5. Live preview: edit config -> see output update.

---

## Milestone Summary

| Phase | What | Where | Depends On |
|-------|------|-------|------------|
| **1** | Unique Stone IDs | Whet core (`Stone.hx`) | - |
| **2** | Stone Introspection API | Whet core (`Project.hx`) | Phase 1 |
| **3** | WS Inspector Protocol | Scry plugin | Phase 2 |
| **4** | Dynamic Config (overlays) | Whet core + SharpStone | Phase 2 |
| **5** | Dynamic Data Improvements | Whet core + AudioDb | Phase 1 |
| **6** | Scry Inspector UI | Scry app | Phase 3 + 4 |

Phases 3, 4, 5 can be worked on in parallel after Phase 2.

### Minimum Viable Path to "view and tweak PNGs in Scry"

1. Phase 1 (unique IDs) - small, ~1-2 hours
2. Phase 2 (introspection API) - medium, ~2-4 hours
3. Phase 3 (WS protocol) - medium, ~2-4 hours
4. Phase 4 (config overlays + SharpStone single preview) - medium, ~3-5 hours
5. Phase 6 subset (basic list + image viewer + SharpStone controls) - larger, Scry-side

---

## Risks and Mitigations

### Risk: Auto-generated IDs are unstable across restarts
**Mitigation**: Document that users should set explicit `config.id` on Stones they want to reference persistently. Auto-IDs are fine for browsing/inspection.

### Risk: Config overlays cause subtle bugs
**Mitigation**: Overlays are always temporary and revertible. Never persisted. Add a `stone.hasOverlay` flag for UI indication.

### Risk: Per-source generation is hard for some Stone types
**Mitigation**: Start with SharpStone only (it already has per-image processing). Other stones can add `generateSingle` as needed. Default behavior: regenerate entire stone.

### Risk: Large base64 responses over WebSocket are slow
**Mitigation**: For Phase 3, base64 is fine (images are typically <1MB). For Phase 6, consider binary WS frames or HTTP range requests for large assets.

### Risk: Cache invalidation complexity
**Mitigation**: Rely on hash mismatch (natural cache miss) rather than explicit invalidation. This is already how Whet works - if config changes, hash changes, cache misses, stone regenerates.

---

---

## Scry App Architecture & Integration Analysis

### How Scry Currently Works

**Tech stack**: Tauri (Rust backend) + SvelteKit + Svelte 5 runes for state management.

**Whet server lifecycle** (Rust side, `src-tauri/src/commands/whet.rs`):
- Scry spawns Whet as a child process: `npx whet --no-pretty serve`
- Sets working directory to the game project path
- Parses Whet's stdout JSON logs, waiting for `"scry_server_ready"` log line to extract the port
- Streams remaining stdout/stderr to Scry's console via Tauri events (`whet-stdout`, `whet-stderr`)
- Process management: start, stop, restart, is_running commands

**Connection state** (`src/lib/state/connection.svelte.ts`):
- Tracks: `running`, `url`, `port`, `error`, `wsConnected`, `wsError`
- URL derived from port: `http://localhost:{port}`
- WS URL derived in PreviewBridge: `ws://localhost:{port}/scry`

**Communication layers**:
1. **HTTP** (`whet-api.ts`): `fetchProjectConfig()` (GET /api/config), `checkWhetHealth()` (GET /api/health), `fetchResolvedLayouts()` (GET assets path)
2. **WebSocket** (`scrystone-client.ts` -> `preview-bridge.ts`): Singleton `PreviewBridge` manages the WS connection. Identifies as `"editor"` client type. Sends commands to preview clients and receives events.
3. **WS Request/Response** (`audio-bridge.ts`): Promise-based wrapper over WS. Uses `requestId` correlation for `sendServerCommand` -> `onResponse` pattern. 30s timeout per request.

**Tool system** (`src/lib/tools/`):
- Self-registering tools via `registerTool()` in a central registry
- Each tool: `{ id, name, icon, description, requiresProject, requiresWhet, component }`
- Tools can declare they need Whet (grayed out if not running)
- Cross-tool navigation via `openFileInTool(toolId, filePath)`
- Currently existing tools: `layout-editor`, `audio-manager`, `frame-aligner`

**AudioDb integration as reference pattern** (most complete Scry<->Whet integration):
- Whet side: `AudioDbPlugin.mjs` registers WS commands (`audio:load`, `audio:set`, `audio:flush`, `audio:add`, `audio:scan`, `audio:add-group`)
- Scry side: `AudioBridge` class wraps WS calls with Promise-based request/response
- State: `audioDb.svelte.ts` manages entries, dirty state, metadata cache
- UI: `AudioManagerTool.svelte` with list, config panels, player, modals

### What This Means for the Plan

**Good news - the architecture is already well-suited:**

1. **Tool registration is trivial**: Stone Inspector would be a new tool registered as `{ id: 'stone-inspector', requiresWhet: true }`. The tool system handles enabling/disabling based on Whet status.

2. **The AudioBridge pattern is the exact template**: Create a `StoneBridge` class (like AudioBridge) that wraps WS commands with Promise-based req/res. The `sendServerCommand` + `requestId` correlation already works perfectly.

3. **State management pattern is clear**: Create `stoneInspector.svelte.ts` following the same pattern as `audioDb.svelte.ts` - private `$state`, exported getters/actions, async actions that call the bridge.

4. **WS infrastructure is shared**: `StoneBridge` would use `getPreviewBridge().getClient()` just like `AudioBridge` does. No new connections needed.

**Improvements the plan enables:**

1. **Generalize the AudioBridge pattern**: AudioBridge is tightly coupled to `audio:*` commands. The `StoneBridge` could be generic, handling any `stones:*` command. This also means AudioDb could eventually be viewed through the Stone Inspector as just another Stone, not a special case.

2. **The `whet-stdout` event stream could carry stone change notifications**: When Whet regenerates a Stone, it logs it. Scry already streams stdout. We could add structured events (not just logs) that Scry parses to know when to refresh the inspector view. But WS push notifications (Phase 3) are cleaner.

3. **HTTP routes for direct asset access**: UwsServerStone's plugin system supports both `registerCommands` (WS) and `registerRoutes` (HTTP). The StoneInspectorPlugin can expose HTTP endpoints like `GET /api/stones/:id/source/:sourceId` so Scry can display images as plain `<img src="...">` instead of base64 blobs. WS for commands/config, HTTP for binary content - best of both worlds.

**Key Scry-side files for implementation:**

| File | Purpose |
|------|---------|
| `src/lib/tools/stone-inspector/index.ts` | Tool registration |
| `src/lib/tools/stone-inspector/StoneInspector.svelte` | Main tool component |
| `src/lib/tools/stone-inspector/state/stones.svelte.ts` | Stone list & selection state |
| `src/lib/api/stone-bridge.ts` | WS command wrapper (like AudioBridge) |
| `src/lib/tools/stone-inspector/components/` | StoneList, StoneDetail, OutputViewer, ConfigEditor, ImagePreview |

**Additional Scry-side context:**
- App directory: `C:\Users\peter\Dropbox\work\NextRealm\scry-app\`
- Framework: SvelteKit + Svelte 5 runes
- State pattern: `$state` + getter functions + action functions
- Styling: Tailwind CSS
- UI components: `ResizableSplitPane`, `ToastContainer`, `ConfirmDialog` available in `$lib/components/shared/`

---

## Non-Goals (for now)

- **Persisting config changes**: Editing Project.mjs from Scry. Too risky, too complex.
- **Stone creation at runtime**: Adding new Stones from Scry. The Stone graph is defined in Project.mjs.
- **Multi-user collaboration**: Single Scry instance per project.
- **Version control for configs**: Undo history, branches. Keep it simple.
- **File system watching in Whet core**: Nice to have but not blocking the inspector.
