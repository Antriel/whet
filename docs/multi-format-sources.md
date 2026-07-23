# Multi-Format Sources — Investigation & Design Sketch

*2026-07-11. Investigation of the "one Source, multiple formats" idea: letting Stones provide
(and consume) alternate representations of the same logical asset, with registered from/to
transforms applied transparently, so chains of image stones stop decoding and re-encoding PNG at
every hop. Also assesses the related stream-API idea. Grounded in the actual pipelines of gooye-2
(the modern template) and the shared scry/whetstones + shards.client stones.*

**TL;DR verdict:** The problem is real and the ecosystem has already *voted for the solution
twice* — ad hoc. The skins pipeline invented a raw-RGBA side channel (`imgBytes` + metadata
router) to escape PNG round-trips at 50k-frame scale, and the audio pipeline avoids the problem
entirely by chaining through WAV and encoding only at the edges. The images pipelines lack an
equivalent interchange convention; that's the actual gap. The fix worth building is small: a
**self-describing raw-image interchange format + a project-level transform registry + an explicit
`getAs(format)` on route results**, with derived representations memoized per build (not
persisted). Full transparent format negotiation inside Router, and a streams rework of the core,
are both **not** worth it today — the first should wait for evidence the explicit API is
insufficient, the second is better served by two targeted optimizations. Measure with the
existing profiler before building anything; the biggest single waste found is actually *inside*
SharpStone (internal PNG materializations between ops) and needs no new architecture at all.

---

## 1. The problem, observed in real pipelines

### 1.1 The gooye-2 image chains (PNG at every hop)

Main atlas chain, per source image:

```
assets/*.png                                    (PNG bytes from disk)
  → SharpStone (items/dangers/ui/char-frames)   decode → ops → ENCODE PNG
  → SharpStone 'multiatlas-preprocess'          decode → ops → ENCODE PNG   (†)
  → ScryMultiAtlas                              decode ALL → pack → ENCODE atlas PNG
  → OxiPng                                      PNG-native recompress        (unavoidable)
  → SharpStone 'atlasFormats'                   decode atlas → encode webp+avif (final)
```

(†) Already partially mitigated: SharpStone's `skipUnprocessed`/`pipeline: null` passthrough
serves the *original bytes verbatim* when the resolved pipeline is empty and output is PNG-only —
i.e. the cost of redundant re-encoding was already noticed and hand-optimized for the no-op case.
When ops exist at both levels, the double decode/encode is paid in full.

Parallel chains repeat the shape: the **SDF chain** (items SharpStone → PNG → SdfStone
decode→EDT→encode → sdfMultiatlas decode→pack→encode → OxiPng/atlasFormats) and the **lossy
chain** (walls/shop SharpStone → PNG → lossyMultiatlas → PNG → lossyAtlasFormats decode →
webp/avif/png). Every arrow crossing a Stone boundary is a full PNG encode on one side and a full
decode on the other, for data that is conceptually "RGBA pixels + width + height" the whole way.

Two structural notes:

- **Interchange vs delivery.** The final fan-out (png/webp/avif, ogg/m4a) is *delivery* — multiple
  formats for the browser to pick from, already handled well by config-driven outputs + manifest.
  The waste is only in *interchange*: intermediate hops where PNG is used as the carrier between
  stones that both actually want raw pixels. Any design should target interchange and leave
  delivery alone.
- **The final encodes dominate publish builds anyway.** OxiPng with zopfli, avif `effort: 9`,
  lossless webp `effort: 6` are orders of magnitude more expensive than the intermediate
  default-compression PNG encodes. Eliminating intermediate hops will *not* transform publish
  build times. Where it plausibly matters: **cold dev builds** and, more importantly, **Scry
  editor latency** — a config tweak in the editor regenerates the chain downstream of the change,
  and the tweak→preview loop is a place where hundreds of ms of decode/encode per hop is felt.

### 1.2 The waste *inside* SharpStone (no architecture needed)

The single largest measured-by-inspection waste isn't between stones — it's within one. Several
SharpStone ops materialize the sharp pipeline to PNG mid-chain and reopen it:

- `trim`: `img.png().toBuffer()` → `sharp(buf)` (sharp requires materialization here, but raw
  would do: `img.raw().toBuffer()` + `sharp(buf, {raw})`).
- `outline`: ~4 separate `.png().toBuffer()` round-trips (ensureAlpha materialization, color
  plate, outline plate, composite result).
- `dropShadow`: same shape, ~4 round-trips.

An image with `[trim, outline, dropShadow]` pays ~9 PNG encodes before its *output* encode. All
of these could pass `{ raw: {width, height, channels} }` buffers instead — a local refactor of
one file, no Whet changes. **This is the cheapest real win and should happen first regardless of
whether the format system gets built.**

### 1.3 The skins pipeline already built the escape hatch — ad hoc

`ScrySkinsOptimizer` → `ScryMultiAtlas` is the one place where PNG interchange was truly
untenable (~50k cut frames per rebuild), and the solution that evolved is instructive:

- The optimizer decodes each sheet PNG **once** (`Scry.decodePng`), cuts frames to **raw RGBA
  buffers**, and emits them as `SourceData.fromBytes(id, frameBytes)` — raw pixels in the normal
  Source system.
- Width/height can't ride inside the bytes, so they travel in a **separate metadata group list**
  consumed via a second Router (`metas` + `imgBytes` config on ScryMultiAtlas).
- The intermediate is huge and worthless on disk, so the stone opts into
  `CacheStrategy.InMemory(LimitCountByLastUse(1))`.
- The packer (`Scry.makeMultiAtlas`) accepts a hybrid: entries with `bytes` (+ external w/h) *and*
  entries with `pngBytes` it decodes itself.

That is the multi-format-sources feature, hand-rolled: a raw interchange representation, a
non-self-describing sidecar for its parameters, memory-scoped caching, and a consumer that
accepts either format. It works, but the format knowledge is smeared across three files, the raw
bytes are meaningless without the sidecar (`stone-cat` on one gives you an opaque blob), and no
other pipeline can reuse it without re-plumbing the same dual-router arrangement.

### 1.4 The audio pipeline shows what "solved" looks like

`AudioDb`'s per-key chain is `wav → AudioSox (wav→wav effects) → Audio (encode ogg / m4a)`.
Decode-ish work happens once at ingest, effects chain in the cheap interchange format (WAV *is*
raw samples + a self-describing header), and expensive lossy encodes happen exactly once, at the
edge. Nobody had to design this — WAV existing as a universal, self-describing, cheap-to-parse
interchange format made it the natural shape. **Images lack the convention, not the need.** The
proposal below is essentially "give images (and anything else) their WAV."

---

## 2. Prior art — idiomatic approaches worth stealing from

**GStreamer caps negotiation.** Elements advertise capability sets ("caps": media type +
parameters); the pipeline negotiates a common format per link and developers insert `videoconvert`
elements that collapse to passthrough when formats already agree. The full auto-negotiation
machinery is famously complex — the lesson to take is the *cheap-passthrough converter* idea
(a conversion step that costs nothing when formats already match, like SharpStone's
`pipeline: null` fast path), not the negotiation protocol.

**Rails Sprockets / Parcel transformers.** The closest match to the "registered from/to
transform" idea, and pleasantly simple: `register_transformer 'text/scss', 'text/css',
SassProcessor`. A request for `foo.css` finds `foo.scss` plus a registered transformer chain and
serves the converted result, cached against the source digest. Consumer-driven, extension-keyed,
single registry. This is the right complexity tier for Whet.

**Pandoc / compiler IRs.** N formats interconvert through one canonical intermediate
representation (document AST, LLVM IR): N readers + N writers instead of N² pairwise transforms.
For Whet images the canonical IR is obvious (raw RGBA8 + dims); the registry then only ever needs
`X→raw` and `raw→X`, and any `X→Y` composes through raw. Avoid pairwise-transform-graph
path-finding entirely; it's what makes GStreamer hard.

**HTTP content negotiation.** Consumer states what it accepts; producer picks the best variant it
can serve; caches key on the variant (`Vary`). Maps to: `routeResult.getAs('rgba8')` with the
transform cache keyed on `(source hash, target format)`.

**Bazel providers.** A build target returns multiple typed *views* of its output and consumers
request the provider they understand. The tempting generalization — stones exposing live JS
objects (a decoded `ImageData`, a `sharp` instance) instead of bytes — breaks Whet's
everything-is-hashed-bytes caching model. Keep providers as an analogy only: alternate *byte*
representations, hash-derivable, never live objects in the Source system.

**Unity/Bevy import pipelines.** Source asset → processed representation cached in a library,
consumers only ever see the processed form. Confirms the caching stance: derived representations
are cache entries keyed by source content hash + processor version, safe to blow away.

**gulp/vinyl.** `file.contents: Buffer | Stream | null` — the precedent for the stream idea, and
also its cautionary tale: every plugin in the ecosystem had to handle both cases forever, and most
just called `buffer()` anyway. See §4.

---

## 3. Proposed design for Whet

Four layers, ordered by increasing commitment. Each is useful without the ones after it.

### 3.1 Format identity on SourceData (core, tiny)

Give `SourceData` an optional `format:String` — a short id like `png`, `rgba8`, `wav`, defaulting
to the file extension of `id`. Whet core treats it as an opaque string. This alone lets consumers
branch without sniffing bytes, and gives the registry its key. (`OutputFilter.extensions` is the
existing half of this idea on the producer side; `format` is the per-datum half.)

### 3.2 A self-describing raw-image interchange format (convention + helper, not core)

Define `rgba8`: a trivial header (magic + width + height, e.g. 16 bytes) followed by RGBA8 bytes.
Alternatives considered:

- **QOI** — self-describing and compact, but nothing in the stack reads it natively; sharp wants
  `{raw:{width,height,channels}}`, the Haxe `ImageData` wants pixels+dims. A compression layer
  that both sides must undo buys nothing for memory-scoped interchange.
- **farbfeld** — self-describing but 16-bit/channel: doubles size for no benefit here.
- **Header-prefixed raw** wins: ~zero encode/decode cost, one ~30-line codec helper shared by the
  JS stones and (via a Haxe twin) `Scry.hx`.

Being self-describing is what fixes the skins hack: raw frames become meaningful standalone
SourceData (dims travel with the bytes), `stone-cat` can print `rgba8 412x300`, the
`metas`/`imgBytes` dual-router split collapses to one router, and any stone can consume the
frames without out-of-band knowledge.

Convention: interchange-only outputs should default to `InMemory` cache strategy (the skins
pipeline already discovered why — raw intermediates are large and worthless on disk). Not
enforced, just documented; a stone whose raw output is expensive to recompute may still choose
FileCache.

### 3.3 Transform registry + explicit `getAs` (the actual feature)

```js
// Project-level registry. Registration is code (Project.mjs / stone modules), like routes.
project.formats.register('png',   'rgba8', async bytes => ..., { cost: 1 });
project.formats.register('rgba8', 'png',   async bytes => ..., { cost: 5 });
project.formats.register('webp',  'rgba8', async bytes => ...);
```

- **Lookup:** direct hit, else one hop through a designated pivot format (`X→rgba8→Y`). No
  general graph search — with the IR convention, two hops covers everything real.
- **Consumption:** `RouteResult.getAs(format)` (and a convenience on Router:
  `router.get(pattern, { as: 'rgba8' })`). If the underlying SourceData already has the format,
  passthrough — zero cost, GStreamer-style. Otherwise run the transform.
- **Caching:** transforms are deterministic, so the derived bytes are keyed by
  `(sourceData.hash, transformId)`. Memoize in **MemoContext** (the existing per-build/per-request
  ALS store — this is exactly what it's for), so within one build the atlas packer and the SDF
  stone decoding the same PNG share one decode. Do **not** persist derived representations by
  default: decodes are big and fast-ish; the persisted canonical form is the compact one.
  If a specific expensive transform ever needs persistence, wrap it in a plain Stone — the
  machinery already exists.
- **Hashing:** a derived representation's hash is `merge(source.hash, fromString(transformId))` —
  computable without running the transform, so `getHash()` paths stay cheap and sound.
- **Producer helper:** the mirror of `getAs` for stone authors:
  `formats.ingest(sourceData, 'rgba8')` — the "give me pixels, I don't care what you were" call
  that replaces every stone's private decode preamble.

What this changes in the real pipelines:

- `SharpStone` gains `rgba8` as a legal member of `outputs` (and accepts `rgba8` inputs via
  `ingest`). A chain like items → multiatlas-preprocess → atlas configures the intermediate
  SharpStones with `outputs: ['rgba8']` and the PNG round-trips between them vanish.
- `ScryMultiAtlas` drops the `metas`/`imgBytes` special case: one `sources` router, `ingest` each
  entry, dims come from the rgba8 header. `ScrySkinsOptimizer` emits rgba8 instead of naked bytes.
- `SdfStone` reads rgba8 from the items stone directly instead of decoding its PNG.

### 3.4 Implicit negotiation in Router (defer)

The "seamless" endgame — a query for `foo.png` matching a stone that lists `foo.rgba8`, Router
synthesizing a virtual `foo.png` result backed by a registered transform — is deliberately
**deferred**. It touches `listIds()`, `OutputFilter` matching, serve-id enumeration, `getHash()`
of routers, and the dev server's URL space; every one of those grows a "…or is convertible to"
case, and debugging "where did this file come from" gets harder. The explicit `getAs`/`ingest`
API covers every consumer found in this investigation, because stones (not URLs) are the
consumers of interchange formats — the browser-facing surface always wants the delivery formats,
which are real outputs already. Revisit only if a concrete case appears where the consumer
can't know the producer's format statically (none exists today: pipelines are wired explicitly
in Project.mjs).

---

## 4. Streams and stream-like APIs — assessment: don't rework the core

The motivating cases, checked against reality:

- **"Don't read whole files just to serve them."** Legitimate, but the fix isn't a stream API in
  Source — it's noticing that `SourceData` is often *already file-backed* (`hasFile()`,
  FileCache entries, `Files` stone). A dev-server change — when the resolved SourceData has a
  file path and the response doesn't need transformation, `sendFile`/stream from that path —
  gets the win with zero model change. Same for `exportTo`/zip-style bulk copies (stream
  file→file instead of buffering).
- **"A stone only wants the header of a big file."** No current stone does this. Image dims come
  from sharp metadata after decode is needed anyway; audio metadata comes from ffprobe-style
  tools that take file paths. If it ever matters, a `readRange()` on file-backed SourceData is a
  targeted addition.
- **The structural blocker:** Whet's correctness rests on content hashing. A Source must be fully
  read to be hashed unless the mtime fast path vouches for it — so streaming can save *memory*,
  not *I/O*, on anything that isn't mtime-validated. And a `data: Buffer | Stream` union is the
  vinyl trap: every stone forever handles two cases, and one-shot-consumability of streams
  poisons the multi-consumer memoization that MemoContext provides (a stream can't be handed to
  two consumers; a buffer can).

If pipelines ever process assets that genuinely don't fit in memory (video?), the right shape
would be file-path-passing between stones (which `getFilePath()` already supports) — not streams
through Source. **Recommendation: adopt the two targeted optimizations (file-backed serving,
lazy `SourceData.data` loading if memory pressure ever shows up), skip the generic stream API.**

---

## 5. Value assessment and recommended sequence

Honest sizing: **medium value, small-to-medium cost** — with the caveat that the top item below
is high value for zero architecture.

| # | Step | Cost | What it buys |
|---|------|------|--------------|
| 1 | Profile first: `p.enableProfiling()` + the existing span export on a cold gooye-2 build; record time in intermediate PNG encodes/decodes vs final encodes | hours | Ground truth; go/no-go for #3–4 |
| 2 | SharpStone internal raw chaining (trim/outline/dropShadow stop materializing PNG mid-op-chain) | small, local | Likely the biggest single win; editor-latency on the ops that get tweaked most |
| 3 | `SourceData.format` + rgba8 codec helper (JS + Haxe twin) | small | Foundation; skins hack becomes self-describing |
| 4 | Transform registry + `getAs`/`ingest`; convert SharpStone↔ScryMultiAtlas↔SdfStone interchange to rgba8; collapse `metas`/`imgBytes` | medium | Removes all inter-stone PNG hops; one decode per source per build via MemoContext |
| 5 | File-backed dev-server serving (`sendFile` when `hasFile()`) | small, independent | Dev-server memory/latency on big atlases/audio; subsumes the useful part of "streams" |
| 6 | Implicit Router negotiation | large | Deferred — no current consumer needs it |

Sequencing rationale: #1 protects against building #4 on intuition (publish builds are dominated
by zopfli/avif final encodes that no interchange format removes; the case for #4 rests on cold
dev builds + editor tweak latency + skins-pipeline simplification, and the profiler can confirm
or kill it cheaply). #2 and #5 are worth doing regardless of the verdict. #3–4 fit naturally
alongside the data-driven-stones direction (docs/ecosystem-review-2026-07/03): the format
registry is the same "project-level registry + convention" pattern as the planned StoneFactory
registry, and rgba8-typed configs would slot into the config-schema work.

### Open questions (decide when building #4)

- Registry scope: per-Project instance vs module-level singleton. Per-project matches
  `ConfigStore`/commands precedent and keeps tests clean; stones ship their registrations as a
  side-effect-free `registerFormats(project)` helper.
- Does `rgba8` carry premultiplied-alpha or channel-order variants? Recommendation: no — fix
  straight-alpha RGBA8 exactly (it's what sharp raw and Haxe `ImageData` both speak); anything
  else is a different format id.
- Whether `getOutputFilter`/`find-outputs` should surface interchange formats or hide them
  (probably hide by default — `find-outputs png` listing stones that only *convertibly* produce
  png is the implicit-negotiation confusion in miniature).
