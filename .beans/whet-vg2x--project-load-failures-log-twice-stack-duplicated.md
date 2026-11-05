---
# whet-vg2x
title: Project load failures log twice, stack duplicated
status: completed
type: bug
priority: normal
created_at: 2026-08-17T15:52:21Z
updated_at: 2026-11-05T09:22:41Z
---

Noticed 2026-08-17 while working on whet-7486. Same shape of bug (one failure, several log records), different code path — whet-7486 fixed the stone/command boundary only, this one is the project **load** path and was left alone.

## Symptom

Any project that throws on import logs **two** level-50 records, and the JS stack appears twice:

```
{"level":"50","time":...,"msg":"Error loading project.","error":{"type":"Error","message":"Must supply config and a name.","stack":"Error: Must supply config and a name.\n    at Project.<anonymous> (...)\n    at new res (...)\n ... "}}
{"level":"50","time":...,"msg":"Error: Must supply config and a name.\n    at Project.<anonymous> (...)\n    at new res (...)\n ... "}
```

The second record has the whole stack as its `msg`, which is also what makes it ugly — a multi-line string in the `msg` field rather than a structured `error` field.

## Cause

`src/whet/Whet.hx:96-102`:

```haxe
if (!topLevelHelp) {
    Log.error("Error loading project.", { error: e });
    if (e is js.lib.Error) Log.error((e:js.lib.Error).stack);   // <- this line
    (cast js.Node.process).exitCode = 1;
}
```

The second call is redundant. `Log.replacer` (`Log.hx:51-56`) already serialises an Error as `{type, message, stack}`, so the first record carries the stack.

**It is redundant for the pretty path too**, which is presumably why it was added. Verified against the installed pino-pretty 13.1.3: given a record with a nested error object it renders the stack, indented and formatted:

```
[17:51:33.582] ERROR: Error loading project.
    error: {
      "type": "Error",
      "message": "boom",
      "stack":
          Error: boom
              at frameA
              at frameB
    }
```

Also checked and **not** a factor: pino-pretty's `ERROR_LIKE_KEYS` is `['err', 'error']` (`node_modules/pino-pretty/lib/constants.js:16`), so the two key spellings whet uses at different call sites (`err:` in `Stone.hx`, `error:` everywhere else) render identically. No need to normalise them for this.

## Why it is dead code

Git history explains it. The extra log was added **2022-05-06** (`2112d5f`, "route fixes"). `Log.replacer` only gained the `stack` field **2022-09-07** (`bb822ce`, "log errors in a way compatible with pino-pretty"). So it was a workaround for stacks not being serialised at all, and became redundant four months later when the replacer was fixed — but was never removed.

## Work

- [x] Delete `Whet.hx:98`. Confirm the load failure then produces exactly one record that still contains the full stack.
- [x] Confirm the `topLevelHelp` branch is unaffected (a load error during `whet --help` is deliberately swallowed and still exits 0).
- [x] Quick sweep of the other error call sites for the same pattern — `Source.hx:90`, `Source.hx:111`, `Stone.hx:210`, `FileCache.hx:165`, `FileCache.hx:171`, `FileCache.hx:176`. They look like single logs, but confirm none of them pairs a structured log with a bare-stack log.

## Not in scope

Whether `Log.replacer` should keep emitting `stack` at all. It should — with a short `message` the stack is genuinely useful, and that was settled in whet-7486 (the replacer stays a dumb format converter; producers decide what their errors carry).

## Summary of Changes

Done 2026-11-05, while closing whet-7486 (commit `e6c98aa`, which was filed under a duplicate bean, whet-nv8o, now scrapped).

- Removed the bare-stack `Log.error` in the load `catchError`. A project that throws on import now gives exactly one level-50 record, the full stack is still inside `error`, and the exit code is still 1.
- `topLevelHelp`: `whet -p <throwing project> --help` prints the help with no log records and exits 0. Unchanged.
- Sweep: every listed site, and every other `Log.error`/`Log.warn` in `src/whet`, logs once. None pairs a structured log with a bare-stack log. Found a different defect on the way: `FileCache.hx:298` passed the Error as the record itself (`Log.error(msg, err)`), so the Error's non-enumerable `message` and `stack` were dropped. Changed it to `{ error: err }`.

297/297 tests pass.
