# Scry Editor Integration Review

Scope: `scry/whetstones/` (ScryStone, UwsServerStone, plugins) as vendored in
`gooye-2`, plus the editor side in `scry-app/src/lib/tools/stone-inspector/`.

## Overall assessment

For "vibe-coded", the layering is right where it matters:

- **Whet core owns the semantics.** `Project.getStoneConfig` builds the
  editable/fixed/meta envelope, `ConfigStore` owns baseline-capture + patch merge +
  preview-vs-persist. `StoneInspectorPlugin` is mostly transport (WS/HTTP framing,
  URL building, binary streaming) — which is exactly what a plugin should be.
- **The plugin contract** (`init(stone)`, `registerCommands(registry)`,
  `registerRoutes(app)`, `registerConfig(cfg)`) is simple and has proven extensible
  (nine plugins, including project-specific ones like `PlaytestPlugin` living in the
  game repo). It deserves a short written contract doc in the scry repo; today it's
  learn-by-example.
- The **Stone Inspector** flow (envelope → stone-specific editor → flat patch →
  preview/persist) is clean, and the editor-side CLAUDE.md files are good.

## Recommendations

### 1. Move the generic CLI verbs into whet core

`ScryStone.addCommands` registers `stones`, `refresh`, `stone-outputs`, `stone-cat`,
`stone-config`, `stone-source`, `find-outputs` — none of which need the server; they
only need `Project`. Hosting them on ScryStone means:

- Projects without Scry (whet's own `example/`, future non-game uses) lack the verbs.
- The `whet` skill has to hedge about their availability.
- `find-outputs` logic is **duplicated** nearly line-for-line between
  `ScryStone.addCommands` and `StoneInspectorPlugin.handleFindOutputs`
  (ext-normalization + compound-extension matching + output-filter overlap test).

Concrete move: a core module (e.g. `whet.Introspect` or commands registered by
`Project` itself behind a flag) providing both the CLI verbs and plain-function
equivalents (`project.findOutputs(exts)`, already-existing `describeStones()` etc.)
that `StoneInspectorPlugin` then calls. ScryStone keeps only `serve`-related commands.

### 2. Move stone-origin tracking into core (opt-in)

`stoneSourceTracking.mjs` patches stone construction to record `__originStack`, and
must be imported before any stone — a fragile convention enforced only by a comment in
`Project.mjs`. If whet core captured origins natively (flag on `Project` config, or
`WHET_STONE_ORIGINS` env, default on — cost is one `Error().stack` per stone at init),
then:

- `Project.describeStones()` could include origins directly (today the plugin merges
  `__originStack` in by hand),
- `stone-source` works everywhere,
- the "must precede any stone" import footgun disappears.

### 3. Give `CacheStrategy` a core pretty-printer

`StoneInspectorPlugin.formatHaxeEnum` reaches into `$hxEnums` via
`whet/bin/genes/Register.js` to render cache strategies — a deep coupling to compiled
internals that will break silently on a genes/Haxe upgrade. Whet should expose
`CacheStrategy.toNiceString()` (or make `describeStones` return the display string);
the plugin's comment already notes `Std.string` truncates at ~5 levels, so this is a
real need, solved at the wrong layer.

### 4. `uiHints` is dead weight — or the seed of schemas

`StoneConfigMeta.uiHints` exists in core but nothing sets or reads it (checked
scry-app + whetstones). Either delete it, or make it the carrier for per-class
**config schemas** (doc 03 §"Config schemas"), which would let the editor generate
forms for simple stones instead of hand-writing a Svelte editor per class
(`SharpConfigEditor` is the only one today — every new tunable stone type currently
costs an editor component).

### 5. Smaller notes

- `StoneInspectorPlugin.describeStones` and `handleGraph` both build on core calls —
  good. `handleGraph`'s edge set inherits the `fixed`-detection gaps noted in doc 01 §5.
- `stone-cat`'s binary refusal (size + sha256 + cached path to stderr, exit 1) is
  excellent agent ergonomics; same for `refresh`'s long self-hash-aware description.
  These patterns are worth carrying over verbatim when the verbs move to core.
- `ScryStone.onServerReady`'s plain-`console.log` readiness contract with
  `src-tauri/whet.rs` is load-bearing and documented in a comment — worth a line in a
  scry-side doc so it survives refactors.
