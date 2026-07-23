---
# whet-uzjf
title: 'configSchema(): per-class config schemas, stone-schema CLI, StoneStore validation'
status: completed
type: feature
priority: normal
created_at: 2026-07-23T07:08:07Z
updated_at: 2026-07-23T13:11:59Z
parent: whet-1vzf
blocked_by:
    - whet-hnde
---

The "keystone" from doc 03: optional per-stone-class config schemas, surfaced to the registry, a `whet stone-schema <type>` CLI (doc 04 §5), and StoneStore sync-time validation. Gives dead `StoneConfigMeta.uiHints` (doc 02 §4) its purpose. Editor form generation is scry-app work, out of scope here.

## Frozen decisions

- **Format: standard JSON Schema (draft-07 subset)** describing the stone's *editable config object* (the JSON-serializable fields — the same set `Project.getStoneConfig` puts in `editable`). Fields that hold stones/routers may be described as `{"type": "object"}` or omitted. Standard JSON Schema so scry-app's Monaco integration (which already consumes JSON schemas) can use it directly later.
- **Convention**: `static configSchema()` — a static *function* returning the schema object. JS stones: `static configSchema() { return {...}; }`. Haxe stones: `@:keep public static function configSchema():Dynamic`.
- `StoneRegistry.register` already reads `ctor.configSchema?.()` (hook wired in whet-hnde); `registerBuilder` takes schema explicitly.
- **No external validator dependency** (no ajv — whet keeps deps minimal). Write `src/whet/stones/SchemaValidator.hx`: `validate(value:Dynamic, schema:Dynamic, ?path:String):Array<{path:String, message:String}>` supporting exactly: `type` (string or array), `properties`, `required`, `additionalProperties` (boolean only), `items`, `enum`, `minimum`, `maximum`, `minLength`, `pattern`; `description`/`default` ignored. Unknown keywords ignored (forward-compat). **Skip validation of any subtree whose value is a single-key `{$stone: ...}` or `{$router: ...}` object** — those revive to live instances and legitimately mismatch the schema.
- **StoneStore integration**: in `syncEntries` validation (whet-31lx step 1), when the registry entry for a flat entry's type has a schema, run the validator on the entry's config (post-expansion, post-token-substitution, pre-revive) and add any findings (with `entryKey + path`) to the aggregated all-or-nothing error.
- **CLI**: `whet stone-schema <type>` — a core command registered next to the existing `schema` command (see how `schema` is implemented/registered in `src/whet/Whet.hx` from the whet-hqwq work, and follow its stdout/NDJSON conventions). With a known type: print the schema JSON (or a clear "type has no schema" message, exit 0). Unknown type: list registered type names, exit 1. No arg: print `StoneRegistry.list()`.
- **Project.getStoneConfig**: populate `meta.uiHints` with the schema for the stone's class when one is registered/available (lookup by constructor via the registry, or read `constructor.configSchema` directly off the instance — the latter also covers unregistered classes; prefer it).
- Add a reference `configSchema()` to one built-in (`JsonDb` — trivial) and to test/helpers/mock-stone.mjs's MockStone for tests.

## Todos

- [x] SchemaValidator with per-keyword unit tests (`test/schema-validator.test.mjs`), incl. $stone/$router skip and path-prefixed messages
- [x] configSchema convention: MockStone + JsonDb reference schemas; registry pickup verified
- [x] StoneStore sync validation integration + test (bad entry config → aggregated error naming entry key + JSON path; stones untouched)
- [x] `whet stone-schema` command + smoke test (check test/ for an existing CLI spawn pattern; if none exists, cover the command's handler function directly and note manual CLI verification)
- [x] getStoneConfig meta.uiHints wiring + test
- [x] Rebuild + full test run green

## Design review (validated 2026-07-23)

Holistic review from the Scry side (Stone Inspector + tools). Conclusion: **land this, but
re-rank the value.** Does not change the Frozen decisions above — it reframes *why* and adds
guardrails. Detail lives in the scry-app `/ecosystem-map` session that produced it.

### Re-ranked payoffs (lead with validation + discovery, not forms)

Doc 03 sells this as "generic editor forms replace per-stone Svelte editors." That is the
**weakest** of the four payoffs and the most misleading. Real ranking for our trajectory:

1. **StoneStore sync validation (the load-bearing one).** JSON-entry / LLM-edited
   `stone-store.json` needs "reject bad entry at sync with a path-specific message" instead of
   a generate-time crash several stones downstream. This is why uzjf is a child of whet-1vzf —
   it is required by the data-driven stone work, not a Stone-Inspector nicety.
2. **LLM / Monaco discovery.** `whet stone-schema <type>` + the frozen "standard JSON Schema
   draft-07" decision means Scry's Monaco can consume the schema **directly** for
   `stone-store.json` autocomplete/validation/hover. Compounds with the format-catalog beans
   (scry-app-t1bn / scry-app-ilg2) and doc 04's discovery-first thesis. Highest long-horizon
   leverage. Also directly enables scry-app-iv1d (bidirectional raw-JSON stone-config editor):
   the same schema drives that editor's validation/autocomplete.
3. **Forms for the genuinely-simple long tail.** Upgrades the raw-JSON `<pre>` fallback in
   `ConfigEditor.svelte` to a real form for stones nobody will hand-write an editor for. Real
   but not urgent.
4. **Gives dead `uiHints` a purpose.** Housekeeping, ~free once 1-3 exist.

Fold this ordering into the framing: uzjf is the **validation-and-discovery substrate**, forms
are a downstream freebie. Leading with forms risks someone over-investing in a Scry form
generator that the flagship stones will never use.

### It will NOT replace the custom editors — and shouldn't try

`SharpConfigEditor` / `SplitOpEditor` / audio-manager stay custom. Their value **is** the
domain UX (per-source override targeting, canvas region editing, waveform + A/B + live
preview). A JSON-Schema `configSchema()` describes SharpStone's *outer* editable shape
(`operations[]`, `operationsMap{}`, `outputs[]`, `editorGrid`) — exactly the irreducibly-custom
part. Note the existing proof: `stone-inspector/.../sharp/opDefs.ts` + `OpCard.svelte` is
already a schema-driven form generator, but at the **op-param** altitude, nested three
components deep inside bespoke pipeline UX. Two schemas at two altitudes that never claim to
describe each other is fine; do NOT try to source op-param defs from `configSchema()` (huge,
still generates no UX, creates a second source of truth that drifts).

### Coexistence model (the honest answer to "replace SharpStone?")

Scry already has the right shape in `ConfigEditor.svelte`: **custom editor if one is registered
for the className; schema-generated form otherwise; raw JSON if neither.** The schema form just
upgrades the *else* branch. Write this rule down so the Scry side doesn't build a form
generator ambitious enough to fight the custom editors. SharpStone should ship a **shallow**
schema (its scalar fields only) and keep its custom editor for `operations`.

### Additional gotchas to freeze

- **Permissive by default.** Do NOT set `additionalProperties:false` as a convention. SharpStone
  carries Scry-injected, build-ignored editor-only fields (`editorGrid`/`editorGridMap`); a
  strict schema would flag live, legitimate config in the store validator / Monaco lint. Keyword
  is supported per the frozen list — just make "omit it" the convention and say why here.
- **Schema targets the `editable` projection, not the raw class fields.** `getStoneConfig` builds
  `editable` as the JSON-serializable subset; the schema author must describe *that* set. Silent
  desync otherwise. State it as a contract.
- **Token-substitution corner (whet-qwye is LIVE, not future).** `each` expansion +
  `$file`/`$name` substitution ships today. Validating post-substitution is right, but a field
  legitimately holding a token pre-substitution, or a templated numeric field, can false-positive.
  Add a test case for schema validation over an `each`-expanded entry with token values.

### Drift escape hatch is NOT uniform (correction)

The layout-schema drift (hand-authored, 1660 lines, diverges from Haxe typedefs) is the warning.
The planned fix — macro-generate the schema from the Haxe config typedef — **only covers Haxe
stones.** Essentially all main Stone implementations are **JS**. So the long-term
generate-the-schema story is two-track:

- **Haxe stones:** macro from the config typedef (the existing plan).
- **JS stones:** would need TS configs (erasable-syntax-only, using Node's native type-stripping
  so there's no bundle/transform step) **plus a types-to-schema conversion tool.** That tool does
  not exist yet and is the real cost of eliminating JS-side drift.

Until those exist, JS-stone schemas are hand-authored and shallow-by-design (which is fine — the
shallow-schema convention keeps the hand-authored surface small). Flag the TS-config +
types-to-schema tool as a **future prerequisite** for JS-stone drift-elimination, not part of uzjf.

### Future paths this opens (beyond uzjf's scope)

- Monaco-native `stone-store.json` authoring (completions/validation/hover) via t1bn/ilg2 catalog.
- MCP / `whet explain`: schema as agent-facing tool-parameter descriptions driving the
  patch -> preview -> persist loop the editor currently monopolizes.
- "Add entry" default seeding in the future `StoneStorePlugin` from schema `default`s.
- **Data-driven pipelines across any stone source (open question, not decided).** The token
  substitution is new and may be expanded toward dynamic stone lookups — building whole Whet
  pipelines from a Scry visual UI without referencing stones by live instance. A *full* pipeline
  likely should NOT be a single `StoneStore` but some data-driven recipe spanning any stone
  source; shape is unsettled. Current 1vzf work already points this direction. Schema/validation
  is a prerequisite for making that authorable safely, but the pipeline-recipe shape is its own
  future design, not this bean.

## Summary of Changes

Landed the configSchema keystone. All work is in whet core (Haxe → bin/whet.js), tests are JS.

**New: `src/whet/stones/SchemaValidator.hx`** — dependency-free JSON-Schema (draft-07 subset) validator. `validate(value, schema, ?path) -> Array<{path, message}>`, collects all findings. Supports `type` (string/array), `properties`, `required`, `additionalProperties` (bool), `items`, `enum`, `minimum`, `maximum`, `minLength`, `pattern`; ignores `description`/`default` and unknown keywords (forward-compat). Skips any single-key `{$stone}`/`{$router}` subtree (they revive to live instances). 16 unit tests in `test/schema-validator.test.mjs`.

**configSchema() convention** — `StoneRegistry.register` already picked up `ctor.configSchema?.()` (from whet-hnde). Added reference schemas: `JsonDb.configSchema()` (Haxe `@:keep static`, shallow/permissive) and `MockStone.configSchema()` (JS, for tests). Registry pickup covered by a new test.

**StoneStore sync validation** — `StoneStore.validateSchemas(flat)` runs in `syncEntries` post-expansion / post-token-substitution / pre-revive: for each expanded entry whose registered type carries a schema, validates config and aggregates findings (prefixed `entry "<key>" @ <path>`) into the existing all-or-nothing thrown error. Tests: bad entry → aggregated error naming key + JSON path, valid entry builds, and an `each`-expanded entry with `$name` tokens validates post-substitution while `$stone`-ref configs are skipped.

**`whet stone-schema [type]` CLI** — new core command in `Whet.hx` next to `schema`. Known type w/ schema → prints schema JSON (exit 0); known type w/o schema → "has no schema" (exit 0); unknown → registered-type list on stderr (exit 1); no arg → `StoneRegistry.list()` JSON. Excluded from the project `schema` export. 4 smoke tests in `test/cli.test.mjs` (subprocess + minimal project, mirroring the existing pattern).

**getStoneConfig meta.uiHints** — `Project.getStoneConfig` now populates `meta.uiHints` by reading `constructor.configSchema()` off the instance (covers unregistered classes), null when absent. 2 tests in `test/project-config-api.test.mjs`.

**Incidental fix (latent bug from whet-hnde):** `StoneRegistry` registered builtins eagerly in `__init__` (module-eval time), which referenced the builtin class bindings. Importing `StoneRegistry` from the entry module (`Whet.hx`, for the new CLI command) reordered the import graph so `Files` was still in its TDZ when that eager call fired ("Cannot access 'Files' before initialization" — broke `stone.test.mjs` / `hash-cache.test.mjs`). Made builtin registration lazy (first `get`/`list`/`register` via `ensureBuiltins()`), so class bindings are only touched at runtime once the graph is initialized; "registered on import" semantics preserved.

Rebuilt (`haxe build.hxml`, clean); full suite green: **258 tests, 0 fail**.

Out of scope (unchanged): SharpStone's shallow schema + scry-app form/Monaco work — follow-ups in their repos per the epic.
