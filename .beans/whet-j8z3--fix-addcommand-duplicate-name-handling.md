---
# whet-j8z3
title: Fix addCommand duplicate name handling
status: completed
type: bug
priority: normal
created_at: 2026-02-20T08:18:53Z
updated_at: 2026-02-20T08:19:14Z
---

Commander.js errors if command names are not unique. When a stone is provided, if the plain \ conflicts with an existing command, fall back to using the alias (\) as the command name instead. If no stone is provided, leave it to commander to error.


## Summary of Changes

- Added `isCommandNameTaken` helper that checks both `.name()` and `.aliases()` of all registered program commands
- In `addCommand`, when a stone is provided: if `name` is already taken, use the full alias (`stone.id + '.' + name`) as the command name instead; otherwise keep original behavior (name as primary, alias as secondary)
- If no stone is provided, behavior is unchanged (commander will error on duplicates as before)
