---
# whet-4bn2
title: Capture Stone instantiation source (construction stack) natively
status: todo
type: feature
priority: low
created_at: 2026-06-10T09:04:52Z
updated_at: 2026-06-10T09:04:52Z
---

Proposal: optionally record where each Stone is instantiated (the JS construction call stack) so tooling can jump from a stone to its static config site. Explored & shipped first as a Scry-side monkey-patch; this bean tracks pulling the ~8-line core into Whet itself.

## What
At Stone construction, capture an `Error` stack and keep the frames that live in user/project code (filter out Whet's own `bin/` runtime, genes trampoline, node internals). Expose them on the instance (e.g. `originStack: Array<{file,line,column,fn}>`) and optionally in `Project.describeStones()` / `StoneDescription`.

## Why
Much stone config is hardcoded in `Project.mjs` and wrapper modules (routing, ids, fixed wiring) and isn't editable from the Scry editor. "Where is this configured?" is currently a grep. A construction-site stack turns it into a click (Scry inspector button) or one CLI call. Storing the *whole* filtered stack (not just one frame) makes wrapper/StoneFactory flows resolve to the real config site and shows the Project.mjs -> wrapper -> stone path.

## How (native, ~8 lines)
In `Stone.new` (src/whet/Stone.hx), same trick Whet already uses in `Project.hx` for rootDir auto-detect:
- swap `Error.prepareStackTrace` to return CallSite[]; bump `stackTraceLimit`; `new Error().stack`; restore in finally.
- map CallSites -> {file,line,column,fn}; drop frames whose file is null / `node:` / matches `whet[/\]bin[/\]`.
- store on the instance; guard behind a flag/env so it's zero-cost in production builds if desired (one Error per stone at construction only — negligible, but opt-in keeps it clean).

## Current state (already working, Scry side)
Implemented without touching Whet by monkey-patching `Stone.prototype[Register.new]` from `scry/whetstones/utils/stoneSourceTracking.mjs` (imported at the top of Project.mjs). Genes compiles construction to a *symbol-keyed method* and subclasses call `super[Register.new](config)`, which resolves dynamically through the prototype — so overriding it on `Stone.prototype` is seen by every subclass. Validated against the real genes runtime: direct `new JsonStone()` -> 1 frame at the call site; via a wrapper fn -> 2 frames (inner `new` + the wrapper's call site); all Whet-internal frames filtered. Scry also exposes `whet stone-source <id>`.

## Caveat / why this is a proposal, not a given
The monkey-patch hinges on genes' `[Register.new]` symbol-method dispatch. If Whet is ever ported off Haxe/genes (e.g. native TS with real ES classes), `super()` binds the parent at definition time and can't be intercepted from outside — source tracking would *have* to live in the Stone constructor. Doing it natively here future-proofs that, at the cost of carrying dev-tooling concerns in core. Deferred (low priority) until the Scry-side version proves its weight.

## Tasks
- [ ] Decide: keep as Scry monkey-patch, or land natively in Stone.hx
- [ ] If native: implement capture+filter in Stone.new behind an opt-in flag/env
- [ ] If native: add `originStack` to StoneDescription so describeStones carries it
- [ ] Retire the Scry monkey-patch once native path exists
