---
# whet-8alw
title: 'StoneStore: close the gaps its first consumer (AudioDb) hit — merge-by-id overrides, nameTemplate keys, rebuild from update'
status: todo
type: feature
created_at: 2026-10-14T12:41:21Z
updated_at: 2026-10-14T12:41:21Z
parent: whet-1vzf
---

StoneStore was designed as the generic form of what scry's `AudioDb` had grown into (epic whet-1vzf,
doc `docs/ecosystem-review-2026-07/03-data-driven-stones.md`). Its first real consumer is that same
AudioDb (scry-app-lcf4, 2026-10-14). Moving AudioDb onto it turned up three gaps, and **AudioDb
should not have to override StoneStore to get around them.** Fix them here, so AudioDb can become a
stock StoneStore with `audio.json` migrated to the generic entry format (scry-side follow-up:
scry-app-dxgt, which waits on this bean).

As things stand (scry-app-lcf4, landed), AudioDb `extends StoneStore` and overrides `validateData` +
`expandEntries` to keep its own file format. Everything else (JsonDb, lazy refresh, preview/revert,
rollback) is already StoneStore's. The workaround code to read is `scry/whetstones/assets/AudioDb.mjs`
in scry-app (or a game's vendored `scry/`).

## First: provenance

Peter wants the design's origin checked before changing it. What the scry side found, to confirm or
correct:

- Planning doc: `docs/ecosystem-review-2026-07/03-data-driven-stones.md`. The epic whet-1vzf lists
  "design deltas vs doc 03". Delta 2 (the `each` clause) was added because doc 03 missed group
  expansion entirely.
- StoneStore and `each` landed **2026-07-23** (whet-qwye, `516e85f`), modelled on AudioDb *as it
  was that day*: a fixed chain whose per-file overrides were plain nested objects (qwye's own example:
  `"overrides": { "punch": { "loudness": { "target": -12 } } }`). A deep merge that replaces arrays
  was correct for that data.
- AudioDb's config became an ordered block array (`pipeline`) on **2026-07-28** (scry-app-ezol),
  which is when the merge-by-id rule appeared (`audioBlocks.mjs` `mergePipeline`, "ezol sharp edge 1").
  So gap 1 is **drift after the snapshot**, not a decision StoneStore made.
- The `groupId/name` key (qwye: `key = entry.id + '/' + names[i]`) is qwye's own choice. AudioDb has
  always keyed by bare name, and doc 03 doesn't mention it. Look for a recorded reason; if there is
  one, weigh it against gap 2 below.

## Gap 1: overrides replace arrays (merge by id)

`expandEntries` merges `overrides` with `ConfigStore.deepMerge`: objects recurse, arrays are replaced
wholesale. For a group whose config holds a list of items (audio: preprocess blocks), a file that
tunes one item's param loses the group's whole list.

**Decided:** in an array whose items are all objects carrying a string `id`, merge **by id**:
- An override item deep-merges into the base item with the same id.
- The base owns membership and order. An override tunes items; it cannot add, drop or reorder them.
  An item-level flag (audio's `enabled: false`) is how a file opts out of one.
- An override item whose id matches no base item is warned about and ignored (same spirit as the
  existing override-key typo guard).
- Any field may be overridden, **including `type`** (Peter, 2026-10-14). The builder copes, since
  every expanded entry gets its own stones. Whether an editor offers it is the editor's business
  (scry's Audio Manager won't).
- Arrays without ids still replace.

Give StoneStore its own merge function. **Don't change `ConfigStore.deepMerge`**: ConfigStore patches
are a separate contract.

Ids must exist in the authored file when the merge runs; StoneStore must not generate them. (Audio
generates missing block ids from their type, but only inside its builder, after expansion. The scry
migration writes ids into `audio.json`, and the audio schema will require them.)

## Gap 2: `each` keys are `groupId/name`

The key is an entry's identity: stone ids for single-stone types, `$stone` refs, preview addressing.
For audio it is also the public asset name, which shows up in:
- route paths, so it is served as `hurt/1.ogg`
- the runtime manifest
- sound-event references
- names in game code

Prefixing the group id couples organisation to identity. Moving a file between groups, or renaming or
splitting a group, renames every asset in it and breaks every reference. The prefix is also redundant
whenever the template already namespaces: gooye-2's templates are `hurt_$1`, `dungeon_land_$1`,
`sfx_collect_$1`, which would give `hurt/hurt_1`.

**Decided:** when `each.nameTemplate` is given, its expansion **is** the key, verbatim. Without one,
the default stays `<id>/<stem>`, so a template-less group still can't collide by accident (bare stems
as project-wide stone ids would). The existing all-or-nothing collision check is what keeps a flat
namespace safe. `overrides` stay keyed by the derived name, which is now the key whenever a template
is given.

## Gap 3: a builder's `update` hook can't ask for a rebuild

A multi-stone builder can update params in place, but not a change that alters which stones exist
(audio: adding or removing a block renames every downstream stone). The hook has no way to say "this
one I can't do in place". AudioDb's hook currently deregisters its stones and `Object.assign`s a
freshly built entry into `existing`. That works because StoneStore re-reads `routes` after an update,
but it's a workaround.

**Proposed:** `update` may return `false`, meaning "recreate me". StoneStore then does the same
id-stable remove + `createEntry` it already does for types without a hook.

## Open: expanding an unsaved entry (for editors)

Scry's Audio Manager previews **unsaved** group edits: it merges the selected file's override over
the edited group config and sends the result to `previewEntry`. To do that it duplicates the merge in
TypeScript (`resolvePreviewTarget`, `effectivePipeline`, its own `withBlockIds` + `deepMerge`). Once
the merge rules live in whet, that copy would be mirroring another repo's code.

Peter's criterion: whichever is more flexible and elegant. The scry side's lean: **the server
expands**. That's one implementation of merge + token substitution, it works for any store and any
future merge rule, and the editor stops knowing the rules. A sketch:
`expandRaw(rawEntry) -> FlatEntryData[]`, plus `previewRaw(rawEntry, ?keys)` that expands against the
**cached** scan (`groupMatches`, no rescan, which keeps the preview perf invariant) and previews the
result. The editor already makes one request per preview edit, so this adds no round trips. It needs
the expanded configs back too, for display (the effective per-file pipeline). Decide the API here.

## Smaller, noticed along the way

- A group's base `config` is only schema-checked through its expansions, so a group matching zero
  files is never validated at all. Possibly fine (its config may need `$file` to be valid); worth
  one line in the docs either way.

## Todos

- [ ] Provenance: confirm or correct the timeline above; record the key-prefix reason if one exists
- [ ] Merge-by-id overrides (own merge fn; ids required; base owns membership/order; `type` overridable; unknown id warns)
- [ ] `nameTemplate` expansion is the key; default stays `<id>/<stem>`
- [ ] Builder `update` may return `false` → recreate
- [ ] Decide + implement the unsaved-entry expansion API (or record why not)
- [ ] Tests (`test/stone-store.test.mjs`); `docs/stone-store.md`; publish (0.7.3 beta)
- [ ] Note in scry-app-dxgt what landed and under which names
