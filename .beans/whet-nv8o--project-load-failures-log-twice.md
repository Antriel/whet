---
# whet-nv8o
title: Project load failures log twice
status: scrapped
type: bug
priority: normal
created_at: 2026-11-05T09:17:52Z
updated_at: 2026-11-05T09:22:41Z
---

Found while closing whet-7486. `Whet.hx` load-failure handler logs `{error: e}` (which `Log.replacer` already serialises with `stack`) and then logs `e.stack` again as a second record. Drop the second line.

## Summary of Changes

Removed the second `Log.error(e.stack)` in the project-load `catchError` (`src/whet/Whet.hx`). Verified with a project file that throws on import: one level-50 record (was two), stack still present inside `error`, exit code still 1. 297/297 tests pass.

## Reasons for Scrapping

Duplicate of whet-vg2x, which already tracked this bug (the earlier bean search missed it). The fix and its verification are recorded there.
