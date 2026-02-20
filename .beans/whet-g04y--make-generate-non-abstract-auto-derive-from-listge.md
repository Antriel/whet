---
# whet-g04y
title: Make generate() non-abstract, auto-derive from list()+generatePartial()
status: completed
type: feature
priority: normal
created_at: 2026-02-20T15:00:25Z
updated_at: 2026-02-20T15:03:33Z
---

Make `generate()` non-abstract in Stone.hx with a default implementation that calls `list()` + `generatePartial()` for each ID. This lets stones that implement per-item generation skip implementing `generate()`.

## TODO

- [x] Stone.hx: Change `generate` from abstract to concrete with default that calls list()+generatePartial()
- [x] SharpStone.mjs: Remove `generate()`, add `generatePartial()`, optimize to fetch single PNG
- [x] Add test for auto-derived generate() (stone with only list+generatePartial, no generate override)
- [x] Build and verify all tests pass

## Summary of Changes

Made `generate()` non-abstract in Stone.hx with a default implementation that calls `list()` then `generatePartial()` for each ID. Stones can now implement just `list()` + `generatePartial()` instead of `generate()`.

### Files changed:
- **src/whet/Stone.hx**: `generate` changed from abstract to concrete with auto-derive default
- **src/whet/stones/{Files,JsonStone,RemoteFile,Zip}.hx**: Added `override` keyword
- **src/whet/stones/haxe/{Hxml,HaxeBuild}.hx**: Added `override` keyword
- **SharpStone.mjs** (external): Replaced `generate()` with `generatePartial()` — fetches single PNG from router instead of all
- **test/partial.test.mjs**: Added `PartialOnlyStone` test class and 3 tests for auto-derived generate()
