---
# whet-gyqz
title: Router.getOutputFilter unsound merge drops sibling routes
status: completed
type: bug
priority: normal
created_at: 2026-07-21T15:05:33Z
updated_at: 2026-07-21T15:23:21Z
---

Merging sibling output filters into one flat {extensions, patterns} breaks OR semantics: a sibling that declares patterns turns patterns into a mandatory gate for the whole combined source, so extension-only siblings get skipped by couldMatch.

## Summary of Changes

**Root cause:** `Router.getOutputFilter` (src/whet/route/Router.hx) unioned sibling `extensions` and `patterns` into one flat filter. `OutputFilterMatcher.couldMatch` treats a non-null `patterns` list as a mandatory gate (returns false if a specific query matches no pattern). So once any sibling declared `patterns` (SoundBankStone: `{extensions:['json'], patterns:['soundbank.json',...]}`), extension-only siblings were skipped — e.g. `assets/logo.avif` returned `[]` despite passing the extension stage.

**Fix:** merged `patterns` is set to null when any child has no patterns (name-unconstrained); symmetric guard for `extensions`. Union remains sound as a necessary-condition gate only for the constraint every child shares.

**Test:** `test/router.test.mjs` — "pattern-declaring sibling does not hide extension-only sibling". Reproduces the gooye-2 scenario; fails (0!==1) pre-fix, passes post-fix. Full suite 182/182.

## Follow-up (not urgent)
- Latent cosmetic bug: pattern prefixing does `Path.posix.join(routeUnder, p)` even when routeUnder is a file mount, producing `soundbank.json/soundbank.json`. Harmless now (guard drops these patterns in mixed sets) but wrong if all siblings ever declare patterns.

## Follow-up resolved: file-mount rename bugs

Verified the `routeUnder` join really breaks (probe: `['renamed.json', a, 'soundbank.json']` serves exactly `renamed.json` but advertised `patterns:["renamed.json/soundbank.json"]` — unmatchable). Fixed TWO related file-mount (rename) defects:

1. **Router.getOutputFilter** — a file (non-dir) routeUnder renames the output to exactly that served path. Now contributes `routeUnder` (+ its extension) as the pattern instead of the bogus `join(routeUnder, childPattern)`.

2. **Router.getResults couldMatch pruning** — the leaf-level prune compared the stone's id-space patterns against the served-space query. For dir mounts the `**/` prefix hides this; for a rename to a DIFFERENT basename it falsely rejected the source. Pruning is now gated to dir mounts only — a file mount's served path is already matched authoritatively by `finalize(routeUnder)`. This means e.g. `['sfx.json', soundBank, 'soundbank.json']` (rename to a different name) now works; previously only same-name renames worked by luck.

Made `OutputFilterMatcher.getExtension` public (shared with Router). New test: "file-mount routes advertise their renamed serve path". Full suite 183/183.
