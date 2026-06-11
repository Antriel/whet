---
# whet-3m64
title: Token-efficient CLI logging (auto-quiet on non-TTY)
status: completed
type: task
priority: normal
created_at: 2026-06-09T16:17:51Z
updated_at: 2026-06-11T15:43:04Z
---

## Problem

Whet's logging is tuned for the author watching a terminal, which makes piped/scripted/agent use noisy and token-expensive:

- `Log.stream` defaults to `js.Node.process.stdout`, and in pretty mode `Log.stream = PinoPretty.call()` — **also stdout, with ANSI color**. So lifecycle chatter and the command's actual result are interleaved on the **same stream, in color**.
- Default `logLevel = Info` (`src/whet/Log.hx`), so per-run lifecycle logs ("Loading project", "New project created", "Resolved project path" — emitted from `src/whet/Whet.hx`) always print.
- Pretty/color stays on even when output is piped (not a TTY).

Net effect: every piped `npx whet <cmd>` ships ANSI codes + INFO preamble around the real output. Pure waste for machine consumers.

## Decision (agreed 2026-06-09 with Peter)

**Keep interactive (TTY) behavior exactly as-is** — Peter relies on seeing the project load and which stones generated (catches "why is that stone generating for an unrelated output? is there a dependency I missed?" moments). Only change behavior when output is **not** a TTY.

- When `!process.stdout.isTTY`: default to `--no-pretty` (no color) **and** raise the default level to `warn`.
- **Explicit flags always win.** If the user passed `-l/--log-level` or `--no-pretty` (or the inverse), honor it. Auto-quiet only applies when the user did NOT set level/pretty themselves — so `npx whet ... -l info 2>logs.txt` still narrates when explicitly asked.
- Detection/level-defaulting lives in `Whet.hx` `main()`/`init()` where `--log-level`/`--no-pretty` are already handled — apply the TTY default only when those options are still at their unset/default value.

## Also consider: demote lifecycle logs Info → Debug

"Loading project", "New project created", "Resolved project path" etc. in `Whet.hx`/`Project.hx` are per-run chatter; moving them to `debug` keeps them out of normal interactive runs too while staying available via `-l debug`. (Optional / discuss — Peter likes seeing "project loaded".) Decide whether to keep these at info (only suppressed by non-TTY auto-quiet) or demote.

## Optional polish (Peter leaned AGAINST, left undecided)

Route `Log.stream` to **stderr** so results (stdout via `console.log` / `process.stdout.write`, e.g. `schema`, `bundle-size`, the ScryStone introspection verbs) are never contaminated by log lines, even warnings/errors. Invisible to humans in a terminal (same console); also makes `npx whet bundle-size > report.txt` capture just the report. Caveat: stdout/stderr interleave ordering not guaranteed. **Do NOT implement unless Peter opts in** — he leaned toward keeping logs on stdout.

## Acceptance criteria / todos
- [ ] In `Whet.hx`, detect non-TTY (`!process.stdout.isTTY`) and, only when the user did not explicitly set them, default log level to `warn` and disable pretty/color
- [ ] Verify explicit `-l <level>` / `--no-pretty` / `--pretty` still override the auto-quiet default
- [ ] Add `-q/--quiet` shorthand (= warn + no-pretty) and/or honor `WHET_LOG_LEVEL` env for CI
- [ ] Decide on demoting lifecycle Info logs → Debug (get Peter's call)
- [ ] Leave stderr routing OUT unless Peter opts in (note it here if he does)
- [ ] Confirm interactive TTY runs are byte-for-byte unchanged

## Reframed 2026-06-11 (with Peter) — IMPLEMENTING

Discussion landed on **stderr routing as the primary, load-bearing change** (not optional polish), because Whet core already emits machine-parseable results on stdout (`schema` cmd, ScryStone introspection verbs) and the logger shares that stream — so a single warn mid-run corrupts JSON. stderr split fixes it at any level and the stdout/stderr interleave caveat is a non-issue for machine consumers (they read stdout, ignore/capture stderr separately; humans see both merged in the terminal exactly as today).

Decisions:
- `Log.stream` default → `process.stderr` (Log.hx). PinoPretty routed to stderr via `{ destination: 2 }` (Whet.hx).
- Keep non-TTY auto-quiet (`warn` + no color) when user didn't explicitly set level/pretty. Explicit `-l`/`--log-level` (incl. `WHET_LOG_LEVEL` env) and `--no-pretty` win; `-q/--quiet` forces quiet.
- Add `-q/--quiet` flag + `WHET_LOG_LEVEL` env (via Option.env).
- **DROP** the Info→Debug lifecycle demotion — stderr routing makes it unnecessary; keep "Loading project" etc. at info (Peter likes seeing them interactively, now on stderr).
- Introspection verbs + new `stone-cat` stay in ScryStone (scry-app), NOT Whet core — keeping core small; port later if needed.

## Summary of Changes (all acceptance criteria resolved)

- `src/whet/Log.hx`: `Log.stream` default `process.stdout` -> `process.stderr`.
- `src/whet/Whet.hx`: `-l/--log-level` now also reads `WHET_LOG_LEVEL` env (Option.env); added `-q/--quiet`; non-TTY auto-quiet to `warn` + no-color unless the user set level/pretty explicitly; pretty output routed to stderr via `PinoPretty.call({ destination: 2 })`.
- Decision: DROPPED the Info->Debug lifecycle demotion (stderr routing makes it moot; kept at info so interactive runs still narrate). Peter opted IN to stderr routing.
- Verified: stdout free of logger lines + ANSI on success and error paths; logs on stderr; override matrix 5/5 (auto-quiet / -l / WHET_LOG_LEVEL / -q / -l debug); pino-pretty->fd2 smoke test; 175/175 tests pass.
- NOT committed yet (awaiting Peter).
