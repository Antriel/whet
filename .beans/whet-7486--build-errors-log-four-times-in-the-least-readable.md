---
# whet-7486
title: Build errors log four times, in the least readable encoding
status: completed
type: task
priority: normal
created_at: 2026-08-17T14:16:37Z
updated_at: 2026-11-05T09:18:25Z
---

Noted 2026-08-17 from a bingo-2026 session. **Investigated 2026-08-17** — root cause found, design settled, see below.

A single Haxe compile error currently reaches the terminal as roughly four copies of the same text, JSON-escaped. Observed from `npx whet --build playtest build`:

- **Two level-50 lines.** `Error while generating.` (stone: `game.hxml-build:whet.stones.haxe.HaxeBuild`) and then `Error while executing command.`. Whet's command-level error handler and the HaxeBuild stone each log it independently.
- **Each line carries the text twice**, once in `message` and again inside `stack`.
- **The payload is ANSI colour codes JSON-escaped**, e.g. `[30;41m ERROR [0m src/playtest/Hooks.hx:149: characters 9-66` — because the game's hxml sets `message.reporting=pretty` and `message.color` (see `GameHaxeBuild.mjs` in bingo-2026 and gooye-2, both set them).

Net effect: a fundamentally three-line message costs a couple of KB of near-unreadable output. This matters because Whet's non-TTY auto-quiet exists specifically to make agent runs cheap and legible — an error that is *present but expensive to parse* undercuts that on the one path where output matters most.

## Root cause: one bug, not two

`HaxeBuild.hx:25` does `new js.lib.Error(stderr)` — **the entire pretty, coloured compiler output becomes the Error's identity**. Everything else follows mechanically:

- `Log.replacer` (`Log.hx:51-56`) serialises every Error as `{type, message, stack}`. V8's `stack` header is `${name}: ${message}`, so the blob lands twice per line. This is structural to all errors, not HaxeBuild-specific.
- `Stone.handleError` (`Stone.hx:223`) and the command boundary (`Whet.hx:173`) each log it — two lines.
- `Json.stringify` (`Log.hx:47`) is what escapes ``. Inherent to the NDJSON log format, so the fix is *don't put ANSI in the record*, not *make the log stop escaping*.
- In `serve` it is **not fixed at four**: `UwsServerStone.mjs:319` and `:424` each log the full error **per failing request**, so a page pulling N assets multiplies it.

The same fact is why pretty could not simply be switched off: `BuildStatusPlugin` serves `error.message` to `/api/build-status`, and `build-error-plugin.mjs:210` feeds it to `ansiToHtml`. One string, two incompatible consumers.

## The caveat dissolves — Haxe has a second, independent message channel

`message.log-file` / `message.log-format` are **fully independent of `message.reporting`**. Verified on Haxe 5.0.0-preview.1 (the games) and 4.3.4 (whet's own `.haxerc`) — both support it:

| Config | stderr (piped) | log file |
|---|---|---|
| `reporting=classic` | `Main.hx:3: characters 9-34 : String should be Int` — plain, 1 line/diagnostic | — |
| `reporting=classic` + `log-format=pretty` + `message.color` | still plain | full pretty output **with ANSI** |
| `reporting=pretty` + `message.color` | ANSI blob (today) | — |

Also verified: the log file is **truncated per compile** (two failing runs produce two entries, not four) and truncated to 0 bytes on success — no stale-state hazard. `classic` carries no colour on either version, which sidesteps the fact that the colour default flipped between 4.3 (on) and 5 (off).

So both consumers get their preferred form **from the compiler itself** — no stripping, no reformatting, no regex over pretty output.

## Design

- [x] **HaxeBuild owns the message channel.** `build()` appends to the exec command (not to `config.defines`): `-D message.reporting=classic`, `-D message.log-file=<abs path>`, `-D message.log-format=pretty`, `-D message.color`. Skip any the user's hxml already sets. **Must be appended at command assembly, not merged into `HxmlConfig.defines`** — `Hxml.generateHashSync()` hashes `getBaseArgs()`, so putting them in config would bust every build cache and leak a machine-specific log path into the generated `.hxml` file (which is a real source others may use for completion).
- [x] **Log file path**: absolute, under `.whet/.temp/haxe-messages/<safeId>.log`, keyed on `config.id` so concurrent builds do not collide. `Utils.ensureDirExist` before exec.
- [x] **Error shape.** On failure build a short plain message (`Haxe build failed (id "game.hxml"): <classic lines>`) and attach the pretty text as a separate property (`haxeLog`), read from the log file. Fall back to stderr when the file is missing/empty (older Haxe, or user-overridden defines).
- [x] **Drop HaxeBuild's own `stack`** — it points into an `exec` callback and says nothing about the compile error.
- [x] **Default `handleError` annotates instead of logging** (`Stone.hx:222-225`): attach the stone id to the error and reject, no `Log.error`. The command boundary then logs **once**, with the stone id included. One line, no information lost, no arbitration over which layer "owns" reporting.
- [x] **Games drop `message.reporting=pretty` + `message.color`** from `GameHaxeBuild.mjs` (bingo-2026, gooye-2). Under Haxe 5 the negation route is a trap — `message.no-color` is deprecated and emits its own warning that then pollutes output; not setting `message.color` is the correct move. Another argument for whet owning these rather than games negating them.
- [x] **`BuildStatusPlugin` serves `err.haxeLog ?? err.message`.** The HTML page, `ansiToHtml` and `addVsCodeLinks` are **untouched** — still coloured, still structured.

## Decisions taken

- **`Log.replacer` is not changed.** Its job is converting an Error to the shape pino expects. Whether `stack` repeats `message` is a V8 default-format convention with two escape hatches — the header is computed lazily on first `.stack` access *then frozen* (read-before-mutate keeps stale text), and `Error.prepareStackTrace` can be replaced wholesale (`source-map-support` does exactly this, and the games build with source maps). Not an invariant, so it must not be load-bearing logic in a generic formatter. With a one-line message the doubling costs ~60 bytes and the stack stays genuinely useful.
- **No TTY-conditional formatting.** Auto-quiet is right for verbosity, but this split is not about who is watching: the dev server is non-TTY and *wants* pretty, the agent run is non-TTY and wants plain. A stable two-channel arrangement is simpler than a conditional and stops the terminal and the error page competing.
- **No parsing of compiler output into structured diagnostics.** Considered and dropped — `addVsCodeLinks` already works and structured diagnostics would buy nothing not already had.
- **`handleError` is kept.** Grepped the ecosystem: assignments exist **only** in the legacy `NextRealm/games` repos (SnowFight, Bubbles, HexSweep, HoL, MyHex, test-snowfight) plus one whet test. Zero in gooye-2, bingo-2026, bingo-2025, the-number, FS-mini, scry-app, tannery. It is the direct ancestor of today's mechanism — `SnowFight/client/Project.mjs:350` swaps the served `index.html` for an EJS error page built from `addVsCodeLinks(ansiToHtml(err.message))`; the scry `BuildStatusPlugin` + client overlay replaced that. Deleting a public dynamic method would break those legacy `Project.mjs` files for no gain here, so only its logging is removed. Removal is a separate follow-up if wanted. Those legacy games read `err.message` for their page and will **degrade gracefully** to a plain-but-correct page: `ansiToHtml` on classic text is a passthrough and `addVsCodeLinks` still matches `file:line`.

## Scope note

This bean covers the **whet** changes only. The `BuildStatusPlugin` change lives in the `scry` submodule and the define removal lives in each game's `scripts/GameHaxeBuild.mjs` — tracked separately, per the rule that the repo holding the edited file owns the work.

## Whet side implemented 2026-08-17

`src/whet/stones/haxe/HaxeBuild.hx` (new `messageSetup()` + `makeBuildError()`), `src/whet/Stone.hx` (`handleError` annotates), `src/whet/Whet.hx` (boundary lifts `stone` off the error, since `Log.replacer` reduces an Error to `{type, message, stack}` and would otherwise drop it). Builds clean, 258/258 tests pass.

Measured on a two-error compile, whet CLI, stderr bytes:

| | bytes | lines |
|---|---|---|
| before | 2972 | 2 |
| after, game still setting `message.reporting=pretty` | 720 | 1 |
| after, game defines removed | 359 | 1 |

Verified end to end: `err.stone` survives to the log line, `err.stack` is null, `err.message` is 163 bytes of plain classic text, `err.haxeLog` is 373 bytes of pretty-with-ANSI read from the log file, the log file truncates to 0 bytes on success, the success path and exit codes are unchanged, and the generated `.hxml` source contains **no** message defines (so no cache-hash impact, no leak into the file used for completion).

## Sequencing constraint found — the two remaining items are not both ready

The games depend on published `whet@^0.7.0` (both `bingo-2026` and `gooye-2`), and `node_modules/whet` is 0.7.0. So:

- **`BuildStatusPlugin` (`err.haxeLog ?? err.message`) is safe to land now** — forward-compatible, a no-op against whet 0.7.0, activates when whet ships.
- **Removing the game defines must wait for a whet release.** Doing it against 0.7.0 would strip colour from the build-error page with nothing providing the log-file channel in return — a regression, not an improvement. Order is: release whet, bump the games, then drop the defines.

Note the whet-side change already gives those games a **4x** reduction with no edit at all (2972 → 720 bytes, two lines → one), because the duplicate log line and the repeated `stack` are gone regardless of which reporting mode the hxml picks. The remaining 720 → 359 is what dropping the defines buys.

Also observed in passing, out of scope here: project **load** failures log twice too (`Whet.hx:97-98` logs the error and then its stack as a second record). Same shape of bug, different path — worth its own bean.

## Summary of Changes

Checked 2026-11-05. bingo-2026 is dropped; the games that matter are gooye-2 and lightning-bounce.

- **Whet released**: the whet side shipped and both games depend on and have installed `whet@^0.7.4`.
- **Game defines dropped**: `scripts/GameHaxeBuild.mjs` in both games no longer sets any `message.*` define.
- **BuildStatusPlugin**: the `scry` submodule in both games serves `haxeLog || message`.

Leftovers, owned by other repos (not tracked here): secondary HaxeBuilds still set `message.reporting=pretty` + `message.color`: gooye-2 `scripts/SimulatorBuild.mjs`, lightning-bounce `scripts/LogicTestBuild.mjs` (both `logic-test.hxml` and `headless.hxml`), and reactor `OpfsLogsJsStone.mjs` (`pretty` only). They now cost the 720-byte form instead of 359, and these are the agent-facing headless builds. Removing the defines is safe now, since whet 0.7.4 provides the pretty channel via `haxeLog`.

The load-failure double log noted at the end is fixed in whet-nv8o.
