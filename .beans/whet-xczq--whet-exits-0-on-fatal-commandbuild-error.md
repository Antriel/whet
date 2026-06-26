---
# whet-xczq
title: Whet exits 0 on fatal command/build error
status: completed
type: bug
priority: high
created_at: 2026-06-26T14:34:41Z
updated_at: 2026-06-26T14:39:23Z
---

The command chain's catchError in Whet.hx swallows rejections into a log line without setting process.exitCode, so shells/CI/agents see exit 0 on hard build failures. Same issue on the project-load failure path.

## Summary of Changes

Fixed in `src/whet/Whet.hx`:

1. **Command chain** (`nextCommand` catch, ~line 156): on a non-help rejection, after logging, set `(cast js.Node.process).exitCode = 1`. Used `exitCode` rather than `process.exit(1)` so pending logs flush and the chain unwinds cleanly.
2. **Project-load failure** (`init` catchError, ~line 92): set `exitCode = 1` when the failure is not a top-level `--help` request. Top-level help still exits 0 (load error intentionally ignored there).

Verified:
- failing command → exit 1
- broken project import → exit 1
- successful command → exit 0 (unchanged)
- full suite: 181/181 pass
