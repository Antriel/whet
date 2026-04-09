---
# whet-hqwq
title: Export project schema as JSON (commands, options, metadata)
status: completed
type: feature
priority: normal
created_at: 2026-04-02T08:38:31Z
updated_at: 2026-04-02T09:00:55Z
---

Add a command to Whet that exports the project's command and option schema as structured JSON.

## Goal

External tools (like Scry) need to programmatically discover what commands and options a Whet project exposes, so they can build dynamic UI (dropdowns, toggles, buttons) for configuring and controlling the project.

## Why

Currently, the only way to discover a project's available options and commands is to parse the human-readable `--help` output. This is fragile and loses structured metadata (choices, defaults, types, descriptions). Commander.js already holds all this information internally on `Command.options` and `Command.commands` — we just need to serialize it.

## What to export

- **Options**: name, flags, description, choices, defaults, whether boolean/required
- **Commands**: name, description, and their own options

The output should be machine-readable JSON suitable for building UIs programmatically.

## Constraints

- Should be part of Whet itself (not something each project manually defines)
- Must work without actually starting the server — just load the project definition far enough to collect registered options/commands, then output and exit


## Summary of Changes

Added a `schema` command to Whet that exports the project's command and option schema as structured JSON to stdout.

### Files changed
- `src/whet/Whet.hx` — Added `schema` command registration in `initProjects()`, plus `outputSchema`, `serializeOption`, and `serializeCommand` helper functions
- `src/whet/Log.hx` — Added `"silent"` as a recognized log level string (maps to level 100)

### Usage
```bash
npx whet --log-level silent schema
```

Outputs clean JSON with `projects` (name, id, description, options) and `commands` (name, description, aliases, options). Each option includes: name, attributeName, flags, description, choices, defaultValue, required, mandatory, boolean, hidden.
