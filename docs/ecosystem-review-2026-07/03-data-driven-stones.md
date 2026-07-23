# Data-Driven Stones: StoneStore Design Exploration

The question: interacting with Whet through the editor (dynamic config, ConfigStore)
works well — how far can the data-driven direction be pushed, without giving up the
flexibility of script-based `Project.mjs`?

## What exists today (three points on the spectrum)

1. **ConfigStore** — data-driven *parameters*. Stones are declared in script; a JSON
   file patches their serializable config fields, with baseline capture, deep-merge,
   preview vs persist. The stone *set* and *wiring* stay in script.
2. **StoneFactory / AudioDb** — data-driven *subgraphs*. `audio.json` entries drive
   `sync(data, keyFn)`, which creates/updates/removes a per-entry chain of stones
   (wav→sox→ogg/m4a + meta) with **stable explicit ids** (`audio/${key}:wav`) and
   routes, exposed as a Router. The editor CRUDs the JSON via `AudioDbPlugin`.
   This is already 80% of the concept — but `createEntry` is hardcoded per factory.
3. **Script wiring** — `GameAssets.mjs`: hand-instantiated stones, hand-composed
   routers, build-mode mutation in methods.

## What in GameAssets is actually data-shaped (and what isn't)

Data-shaped (repetitive, per-instance, editor-worthy):

- The **SharpStone-per-folder** entries: `{id, sourceDir, operations?, configStore}`
  repeated five times, plus commented-out ones (`effects`) that are literally
  "entries toggled off".
- The **atlas definitions**: `{name, sources, packOptions, lossy?}` — three instances.
- The **format-conversion outputs**: `[{type:'webp', quality…}, …]` arrays — repeated
  with small variations across `lossyAtlasFormats`, `atlasFormats`, `preloadAssets`.
- The **route mounts**: which stone feeds which pipeline stage under which prefix.

Not data-shaped (keep in script):

- `onInit` build-mode switching (`setDebugMode`/`setPublishMode`), env, publish URLs.
- Cross-cutting links: `linkToHaxe` (manifest → Haxe define + dependency), fixed
  handoff paths (`.whet/manifest.json`).
- Anything carrying *rationale*: the SDF-atlas block in GameAssets has ~15 lines of
  comments explaining why SDF pages must stay lossless, why extrude-not-padding, why
  msdf needs `alpha:false` OxiPng. **JSON can't hold why.** Special-case wiring with
  design reasoning should stay in script where comments live next to the decision.

## Design sketch: StoneStore

**StoneStore = StoneFactory with a generic `createEntry` driven by a registry.**
Same lifecycle (sync/create/update/remove, stable ids, Router-compatible), but the
entry data *is* the stone declaration:

```jsonc
// assets/stone-store.json
[
  {
    "id": "sharpstone-ui",
    "type": "SharpStone",
    "config": {
      "pngs": { "$router": [["/", "assets/ui/", "**/*.png"]] },
      "operations": [{ "op": "trim" }]
    },
    "mount": [["/", "$self"]]          // route into the store's own Router
  },
  {
    "id": "lossy-multiatlas",
    "type": "ScryMultiAtlas",
    "config": {
      "name": "lossy_atlas",
      "pngs": { "$router": [["/", "assets/backgrounds/"], ["/", { "$stone": "sharpstone-walls" }]] },
      "defaultPackOptions": { "extrude": [2, 2, 2, 2] }
    }
  }
]
```

Pieces needed:

1. **Stone-type registry.** `registerStoneType(name, ctor, schema?)` — whet registers
   built-ins; project/shared libs register theirs at import time (a one-liner next to
   each class). Without it there's no way to go from `"type": "SharpStone"` to a
   constructor, since classes live across three repos.
2. **Config reviver.** Resolve `{"$stone": "id"}` → live stone, `{"$router": [...]}` →
   `new Router(...)` (recursively reviving `$stone` refs in routes). Resolution must be
   **lazy or two-pass** so entries can reference each other and script-defined stones
   regardless of order. Everything else passes through as plain JSON (which is exactly
   what stone configs are designed to be).
3. **`StoneStore extends StoneFactory`** over a JSON file (promote AudioDb's private
   `JsonDb` into core — it's independently useful). `sync` maps entries through the
   registry + reviver; `mount` entries become the factory's routes. Script does one
   thing: `bundleAssets.route([['/', store]])` — a single mount point, or several named
   stores (`assets`, `atlases`) if stage separation matters.
4. **Editor plugin.** A generic `StoneStorePlugin` (CRUD on entries, mirroring
   AudioDbPlugin) — with schema-driven forms (below) it needs no per-type UI for
   simple stones. Add/duplicate/disable-entry covers the "commented-out effects stone"
   workflow properly.

### Config schemas: the keystone

A static, optional `configSchema()` per stone class (JSON-Schema-ish: field types,
ranges, enums, defaults, descriptions) pays off four times:

- **Generic editor forms** — Stone Inspector stops needing a hand-written Svelte
  editor per class for simple configs (today only SharpStone has one).
- **StoneStore validation** — reject bad entries at sync with a real message instead
  of a generate-time crash.
- **LLM affordance** — `whet stone-schema <type>` (or schema embedded in
  `stone-config` output) tells an agent exactly what's editable and what values are
  legal, no source-reading required.
- It gives `StoneConfigMeta.uiHints` (currently dead, doc 02 §4) its purpose.

### Interplay rules (avoid two sources of truth)

- **ConfigStore patches script-defined stones; StoneStore entries are edited
  directly.** A store-defined stone should not *also* have a ConfigStore patch —
  its entry already is persistent config. Enforce or warn.
- Hashing needs nothing new: entry configs are plain data feeding normal stone
  hashing; logic changes are covered by the code-aware self-hash.
- Ids in the store are explicit by construction — sidestepping the implicit-id
  instability (doc 01 §2).

## Recommended incremental path

1. **Registry + reviver** (small, standalone, testable — whet core).
2. **`JsonDb` promoted to core**, `StoneStore extends StoneFactory` on top.
3. **Pilot on the SharpStone folder entries in GameAssets** — the most repetitive,
   least rationale-laden slice. `charFrames`/`items`/`dangers`/`walls`/`ui` become five
   store entries; the atlas/manifest wiring stays in script and consumes the store as
   a route source. Success criterion: adding a new asset folder = editor action, no
   Project.mjs edit.
4. **Generic StoneStorePlugin + schema-driven forms** in Scry.
5. Only then consider atlases/format-chains as store entries — they have more
   cross-links (formats consume atlas outputs) and are where `$stone` refs earn
   their keep.

## What deliberately stays out of scope

- Making `Project.mjs`/`onInit` data-driven. Mode switching, publish config, and
  cross-tool links are control flow, not data — script is the right medium and the
  current `setDebugMode`/`setPublishMode` convention is good.
- A visual node-graph pipeline editor. The stones:graph view + StoneStore CRUD gets
  most of the value at a fraction of the cost; revisit only if store entries start
  referencing each other heavily.
