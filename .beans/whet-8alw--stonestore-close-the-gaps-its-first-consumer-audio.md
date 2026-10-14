---
# whet-8alw
title: 'StoneStore: close the gaps its first consumer (AudioDb) hit — merge-by-id overrides, nameTemplate keys, rebuild from update'
status: in-progress
type: feature
priority: normal
created_at: 2026-10-14T12:41:21Z
updated_at: 2026-10-14T12:52:09Z
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

- [x] Provenance: confirm or correct the timeline above; record the key-prefix reason if one exists
- [x] Merge-by-id overrides (own merge fn; ids required; base owns membership/order; `type` overridable; unknown id warns)
- [x] `nameTemplate` expansion is the key; default stays `<id>/<stem>`
- [x] Builder `update` may return `false` → recreate
- [x] Decide + implement the unsaved-entry expansion API (or record why not)
- [x] Tests (`test/stone-store.test.mjs`); `docs/stone-store.md`; publish (0.7.3 beta)
- [x] Note in scry-app-dxgt what landed and under which names

## Provenance findings (2026-10-14)

Timeline **confirmed**:
- scry `913621b` (2026-07-22, "audio per group overrides"): AudioDb's overrides are plain nested
  objects merged by a local `deepMerge` that replaces arrays; assets keyed by bare name
  (`this.sync(flatEntries, e => e.name)`).
- whet `516e85f` (2026-07-23, whet-qwye) ported that, reusing `ConfigStore.deepMerge`. Array-replace
  was faithful to AudioDb as it was that day.
- scry `08d9c79` (2026-07-28, "audio pipeline", scry-app-ezol) introduced `pipeline` and
  `mergePipeline`. So gap 1 is drift after the snapshot.

Key prefix: **no recorded reason.** It's in qwye's spec (`key = entry.id + '/' + names[i]`), but not
in doc 03, the epic or the commit. It also contradicts qwye's own premise ("semantics intentionally
identical to AudioDb"). The likely unstated reason is that a StoneStore key is a project-wide stone id
for single-stone types (`register` builds `{...config, id: key}`), so bare stems would collide.
AudioDb didn't hit that because its builder namespaces its own stones (`audio/${key}:wav`). That's
the reason the template-less default keeps, so it doesn't argue against gap 2.

## Decision: unsaved-entry expansion API

The server expands, as the scry side leaned. `StoneStore.expandRaw(rawEntry) -> Promise<FlatEntryData[]>`
and `StoneStore.previewRaw(rawEntry, ?keys) -> Promise<FlatEntryData[]>` (all expanded entries, for
showing effective configs). Both validate structure and schema first, so a broken edit rejects before
any stone changes. A group reuses the last sync's scan of its id while `each.dir/pattern/nameTemplate`
are unchanged (perf invariant). If `each` itself changed, or the group was never synced, it scans,
without caching the result or touching `getExpansion`. Sync and `expandRaw` share one pure
`expandGroup`, so there is one implementation of keys, merge and tokens.

## Summary of Changes

- `StoneStore.mergeOverride`: StoneStore's own override merge. `ConfigStore.deepMerge` is
  unchanged. A base array whose items all carry a string `id` merges by id. Base membership and order
  win, any field (incl. `type`) is overridable, it recurses into nested id'd arrays, and unknown or
  missing ids warn (with group/file/path) and are ignored. Other arrays replace.
  - Judgment call: a base with **no** such field takes the override's array as-is, the same as any
    key the base lacks. "Base owns membership" applies where the base has a list.
  - Per-item merge is deep, where audio's `mergePipeline` was a shallow `{...b, ...params}`.
- `each` key: the `nameTemplate` expansion verbatim when given, else `groupId/name`.
- `BuiltEntry.update` may return `false`; `updateEntry` then does the id-stable remove + `createEntry`.
- `expandRaw` / `previewRaw` (above). `expandEntries` was refactored into `singleEntry`, `scanGroup`,
  `expandGroup` and `assertUniqueKeys`.
- Docs: `docs/stone-store.md` (keys, override rules, the zero-match schema note, editor preview API,
  update hooks); `src/whet/stones/CLAUDE.md` invariants; whet skill authoring reference.
- 7 new tests in `test/stone-store.test.mjs`; full suite 286/286.
