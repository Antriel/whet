---
# whet-g0xu
title: Router.getHash fast path for unfiltered queries
status: completed
type: feature
priority: normal
created_at: 2026-05-28T13:29:21Z
updated_at: 2026-05-28T13:34:39Z
---

Avoid full enumeration (and thus full Stone generation) when Router.getHash is called with no query pattern. Replace serveId-folding with merge(child hashes) + hash(static route structure), recursing into child routers.

## Summary of Changes

Added a fast path to `Router.getHash` (`src/whet/route/Router.hx`) for `pattern == null`:

- New `getUnfilteredHash()` computes the hash without enumerating ids. For each route it builds a token binding the static route structure (`routeUnder | filter.pattern | extractDirs.pattern`) to the source's own `getHash()`, then sorts the tokens and merges them.
- This avoids `get()` -> `listIds()`, which for a stone lacking `list()` falls back to a full `getSource()` generation. Stones with a cheap custom `generateHash` (e.g. ScrySkinsOptimizer) are no longer generated just to compute a router hash.
- Per-route binding keeps it false-hit-safe; sorting tokens preserves the existing route-order-independence contract.
- Recurses through child routers via their own `getHash()`.

Path 2 (literal-id filter probe) was intentionally dropped — narrow value, `list()` already covers it.

Tests:
- Updated diamond test in `test/memo-context.test.mjs`: pure hashing now generates nothing (`generateCount == 0`).
- Added test in `test/source-hash.test.mjs`: router hashing a stone with cheap hash + no `list()` does not generate, and the hash still moves when the stone's id-set/content changes.

Full suite: 157 pass.
