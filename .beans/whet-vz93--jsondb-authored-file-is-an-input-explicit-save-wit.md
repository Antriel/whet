---
# whet-vz93
title: 'JsonDb: authored file is an input; explicit save with conflict check, reload hook'
status: todo
type: feature
priority: high
created_at: 2026-10-14T08:04:30Z
updated_at: 2026-10-14T09:21:13Z
---

Stop `JsonDb` from writing its authored file as a side effect of `getSource()`. The file is an
*input*; it is written only by an explicit save that refuses to overwrite a file someone else
changed.

## Why

`JsonDb.load(path)` calls `setAbsolutePath(path, false)`, so the stone's cache slot **is** the
authored file. Any `getSource()` hashes the in-memory `data`, finds the file on disk no longer
matches (another process, an agent, `git checkout`, a hand edit), counts it a cache miss and
writes `data` back over the file. Nothing has to be stale *code* for this: a current `whet serve`
reverts any external edit the next time something depends on the stone.

Incidents (both via AudioDb's private copy of the same class, which moves onto this one in
scry-app-lcf4; SoundBankStone's copy is dropped outright in scry-app-9495):
- gooye-2 2026-07-28: `assets/audio.json` lost every `group`/`bus`/`loadPolicy` (scry-app-4z5u).
- gooye-2 2026-10-14: a zombie `whet serve` from 10-10 rewrote `assets/audio.json` to its
  pre-`1ac9c89` contents on one HTTP request (`gooye-2/STALE_WHET_PROCESS_HANDOFF.md`).

Multiple whet processes per project are normal (a long-lived server plus ad-hoc CLI builds, or
several servers), so the fix has to be in the stone, not in "don't do that".

**Where it lands:** branch `v0.7-stone-store` (npm `beta`, 0.7.1 at filing; `latest` is 0.6.4).
Core `JsonDb` only exists there and has no consumers yet (scry still uses its own two copies),
so the behaviour change below breaks nobody.

## Design

- **Output is built from `data`, never cached to the authored path.** `load` no longer calls
  `setAbsolutePath`; the stone keeps its default/in-memory strategy. The output id stays the
  stone id, so routes serving `audio.json` etc. are unaffected.
- No `generateHash`, deliberately: `generate` is a single `stringify`, and a hash would cost the
  same `stringify`. With a null hash, `BaseCache` generates once and uses that source's hash.
  (np9d's spec had one; it was dropped before commit, though the np9d summary still lists it.)
- `load(path)` reads the file and records its disk state (mtimeMs, size, content hash) plus the
  hash of what was loaded.
- `isDirty()`: `data` serialises differently from the last load/save. No mark-dirty API, because
  callers mutate `data` directly.
- `diskChanged()`: a cheap stat compare against the recorded disk state, with a content-hash
  fallback when mtime differs.
- `save(?force)` is the only writer. With no bound path it throws. If the disk changed since
  load/save and `!force`, it rejects with a typed conflict error naming the path. Otherwise it
  writes via temp file and rename (skipping the write when bytes are unchanged) and updates the
  recorded state. `flush()` stays as an alias, so `StoneStore.flushDb` keeps working.
- `reload()` re-reads the file, replaces `data`, updates the state and fires `onReload`
  listeners. StoneStore registers `syncEntries()` there, which also covers AudioDb once
  it becomes a StoneStore (scry-app-lcf4).
- **No watcher in whet** (kept simple on purpose). Whoever wants live reload watches the file
  and calls `diskChanged()`/`reload()`; for Scry that is the plugin layer.

## Behaviour change to note in the changelog

Unsaved mutations of `data` no longer reach disk when something happens to fetch the stone.
They reach disk only on `save()`/`flush()`. Scry's audio-manager already treats edits as
unsaved until flush, so this makes its "flushed" state true.

## Todos

- [ ] `JsonDb.hx`: drop `setAbsolutePath` from `load`; add disk-state record,
      `isDirty`, `diskChanged`, `save(force)` with conflict error + atomic write, `reload` +
      `onReload`; `flush` → `save`
- [ ] `StoneStore`: register an `onReload` → `syncEntries()`; `flushDb` surfaces the conflict
- [ ] Tests (`test/json-db.test.mjs`): getSource never touches the file; external edit + save
      → conflict; `force` overwrites; unchanged save keeps mtime; reload fires listeners and
      picks up the edit; isDirty after mutation and after save
- [ ] Publish as the next 0.7 beta + changelog note

Follow-up in scry-app (not here): AudioDb moves onto this class by becoming a StoneStore
(scry-app-lcf4), then a plugin-side watcher (scry-app-gvry). SoundBankStone drops its JsonDb
entirely (scry-app-9495).

Scry follow-ups: scry-app-lcf4 (AudioDb becomes a StoneStore, so it inherits this), scry-app-gvry (plugin watcher + editor simplification).
