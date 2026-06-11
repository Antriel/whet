---
# whet-3m64
title: Token-efficient CLI logging (auto-quiet on non-TTY)
status: todo
type: task
priority: normal
created_at: 2026-06-09T16:17:51Z
updated_at: 2026-06-09T16:17:51Z
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
