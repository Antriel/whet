# Whet Core Review

Grounded in real usage: `gooye-2/Project.mjs` + `scripts/Game*.mjs`, the Scry
whetstones, and `SnowFight`'s multi-sub-project layout.

## What's working well (keep doing this)

- **The memo/caching stack is coherent now.** `MemoContext` (per-request memoization),
  mtime-backed `HashCache`, cache-metadata `tryListIds`, partial generation, and the
  code-aware self-hash compose cleanly. The 2026-06 `PERFORMANCE_REVIEW.md` findings
  were largely implemented (see git log around `d2aecd2`…`c887b61`).
- **`getContext`/`generateContext`** solved the "shared per-batch state" problem with
  clear caching rules and a documented deadlock constraint. Good abstraction.
- **CLI hygiene for machine consumers** — exit codes, stdout/stderr split, auto-quiet
  NDJSON on non-TTY — is genuinely ahead of most build tools.
- **The `Project` config-view API** (`getStoneConfig`/`setStoneConfig`/`clearStoneConfigPreview`)
  put the editor-integration brains in core where they belong (see doc 02).

## Findings

### 1. Documentation gap (highest leverage, lowest risk)

`README.md` has empty stub sections (`### Hashes ...`, `### Commands ...`, `## Routers ...`).
The best existing documentation is `CLAUDE.md` — written for agents, but it's also the
best human doc. Worth doing:

- Fill the README from CLAUDE.md + the skills' content (they contain hard-won facts:
  stream conventions, cache-busting rules, CLI grammar).
- Move `MEMORY_CACHE_PLAN.md` and `PERFORMANCE_REVIEW.md` from the repo root into
  `docs/` with a status header (the perf review is mostly *implemented*; the memory-layer
  plan is largely *superseded* by metadata-backed `listIds` + single-file partial reads).
- `CLAUDE.md` staleness: the built-in stones list omits `StoneFactory` (and `StoneFactory`
  has no docs anywhere despite being the seed of the data-driven direction — doc 03).

### 2. Implicit stone-id instability vs persistent keys

`Stone.new` auto-suffixes duplicate implicit ids (`SharpStone`, `SharpStone:2`, …) by
**instantiation order**. Both `ConfigStore` entries and the file cache are keyed by
`stone.id`, so reordering stone construction silently re-targets persisted config and
orphans cache entries. `gooye-2` already works around this by naming every
ConfigStore-participating stone explicitly (`sharpstone-ui`, `multiatlas-preprocess`).

Suggestions, cheapest first:

- **Warn** when `ConfigStore.ensureApplied`/`setEntry` touches a stone whose id was
  auto-suffixed (detectable at construction: keep an `implicitId:Bool` flag).
- Optionally: `whet stones` (and the editor) could badge auto-suffixed ids so it's
  visible which stones have unstable identities.

### 3. ConfigStore lifecycle: orphans and no introspection

`ConfigStore` entries whose stone id no longer exists (renamed stone, removed pipeline)
sit in the JSON forever, silently. There's also no way to see "which stones have
patches, which are dirty" outside the editor. A small `config-store` command (core or
ScryStone) would cover it:

- `whet config-store status` — per-entry: matched stone / **orphan**, dirty state.
- `whet config-store prune [--yes]` — drop orphans.

Related nit: the `setPatch(stone, patch)` (reload+write+apply) vs
`setEntry(id, patch)`+`flush()` duality is easy to misuse from JS; consider making
`setEntry` private-ish or documenting that `Project.setStoneConfig` is the intended path.

### 4. `removeStone` / cache cleanup coupling

`Project.removeStone` deliberately doesn't clear cache; `StoneFactory.sync` returns
removed keys so callers can `cache.clearStone` — but nothing in the ecosystem actually
does (checked `AudioDb`). Either give `sync` an opt-in `clearCache` flag or accept that
stale entries age out via durability rules and say so in the StoneFactory docs.

### 5. `getStoneConfig` fixed-ref detection misses some shapes

`Project.getStoneConfig` classifies non-serializable config values as
`{type:'stone'}` / `{type:'stones'}` for `Stone`, `Router`, and `Array<Stone>` — but not
`Array<Router>` or plain objects containing stones (e.g. a `{sox, ogg, m4a}` map).
Consequence: the editor's dependency graph (`stones:graph`) under-reports edges for
such configs. A small recursive walk (bounded depth) over arrays/plain objects that
collects `Stone`/`Router` instances would make `fixed` complete.

### 6. `rootDir` detection has a standing TODO

The stack-trace-based `rootDir` inference in `Project.new` (`Stone.hx` caller frame
index 3) has a `// TODO write tests for this` and is sensitive to the genes/register
call shape. It has bitten nobody yet, but a test pinning the behavior (plus a fallback
when the frame isn't a file URL — e.g. REPL/eval) is cheap insurance.

### 7. Schema output could carry more of the discovery surface

`whet schema` covers options + commands. Two cheap additions that would make it the
single discovery call (details in doc 04):

- `--stones`: include `project.describeStones()` output.
- Per-command `description` already serializes; consider adding the owning stone's id
  for stone-registered commands (aliases hint at it, but only on collision).

### 8. Minor

- `Whet.hx` parses **project options only from the first `+` segment** — fine as a
  contract, but it was undocumented until the skill update (doc 04). An alternative
  (parse global options in every segment) would complicate `onInit`-once semantics;
  not recommended, just document it.
- `Project.getStone` is a linear scan called per CLI verb / WS command — fine at
  current stone counts (AudioDb creates 7 stones per audio entry; a big game could
  reach thousands, still fine).
- `StoneFactory` extending `Router` is pragmatically great (drop-in route source) but
  means factories inherit route-less `getHash()` semantics — worth one doc paragraph
  when StoneFactory gets documented.
