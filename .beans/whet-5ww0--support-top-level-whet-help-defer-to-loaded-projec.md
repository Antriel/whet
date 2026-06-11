---
# whet-5ww0
title: Support top-level `whet --help` (defer to loaded-project help)
status: completed
type: feature
priority: normal
created_at: 2026-06-11T13:29:29Z
updated_at: 2026-06-11T13:31:54Z
---

## Problem

`npx whet --help` only shows commander's built-in global help (global options, no project commands) because commander consumes `--help`/`-h` during the FIRST `program.parse()` in `Whet.main()` — which runs BEFORE the project module is imported. The real help (with project commands) only appears via the `help` *command*, which is processed in the SECOND pass (`initProjects`) after the project loads. This trips users up.

Subcommand help (`whet greet --help`) already works because `passThroughOptions` defers options that come after the first operand into the second pass.

## Fix

Defer the top-level help option to the second pass, just like the `help` command:

- [x] `Whet.main()`: add `.helpOption(false)` so the first parse does NOT consume `-h/--help`; with `allowUnknownOption(true)` it passes through into `program.args`.
- [x] After first parse, compute `topLevelHelp` from `getCommands(program.args)[0]` (first segment starts with `-h`/`--help`).
- [x] `initProjects()`: re-enable help (`program.helpOption('-h, --help', ...)`) before the command loop so the second-pass `parseAsync(['--help'])` outputs full help.
- [x] `nextCommand` catch: also swallow `commander.helpDisplayed` (the `--help` option path) in addition to `commander.help` (the help command path).
- [x] Project-load-failure path: if `topLevelHelp`, show clean `program.help()` without the scary error (preserves old behavior of `whet --help` in a dir with no/broken project).

## Verification (prototyped against commander directly)

- `helpOption(false)` -> `--help`/`-h`/`-p x --help` all land in `program.args`.
- Re-enabling + replaying initProjects' `parseOptions`+`parseAsync` flow shows full help incl. project commands, throws `commander.helpDisplayed`.
- `.help()` method still works with help option disabled (throws `commander.help`).
- Narrow change: subcommand help and `--version` paths unaffected.

## Summary of Changes

Implemented in `src/whet/Whet.hx`. Top-level `whet --help`/`-h` now defers to the second (post-project-load) pass and renders full help including project commands, matching the `help` command. Subcommand help (`whet greet --help`), `--version`, and normal commands unchanged. Broken/missing project + top-level help prints clean global help without the load error. Added `test/cli.test.mjs` coverage asserting `--help`/`-h` surface project commands. Full suite: 174 pass.
