---
# whet-b2v6
title: withSpan leaks span (and stone lock) on synchronous throw from fn()
status: completed
type: bug
priority: high
created_at: 2026-05-29T11:54:27Z
updated_at: 2026-05-29T11:54:31Z
parent: whet-mosz
---

Profiler.withSpan emitted the Start event then ran fn() inside a .then()/.catchError() chain. If fn() threw *synchronously* (or returned a non-Promise), neither callback ran, so emit(End) was skipped: AsyncLocalStorage.run() re-throws sync exceptions, so withSpan threw synchronously. Start had already been broadcast over WS, End never was, so the client's activeSpans map (build-activity.svelte.ts / build-progress-plugin.mjs) kept the span id forever — no timeout/reconciliation exists client-side.

Real-world trigger: the `if (!this.locked) throw` guard at the top of Stone.generateSource / generatePartialSource (wrapped in withSpan(Generate/GeneratePartial) by BaseCache) firing during a lock race under concurrent generation. A user stone's generate() throwing synchronously does it too.

Worse: in Stone.acquire, `profilerWithSpan(LockHeld, run).finally(runNext)` — if run() threw synchronously, withSpan threw before `.finally(runNext)` was attached, so `locked` stayed true forever and the stone deadlocked (every later acquire queued, leaking a LockWait span each time).

## Summary of Changes
- Profiler.hx: wrapped the fn() invocation + then/catchError chain in try/catch inside context.run; on a synchronous throw it finalizes the span and returns Promise.reject(e). Extracted finishSpan(span, status) helper (records, updates stats on Ok, emits End).
- Converting the sync throw to a rejected promise also lets `.finally(runNext)` attach in acquire, so the lock is released.
- Added two regression tests in test/profiler.test.mjs (End emitted on sync throw; lock released after sync throw under acquire).
- Rebuilt Haxe -> bin/. Full suite: 159/159 pass.
