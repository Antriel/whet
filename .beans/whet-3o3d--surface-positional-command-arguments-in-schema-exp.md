---
# whet-3o3d
title: Surface positional command arguments in schema export
status: todo
type: feature
created_at: 2026-06-10T06:08:01Z
updated_at: 2026-06-10T06:08:01Z
---

The `whet schema` export (outputSchema/serializeCommand in src/whet/Whet.hx) only serializes a command's `cmd.options` (commander Options). Positional arguments declared via `.argument('<name>')` live in a separate commander array (`cmd.registeredArguments`) and are never included in the exported schema.

Consequence: downstream consumers (e.g. the Scry editor's WelcomeScreen) cannot build input UI for commands whose inputs are positional — such as the ScryStone verbs `refresh <stoneId>`, `stone-outputs <stoneId>`, `stone-config <stoneId>`, `find-outputs <ext...>`.

## Scope
- [ ] Add an `arguments` array to `serializeCommand` in `src/whet/Whet.hx`, iterating `cmd.registeredArguments`
- [ ] Serialize per-argument: name, description, required, variadic, argChoices (choices), defaultValue
- [ ] Keep field naming consistent with `serializeOption`
- [ ] Verify `whet schema` JSON now includes arguments for `refresh` et al.

## Notes
Editor-side consumption is tracked in the scry-app repo (WelcomeScreen command argument UI), which is blocked by this.
