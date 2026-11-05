---
# whet-mi7g
title: Upgrade minimatch 11 / dts2hx, regenerate externs
status: completed
type: task
priority: normal
created_at: 2026-11-05T09:42:43Z
updated_at: 2026-11-05T09:44:03Z
---

minimatch 10 -> 11 made `Minimatch#matchOne` private (`#matchOne`), breaking `Filters.isPathPossible` in Router (`TypeError: f.filter.matchOne is not a function`).

- [x] Replace `matchOne` with public `match(path, partial=true)`
- [x] Upgrade dts2hx, regenerate externs (`npm run devinit`)
- [x] Fix any build breakage from regenerated externs
- [x] Build + full test suite green

## Summary of Changes

- `Router` `Filters.isPathPossible`: replaced the now-private `matchOne` loop (with hand-rolled negate/flipNegate handling) with `filter.match(pathSoFar.join("/"), true)`; returns true early for empty `pathSoFar`.
- dts2hx 0.20.0 -> 0.34.0, externs regenerated.
- Regenerated commander extern types `opts()` as `opts<T:DynamicAccess<Dynamic>>():T`; `Whet.hx` now types the result as `Dynamic`.
- dts2hx emits pino-pretty `customPrettifiers` as `DynamicAccess<Prettifier> & {...}`, which Haxe cannot type. Dropped pino-pretty from `devinit`, added hand-written `src/whet/PinoPretty.hx` (only `call({destination})` is used). This also removes the pino-abstract-transport/colorette externs and their NodeJS-namespace errors.
- Build clean, 297/297 tests pass.
