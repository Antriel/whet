---
# whet-onc4
title: 'Docs: StoneFactory + StoneStore (CLAUDE.md, README, skill pointer)'
status: completed
type: task
priority: low
created_at: 2026-07-23T07:08:17Z
updated_at: 2026-07-23T15:27:05Z
parent: whet-1vzf
blocked_by:
    - whet-31lx
    - whet-qwye
---

Documentation pass once StoneStore + expansion land (also addresses doc 01 §1's note that StoneFactory is entirely undocumented).

- [x] CLAUDE.md: add StoneFactory, StoneStore, JsonDb, StoneRegistry to the built-in stones / architecture sections; document the store entry format (id/type/config/mount/disabled/each/overrides), $stone/$router refs, preview semantics (previewEntry/revertEntry, sync reasserts canonical), and the "script references the store, never inner stones" rule
- [x] README: fill the data-driven section from the same material (doc 01 §1 lists other README stubs — only do the StoneStore-related part here)
- [x] Note the StoneFactory-extends-Router hash semantics paragraph (doc 01 §8)
- [x] Update `docs/ecosystem-review-2026-07/03-data-driven-stones.md` with a short status header pointing at epic whet-1vzf and the frozen deltas
- [x] Remind Peter to update `~/.claude/skills/whet-pipeline` (user-owned skill; agent may draft the diff but the skill lives outside this repo)

## Summary of Changes

- **CLAUDE.md**: added StoneFactory/StoneStore/StoneRegistry/ConfigReviver/SchemaValidator/JsonDb to the source-files list, and a new **Data-Driven Stones** section documenting the three classes, the store entry format (id/type/config/mount/disabled/each/overrides), `$stone`/`$router` reviver semantics, topo-sort + all-or-nothing validation + reference-consistency cascade, `each` expansion, preview/revert semantics, the script rule (reference the store, never inner stones), the StoneFactory-extends-Router hash paragraph (doc 01 §8), and the `whet stone-schema` CLI.
- **README.md**: added a **Data-Driven Stones** section (StoneFactory/StoneRegistry/StoneStore overview, entry shape, reviver sentinels, script-mounts-only rule) pointing at CLAUDE.md + doc 03.
- **docs/ecosystem-review-2026-07/03-data-driven-stones.md**: added an implemented-status header pointing at epic whet-1vzf, listing the six frozen deltas vs the original sketch and the implementation/doc file locations.
- **~/.claude/skills/whet-pipeline/SKILL.md** (user-owned, outside repo — applied with Peter's OK): rewrote the data-driven section to lead with StoneStore (no-code JSON graph, registry, `$stone`/`$router`, `each`, stone-schema, preview) then StoneFactory (custom code).
