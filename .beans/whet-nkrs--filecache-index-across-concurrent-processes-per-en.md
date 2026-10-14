---
# whet-nkrs
title: 'FileCache index across concurrent processes: per-entry records vs SQLite (design)'
status: draft
type: task
priority: normal
created_at: 2026-10-14T08:04:30Z
updated_at: 2026-10-14T08:05:16Z
---

Design task: make the FileCache index work for several whet processes on one project at once.
Two candidate designs, per-entry records and SQLite, plus a minimal baseline. **Measure, then
decide**; nothing is settled.

## The problem

`FileCache` reads `.whet/cache.json` once at process start (`FileCache.new`), keeps its own
in-memory index, and `doFlush` writes that whole index back (last writer wins). Multiple
processes per project are normal: a long-lived `whet serve` next to ad-hoc CLI builds, or
several servers.

Consequences:
1. **A running server never sees what another process built.** Typical case: an agent
   implements something and runs builds/tests, then Peter tests on his already-running server.
   The server computes the same hash, misses in its own index and recompiles the game.
2. **Entries are lost.** Whichever process flushes last drops the other processes' entries, so
   later runs rebuild for nothing.
3. **Version-folder allocation race (unverified).** `getUniqueDir` picks `vN/` from the
   process's own index, so two processes can pick the same folder. Hash validation should catch
   the clash (it regenerates), but it may thrash.
4. **Flush cost.** It pretty-prints the whole index on every debounced change
   (`PERFORMANCE_REVIEW.md` §4).

Out of scope (handled elsewhere): stale processes overwriting authored files (the JsonDb
bean); stale code in long-lived servers (scry-app, ScryStone staleness bean); two live processes
with different flags fighting over one fixed-path output (`.whet/config.json`, `build.hxml`).
That last one is a project rule: put the varying option in the path.

Caveat for any shared design: sharing also spreads a *poisoned* entry (a stale process writing
wrong output under the correct hash; FS-mini 2026-09-28, `map.json`) to every process
immediately.

## Option A: one record per entry, no central index

An entry is an immutable fact, "stone X with hash H produced these files", valid for any
process that computes H. Store each with its files (e.g. `.whet/<stoneId>/<hash>/` plus a small
record file). On an in-memory miss, look for the record on disk before generating. Folders keyed
by content hash remove the `vN` race; same-hash writers produce the same bytes. Same shape as
Bazel, Turborepo and Nx local caches.

Open questions:
- **Performance:** a record read on the first lookup per stone and hash; startup cost vs one
  `cache.json` read; small-file cost on Windows; stones with thousands of output files (FS-mini
  AutoCompose ~2.3k); `tryListIds` fast path from record metadata.
- **Eviction:** `LimitCountByLastUse` needs last-use time across processes (touch the record?
  rewrite it?). `LimitCountByAge` from ctime in the record. Deleting an entry another live
  process is still serving (today that would be a miss and a regenerate). Two processes with
  different flags evicting each other's count-1 entries. `MaxAge`/`Custom`/`All`/`Any` semantics
  unchanged?
- **Partial entries:** concurrent `mergePartial` on the same record.
- **AbsolutePath entries:** a record pointing at the fixed path.
- **Migration** from `cache.json`; debugging by hand (`rm -r .whet/<stone>` instead of editing
  `cache.json`, which FS-mini's cold-profiling workflow does today).

## Option B: SQLite (`node:sqlite`)

`.whet/cache.db` in WAL mode: one row per entry (plus a files table). Transactions cover
eviction and folder allocation; on a miss, query the db (or watch `PRAGMA data_version`) so
other processes' entries are visible. Writer columns (pid, option fingerprint) would come
almost free if writer tracking is ever wanted. Precedent: scry's `LogCollectorPlugin` uses
`node:sqlite` with no dependency.

Open questions: the Node version floor for whet users and `node:sqlite`'s stability status;
the sync API blocking the event loop under a busy dev server; `busy_timeout` with several
writers; not hand-editable, so cold-profiling surgery needs a `whet cache clear <stone>`-style
verb.

## Option C (baseline): keep `cache.json`, merge instead of overwrite

Re-read and merge per stone on flush under a lock file, with an atomic write. On a miss,
re-read the index if its mtime changed. Smallest change. It fixes 1 and 2, but not 3 or 4.

## To decide

- [ ] Benchmark harness: cold/warm startup, lookup latency, flush cost, on gooye-2 and FS-mini
      (largest index)
- [ ] Prototype A and B behind `FileCache` (`BaseCache` stays); measure
- [ ] Walk every `CacheDurability` case through the chosen design
- [ ] Decide; then split implementation beans
- Related: `MEMORY_CACHE_PLAN.md` (memory layer), `PERFORMANCE_REVIEW.md` §4–6

Related: whet-vz93 (JsonDb), scry-app-pwhw (ScryStone staleness/lifecycle).
