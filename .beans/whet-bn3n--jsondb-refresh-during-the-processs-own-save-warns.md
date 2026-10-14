---
# whet-bn3n
title: 'JsonDb: refresh() during the process''s own save() warns of a false external change'
status: completed
type: bug
priority: low
created_at: 2026-10-14T13:55:21Z
updated_at: 2026-10-14T14:32:32Z
---

`JsonDb.refresh()` can run while the process's own `save()` is mid-write, and then it logs
"DB file changed on disk, but there are unsaved changes; keeping them." for the write it is
itself doing. Nothing is lost (data is kept, and state settles when the write resolves), but the
warning is false and it lands in the Scry app's warnings badge.

## Seen

scry-app-dxgt's Audio Manager harness drive (add a group, edit it, Save DB) hit it in 2 of 3
runs. The fixture lives under Dropbox.

## Why the window is not tiny

- `TrackedFile.write`: writeFile(tmp), then rename, then `stat()`, and only then is `state`
  recorded. `JsonDb.save` sets `savedJson` only after `write` resolves.
- During that span, `changed()` sees the new file's size against the old recorded size. That
  returns `true` with no hashing. `isDirty()` is still true because `savedJson` is old, so
  `refresh()` warns.
- Requests are typically in flight right then. Scry's Save does `audio:set` (a sync that bumps
  the editor's cache generation, so it refetches the waveform and metadata), then `audio:flush`.
  Every routed request calls `refresh()`. Each step of the write is an async fs call, slower on a
  Dropbox-watched folder.

Likely the same during `StoneStore.flushDb` in any editor flow, not just audio.

## Fix sketch

Make `refresh()` aware of an in-flight save. `save()` keeps a `saving` promise, and `refresh()`
waits for it (then re-checks) instead of comparing against a half-recorded state. That beats
pre-recording `state` in `TrackedFile.write`: before the rename the disk still holds the old
bytes, so a hash check would still report a change.

## Todo

- [x] Repro in a unit test: start `save()`, call `refresh()` before it resolves, assert no warning or reload
- [x] ~~`JsonDb`: serialize `refresh()` behind an in-flight `save()`~~ done one level down, in `TrackedFile` (see summary)
- [x] Check `TrackedFile` callers other than JsonDb for the same pattern

## Summary of Changes

Fixed in `TrackedFile` rather than `JsonDb`. While the process's own write is in flight, `changed()` has no meaningful answer, and every caller is affected:

- **Overlapping saves also failed outright.** A second `save()`/`flush()` during the first write saw the half-recorded state and rejected with a false `WHET_FILE_CONFLICT` (`TrackedFile.adoptIfSame` for JsonDb; `ConfigStore.merge` for ConfigStore).
- `TrackedFile.write` now runs writes one at a time, in call order. `read()`/`changed()` wait for an in-flight write.
- Write counter: a `read()`/`changed()` already running when a write is requested runs again after it, since its `stat` may land after the rename and its recorded state may clobber the write's.
- `changed()` compares against one snapshot of `state` rather than re-reading the field across async steps.
- `ConfigStore.persist` recorded `persistedData = deepClone(data)` *after* the write, so an entry edited mid-write was wrongly marked saved. It now records the snapshot it actually wrote.
- `JsonDb` needed no change.

Tests: `test/tracked-file.test.mjs` (new), plus race cases in `json-db` and `config-store`. They use `test/helpers/fs-hold.mjs` (`holdRenames`, `deferNext`), which pins a write in the rename to state-recorded window deterministically. Five new race tests fail on the old code and pass now; full suite 292/292.

### Also: racy mtimes

A same-size external edit that lands in the same mtime tick as whet's last read/write (about 1 in 5 for two quick writes on this NTFS/Dropbox disk) was missed: `changed()` trusted a matching size + mtime without hashing. This likely explains a one-off failure of `config-store` "flush merges per entry", which rewrites the file at the same size. It couldn't be reproduced naturally in 95 runs; forcing the exact mtime reproduces it (`1 !== 5`).

Fix, after git's "racy git": `DiskState.seenAt` records when the content was last confirmed to hash to `hash`. A matching stat is trusted only if `seenAt - mtimeMs > RACY_MS` (2 s, covering 1-2 s mtime granularity on some file systems). Otherwise `changed()` hashes, and a matching hash refreshes `seenAt`. So only files touched in the last moment pay for a hash. Tests in `test/tracked-file.test.mjs`: forced collision is detected; an old state is trusted on stat alone; a racy state hashes until a check confirms it after the window.
