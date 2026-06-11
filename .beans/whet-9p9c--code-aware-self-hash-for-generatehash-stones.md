---
# whet-9p9c
title: Code-aware self-hash for generateHash() stones
status: completed
type: task
priority: normal
created_at: 2026-06-09T16:17:22Z
updated_at: 2026-06-11T13:54:55Z
---

## Problem

Whet caches by `SourceHash`, which merges a stone's **config + dependency** hashes. It does **not** include the stone's own `generate()` code. So editing a stone's generation logic without changing its config/inputs leaves the cached output **stale** — the build keeps serving the old result. This bites every project and contributor (a recurring "why didn't my change show up?" moment) and currently requires a manual regenerate from the Scry editor (or `whet refresh <id>`, a new ScryStone CLI verb).

## Key insight (scopes the fix)

Staleness affects **only** stones that override `generateHash()` — the optimization path that derives a hash from config to avoid generating just to hash. Stones **without** `generateHash()` already hash their output bytes (`SourceHash.fromBytes` of generated data, see `Stone.generateSource`), so editing their `generate()` changes the bytes → hash changes → cache busts automatically. The fix therefore only needs to touch the `generateHash()` path.

## Proposed design

In `src/whet/Stone.hx`, `finalMaybeHash()` (around line 232): when `generateHash()` returns a non-null hash, `.add()` a hash of the stone's own overridable method sources before finalizing.

- Compute `codeHash(this)` = `SourceHash.fromString` (or fromBytes) of the concatenated `Function.prototype.toString()` of the stone's own methods: `generate`, `generatePartial`, `list`, `generateContext`, `generateHash`. Walk the prototype chain from `this` down to **but excluding** `Stone` (so unrelated base-class methods don't participate, and whet-core upgrades only bust stones whose own compiled bodies changed).
- **Memoize per class** (keyed by constructor) — compute once per process. This addresses the performance worry: with memoization it's a one-time `.toString()` + hash per stone class.
- Only mix it in on the `generateHash()` != null branch. When `generateHash()` returns null, do nothing (output-byte hash already reflects code).

### Why `.toString()` over file hashing
File-source hashing (`import.meta.url` etc.) is the ugly path: ambiguous which-file-is-the-class, misses imports, bundler-sensitive. `.toString()` reads the actual function body whether the stone is a user `.mjs` or Whet's compiled `bin/whet.js`, with no file resolution.

## Escape hatch

Add optional `config.codeVersion` (string/number) mixed into the hash when present — for the known limitation that `.toString()` does NOT capture changes in **imported helper modules** a `generate()` delegates to (e.g. scry's `autocompose/strategy.mjs`, `palette.mjs`). Bump `codeVersion` to force-bust in those rare cases.

## Accepted tradeoffs
- One-time full rebuild of all `generateHash()` stones on first deploy.
- Comment/whitespace-only edits to a covered method bust the cache (rare, cheap false positive; not worth normalizing).
- Helper-module edits need a `codeVersion` bump (documented).

## Decision
Agreed on 2026-06-09 with Peter (Whet author): implement **auto-on** for all `generateHash()` stones — opt-in reintroduces the "forgot to enable it" failure mode this is meant to fix. Add a class-level opt-out flag only if some stone misbehaves.

## Acceptance criteria / todos
- [x] Add memoized `codeHash(stone)` helper (per-class, walks prototype chain `this`..exclusive-of-`Stone`, hashes `.toString()` of generate/generatePartial/list/generateContext/generateHash)
- [x] Mix it into `finalMaybeHash()` only when `generateHash()` returns non-null
- [x] ~~Support optional `config.codeVersion`~~ — **removed on 2026-06-11 (Peter): noise, trivially replicated via a config change or a version constant folded into `generateHash()`.** Helper-module limitation documented in `Stone.codeHash` doc-comment instead.
- [x] Opt-out flag: instance `Stone.ignoreCodeHash` (mirrors `ignoreFileHash`; instance over static for per-stone control + consistency)
- [x] Add a test (`test/code-hash.test.mjs`): covers covered-body edit busts, unrelated method does not, identical source matches, `ignoreCodeHash` opts out, and no-`generateHash()` byte path unaffected
- [x] One-time-rebuild behavior: no CHANGELOG file exists in the repo; documented in `finalMaybeHash` / `codeHash` doc-comments and this bean instead

## Summary of Changes

Implemented code-aware self-hashing for `generateHash()` stones in `src/whet/Stone.hx`:

- Added `Stone.codeHash(stone)`: hashes the concatenated `Function.prototype.toString()` of the stone's own `generate`/`generatePartial`/`list`/`generateContext`/`generateHash` methods, walking the prototype chain from the instance down to — but excluding — `Stone` (identified by ownership of the final `finalizeHash` method). Memoized per class via a static `js.lib.Map` keyed by constructor.
- Mixed `codeHash(this)` into `finalMaybeHash()` **only** on the non-null `generateHash()` branch (`hash.add(codeHash(this))`), gated by the new `ignoreCodeHash` opt-out. Byte-hash stones are untouched — their output already reflects code changes.
- Added `public var ignoreCodeHash:Bool = false` (mirrors `ignoreFileHash`).
- `config.codeVersion` was implemented then removed per Peter's request as unnecessary noise.

All 171 tests pass (5 new in `test/code-hash.test.mjs`). Tradeoff retained: first deploy triggers a one-time rebuild of all `generateHash()` stones; comment/whitespace-only edits to covered methods bust the cache (cheap, rare).

## Update (2026-06-11): broadened from a fixed method list to all own functions

Code review with Peter surfaced a gap in the original design: hashing a fixed `CODE_HASH_METHODS` list missed the stone's *own private helper methods* (e.g. `generate()` calling `this.buildAtlas()` — editing `buildAtlas` left output stale). Considered whole-file/module hashing but rejected it: the compiled side would over-invalidate (a release re-hashes the bundle → busts every stone), and there's no reliable runtime way to map a loose `.mjs` class back to its source file.

Final design: `Stone.codeHash` now hashes **every own method** (instance/prototype methods, accessors, and static methods) of the stone's class and ancestors down to — but excluding — `Stone`, via `Function.prototype.toString()`. Deliberately over-invalidates (any method edit busts) since stale output costs more than a redundant rebuild, and removes the brittle list.

Implementation notes:
- Descriptor-based (`getOwnPropertyDescriptor`) so getters/setters are read by source, never invoked (the live `cache` getter throws on a detached instance — proven by a probe).
- Boundary uses a `finalizeHash`-ownership sentinel on the prototype, reliable across both ES-class user stones and the modular Haxe output (whose constructor/prototype chains aren't linked until instantiation — verified on live `JsonStone`/`Files` instances).
- Skips Haxe-internal `__`-prefixed props (`__class__`, `__super__`, `__name__`); `__super__` would otherwise pull the parent constructor's source into every subclass's hash.
- Limitation now: only *module-level free functions* and *imported modules* are uncaptured (not reachable by reflection). Instance-own function props are intentionally excluded so the per-class memo stays sound.
- Tests extended to 8 (helper-method participation, static-method participation, two file-cache e2e round-trips proving real regenerate-on-edit / reuse-on-identical). Full suite: 175 pass.
