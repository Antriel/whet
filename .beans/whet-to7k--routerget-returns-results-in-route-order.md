---
# whet-to7k
title: Router.get() returns results in route order
status: completed
type: bug
priority: normal
created_at: 2026-11-05T08:51:30Z
updated_at: 2026-11-05T09:09:53Z
---

`Router.getResults` pushed into a shared array inside each route's `listIds().then`, so `get()` returned results in listing *completion* order. Stones that pack what a router hands them got a different output under the same hash (gooye-2 MSDF atlas: `gooye-2/MSDF_FONT_ORDER_HANDOFF.md`; earlier per-stone patch: scry `f5d3eef` FormatFilterStone).

Fix: each route resolves to its own array, joined in route order after `Promise.all`. Also removes the `new Promise` wrapper whose `rej` was never called, so a failing listing hung `get()` forever instead of rejecting.

- [x] Per-route result arrays joined in route order (`Router.hx`, `StoneStore.hx` override signature)
- [x] Tests: reverse-delay listings incl. nested router; listing rejection propagates
- [x] Peter reviewed

## Summary of Changes

`Router.getResults(filters)` drops the shared `results` argument: each route resolves to its own array (a nested router returns its own, already ordered), joined in route order after `Promise.all`. Filter push-down and early exit from the 2022 refactor (`23c0f8c`) are unchanged; the only added cost is one small array per route and one copy per nesting level. `StoneStore.getResults` override updated. Listing rejections now propagate instead of hanging. Two tests in `test/router.test.mjs`, both fail on the old code; full suite 297/297.

Left to Peter: publish whet, bump `node_modules/whet` in gooye-2, re-sync the msdf chain (hashes do not move, so downstream needs a refresh; see `gooye-2/MSDF_FONT_ORDER_HANDOFF.md`).
