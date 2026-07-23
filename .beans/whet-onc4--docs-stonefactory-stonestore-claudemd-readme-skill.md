---
# whet-onc4
title: 'Docs: StoneFactory + StoneStore (CLAUDE.md, README, skill pointer)'
status: todo
type: task
priority: low
created_at: 2026-07-23T07:08:17Z
updated_at: 2026-07-23T07:08:17Z
parent: whet-1vzf
blocked_by:
    - whet-31lx
    - whet-qwye
---

Documentation pass once StoneStore + expansion land (also addresses doc 01 §1's note that StoneFactory is entirely undocumented).

- [ ] CLAUDE.md: add StoneFactory, StoneStore, JsonDb, StoneRegistry to the built-in stones / architecture sections; document the store entry format (id/type/config/mount/disabled/each/overrides), $stone/$router refs, preview semantics (previewEntry/revertEntry, sync reasserts canonical), and the "script references the store, never inner stones" rule
- [ ] README: fill the data-driven section from the same material (doc 01 §1 lists other README stubs — only do the StoneStore-related part here)
- [ ] Note the StoneFactory-extends-Router hash semantics paragraph (doc 01 §8)
- [ ] Update `docs/ecosystem-review-2026-07/03-data-driven-stones.md` with a short status header pointing at epic whet-1vzf and the frozen deltas
- [ ] Remind Peter to update `~/.claude/skills/whet-pipeline` (user-owned skill; agent may draft the diff but the skill lives outside this repo)
