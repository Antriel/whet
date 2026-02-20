---
# whet-eogt
title: Update commander v9→v14 + CLI smoke tests
status: completed
type: task
priority: normal
created_at: 2026-02-20T07:26:44Z
updated_at: 2026-02-20T07:28:05Z
---

Update commander dependency from ^9.0.0 to ^14.0.0 and add basic subprocess CLI tests.

## Key changes needed

- [ ] Update `package.json` commander version to `^14.0.0`
- [ ] Fix `--help` exit-code bug: only `commander.version` is caught; `commander.helpDisplayed` is not, causing exit 1
- [ ] Build project (`haxe build.hxml`)
- [ ] Create `test/cli.test.mjs` with subprocess smoke tests (`--version`, `--help`, bad flag)
- [ ] Run tests to verify

## Breaking changes from changelog (v9→v14)

- v12: duplicate option/command names now throw — low risk
- v13: `allowExcessArguments` now false by default — adopting stricter behavior (good for users)
- v14: Node.js v20+ required — we're on v24, fine

## Summary of Changes

- `package.json`: bumped `commander` from `^9.0.0` to `^14.0.0`
- `src/whet/Whet.hx`: fixed pre-existing bug where `--help` exited with code 1 — added `commander.helpDisplayed` alongside `commander.version` in the catch handler
- `test/cli.test.mjs`: new subprocess smoke tests for `--version`, `--help`, and unknown option
- Adopted v13's stricter `allowExcessArguments: false` default without workaround — good error feedback for users
- All 101 tests pass
