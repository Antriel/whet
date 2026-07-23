---
# whet-1vzf
title: 'StoneStore: data-driven stone graphs (registry, reviver, store, preview)'
status: todo
type: epic
priority: normal
created_at: 2026-07-23T07:05:38Z
updated_at: 2026-07-23T12:49:01Z
---

Umbrella for landing the StoneStore design from `docs/ecosystem-review-2026-07/03-data-driven-stones.md`, plus the generic StoneFactory live-preview from scry-app-y4be §A (`scry-app/.beans/scry-app-y4be--audio-manager-live-preview-of-unsaved-audio-config.md`).

Reference implementation to mirror/generalize: `gooye-2/scry/whetstones/assets/AudioDb.mjs` (StoneFactory subclass: per-entry stone chains, group expansion, JsonDb, per-file overrides).

## Design deltas vs doc 03 (frozen — do not re-decide in child beans)

1. **Registry registers builders, not bare constructors.** A registered type is a named `createEntry`: `(key, revivedConfig) -> {stones, routes?, mainStone?, update?}`. `registerStoneType(name, Class)` is single-stone sugar. This lets one JSON entry declare a multi-stone chain (future AudioDb migration) and lets builders skip stages conditionally (the "SoX-optional skip-stone" note in scry-app-y4be).
2. **`each` expansion clause** generalizes AudioDb group entries (dir scan + regex + nameTemplate + per-file `overrides` deep-merge + `$file`/`$name` token substitution). Doc 03 missed this entirely; AudioDb could not have migrated without it.
3. **Preview lives on StoneFactory via a retained canonical `dataMap`** — `sync()` records last-synced data per key; `previewEntry` mutates live stones only; `revertEntry` re-applies from dataMap. No DB coupling, no baseline snapshot (simpler than ConfigStore), zero AudioDb changes.
4. **Reference consistency**: default entry update is id-stable destroy+recreate; sync processes entries in **topological order** of `$stone` refs and **force-updates dependents of any touched entry** (cascade). Without this, an unchanged entry keeps a dead instance of a recreated dependency — the main correctness hole in the doc-03 sketch.
5. **All-or-nothing sync validation** with aggregated, path-specific error messages.
6. **`disabled: true`** per entry (the "commented-out stone" workflow).
7. `mount` drops `"$self"` — the entry's mainStone is implicit.

## Child beans / order

1. StoneFactory preview/revert (dataMap) — independent, HIGH (scry-app-y4be §B–E wait on it).
2. Stone-type registry + config reviver — independent.
3. JsonDb promoted to core — independent.
4. StoneStore (needs 2, 3; preview arrives free via 1).
5. `each` expansion (needs 4).
6. configSchema() + stone-schema CLI + validation (needs 2; integrates with 4).
7. Docs (needs 4, 5).

## Out of scope (follow-ups in other repos — create beans there when ready)

- scry-app: WS `factory:preview-entry`/`factory:revert-entry` plugin + client work — tracked in scry-app-y4be §B–E already; generic `StoneStorePlugin` + schema-driven forms is a later scry-app bean.
- scry repo: migrate AudioDb.loadDb to core JsonDb; eventually re-express the audio chain as a registered builder.
- gooye-2: pilot — the five SharpStone-per-folder entries in GameAssets.mjs become store entries (doc 03 "Recommended incremental path" step 3).

## Conventions for implementers

- Whet is Haxe (4.3.4) compiled to JS: build `haxe build.hxml`, then test `node --test "test/**/*.test.mjs"` (tests are JS against compiled bin/whet.js — always rebuild before testing).
- New classes go in `src/whet/stones/`, exposed like existing stones (check build.hxml `@:expose` setup; verify importability from bin/whet.js in tests, e.g. `import { StoneFactory } from` the repo's bin/whet.js as test helpers do).
- Test helpers: `test/helpers/test-env.mjs` (createTestProject), `test/helpers/mock-stone.mjs` (MockStone).

## Child bean ids

1. whet-rg6l — StoneFactory preview/revert (HIGH; scry-app-y4be waits on it)
2. whet-hnde — registry + reviver
3. whet-np9d — JsonDb to core
4. whet-31lx — StoneStore (blocked by 1, 2, 3)
5. whet-qwye — `each` expansion (blocked by 4)
6. whet-uzjf — configSchema + stone-schema CLI (blocked by 2)
7. whet-onc4 — docs (blocked by 4, 5)

## Note: configSchema re-ranking (2026-07-23 review)

Design review folded into whet-uzjf. Key point for this epic: **configSchema's primary value is
StoneStore sync validation + LLM/Monaco discovery, NOT generic editor forms.** The forms payoff
(doc 03's headline) is the weakest and applies only to the simple long tail — the flagship
stones (SharpStone, audio) keep custom editors. Validation is the load-bearing dependency for
JSON-entry / LLM-authored `stone-store.json`, which is why uzjf belongs under this epic. See
whet-uzjf "Design review" for the coexistence model, permissive-default guardrail, and the
Haxe-vs-JS drift-escape-hatch split (JS stones would need TS configs + a types-to-schema tool —
a future prerequisite, not in uzjf).
