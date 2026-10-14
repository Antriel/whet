---
# whet-vz93
title: 'JsonDb: authored file is an input; explicit save with conflict check, reload hook'
status: completed
type: feature
priority: high
created_at: 2026-10-14T08:04:30Z
updated_at: 2026-10-14T11:01:36Z
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
- No hash from `generateHash`, deliberately: `generate` is a single `stringify`, and a hash would
  cost the same `stringify`. With a null hash, `BaseCache` generates once and uses that source's
  hash. (np9d's spec had one; it was dropped before commit, though the np9d summary still lists
  it.) `generateHash` is still overridden, only to run the freshness check below, and returns null.
- **Shared file tracking (`whet.TrackedFile`)**, used by both `JsonDb` and `ConfigStore` (the
  other JSON file whet both reads and writes). It records the disk state (exists, mtimeMs, size,
  content hash) of the last read/write, and provides:
  - `changed()`: a cheap stat compare, with a content-hash fallback when mtime differs but size
    doesn't (so a `git checkout` that only touches mtime is not a change). A missing file is
    recorded as "absent", so a file created later counts as changed.
  - `write(content, force)`: the conflict-checked writer. If the disk changed since the last
    read/write and `!force`, it rejects with an error carrying `code: 'WHET_FILE_CONFLICT'` and
    `path`. Otherwise it writes via temp file + rename (skipping the write when the bytes match
    what is on disk) and records the new state.
- **Freshness is pull-based, like `Files`/`HashCache` and `ConfigStore`**: no watcher, no
  snapshot-until-told. On access, if the file changed on disk:
  - and the in-memory state is clean, reload it;
  - and the in-memory state is dirty, keep the unsaved edits (warn once); `save()` will then
    report the conflict.
  For `JsonDb` the check runs from `generateHash` (every `getSource`/`getHash`). `StoneStore`
  runs it at its own entry points (`getResults`, `getUnfilteredHash`), before resolving routes,
  because requests for entry outputs never touch the db stone. `ConfigStore` already checked on
  every `ensureApplied`. Its file is a map of independent per-stone entries, so it merges per
  entry instead: clean entries take the disk version, unsaved (preview) entries are kept, and only
  an entry changed both here and on disk is a conflict. `flush` merges first, then rejects with
  `WHET_FILE_CONFLICT` + `stoneIds` if such an entry remains; `force` keeps the in-memory version of
  those entries while other stones' external edits survive.
- `JsonDb` API:
  - `load(path)` binds the path, reads the file (missing → `defaultData`, recorded as absent).
    Does not fire `onReload` (the caller is explicitly loading).
  - `isDirty()`: `data` serialises differently from the last load/save. No mark-dirty API,
    because callers mutate `data` directly.
  - `diskChanged()`: `TrackedFile.changed()` for the bound path.
  - `save(?force)` is the only writer; resolves `true` if bytes were written. With no bound path
    it rejects. `flush()` stays as an alias, so `StoneStore.flushDb` keeps working (its return type
    changes from `Source` to `Bool`; nothing consumes it).
  - `reload(?force)` re-reads the file, replaces `data` and fires `onReload` listeners. With
    unsaved edits and `!force` it rejects with `code: 'WHET_UNSAVED_CHANGES'`. Atomic: if parsing or
    a listener fails, `data` is restored and the disk state forgotten, so the next access retries
    (a broken file keeps failing requests until fixed, like a missing `Files` input).
  - `refresh()`: the lazy check above; resolves `true` if it reloaded.
  - `onReload(fn)` returns an unsubscribe function. StoneStore registers `syncEntries()` there,
    which also covers AudioDb once it becomes a StoneStore (scry-app-lcf4).
- Explicit `diskChanged()`/`reload()` stay public so a plugin-side watcher (scry-app-gvry) can push
  changes for live editing, but correctness doesn't depend on one.
- **Out of scope:** graceful file-system handling (rename retry on EPERM/EBUSY when another
  program holds the file, etc.). Worth doing whet-wide later, in whatever way is idiomatic for
  tools like this; tracked in whet-391c.

## Behaviour changes to note in the changelog

- `JsonDb`: unsaved mutations of `data` no longer reach disk when something happens to fetch the
  stone. They reach disk only on `save()`/`flush()`. Scry's audio-manager already treats edits as
  unsaved until flush, so this makes its "flushed" state true.
- `JsonDb`/`StoneStore`: external edits to the file are picked up on the next access (when there
  are no unsaved edits).
- `ConfigStore`: external edits merge per entry, both on access and on `flush()`. A reload no
  longer discards unsaved (preview) entries, and a preview no longer overwrites other stones'
  external edits on persist. `flush()` (and `Project.setStoneConfig(..., Persist)`) rejects with
  `WHET_FILE_CONFLICT` and `stoneIds` only when the same entry was changed here and on disk;
  `flush(true)` / `setStoneConfig(id, patch, Persist, true)` keep the in-memory version.

## Todos

- [x] `TrackedFile.hx`: disk-state record, `changed`, conflict-checked atomic `write`, `forget`
- [x] `JsonDb.hx`: drop `setAbsolutePath` from `load`; `isDirty`, `diskChanged`, `save(force)`,
      `reload(force)` + `onReload`, `refresh` from `generateHash`; `flush` → `save`
- [x] `StoneStore`: register `onReload` → `syncEntries()`; refresh at entry points; `flushDb(force)`
- [x] `ConfigStore`: move onto `TrackedFile`; per-entry merge on reload/flush; `flush(?force)`;
      `Project.setStoneConfig(..., force)`
- [x] Tests (`test/json-db.test.mjs`, `test/stone-store.test.mjs`, `test/config-store.test.mjs`):
      getSource never touches the file; external edit + save → conflict; `force` overwrites;
      unchanged save keeps mtime; external edit picked up lazily when clean, kept out when dirty;
      reload fires listeners / refuses when dirty; absent file created externally → conflict;
      StoneStore picks up an external edit on next request; ConfigStore flush conflict
- [x] Update `docs/stone-store.md` / `src/whet/stones/CLAUDE.md` where they describe load/flush

Follow-up in scry-app (not here): AudioDb moves onto this class by becoming a StoneStore
(scry-app-lcf4), then a plugin-side watcher (scry-app-gvry). SoundBankStone drops its JsonDb
entirely (scry-app-9495).

Scry follow-ups: scry-app-lcf4 (AudioDb becomes a StoneStore, so it inherits this), scry-app-gvry (plugin watcher + editor simplification).

## Implementation notes

- `JsonDb.save()` without unsaved changes is a no-op (doesn't even compare bytes), so a
  hand-formatted file isn't rewritten into whet's 2-space format just because someone saved.
- `TrackedFile` has no rename retry/fallback for EPERM/EBUSY (Windows, another program holding the
  file). Deferred to a whet-wide graceful-file-system pass.
- After review by the scry-side agent:
  - `StoneStore.refresh()` is public; code reading `entryMap`/`dataMap`/`getExpansion` outside
    the router must call it first (documented in `docs/stone-store.md`). Scry's AudioManifest and
    SoundBankStone read entries directly, so they need it once AudioDb is a StoneStore (scry-app-lcf4).
  - `TrackedFile.write` doesn't report a conflict when the disk already holds exactly the bytes
    being written; it adopts that state instead.
  - `defaultData` is `structuredClone`d on load, so edits never leak into the config.
