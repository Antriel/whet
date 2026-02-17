---
# whet-c5z1
title: 'Bug: FileCache flush uses delayed background write without lifecycle sync'
status: completed
type: bug
priority: high
created_at: 2026-02-14T08:29:35Z
updated_at: 2026-02-17T07:49:54Z
parent: whet-4ve1
---


FileCache.flush batches writes with setTimeout and does not expose completion/shutdown hook (`src/whet/cache/FileCache.hx:164`, `src/whet/cache/FileCache.hx:167`). Background writes can race project/test cleanup and hold directory handles, causing flaky teardown on Windows.

## Fix

Split `flush()` into two parts and added `FileCache.close()` / `CacheManager.close()`:

- `flush()` is unchanged in batching behaviour (100ms debounce preserved). It now also creates a `Promise`/resolve pair on first call in a batch and returns it, making the pending write observable.
- `doFlush()` is the timer callback. It clears the pending state, serialises the DB, writes it, then calls `resolve(null)` on both success and error paths.
- `close()` cancels the timer if armed and calls `doFlush()` immediately, returning the same promise so the caller can await the disk write before cleanup.
- `CacheManager.close()` delegates to `fileCache.close()` (`@:keep` required due to `--dce full`).

## Decision notes

- The 100ms debounce was intentionally kept. Generating many files triggers many `set()` calls in quick succession; without the debounce, an SSD-fast run could flush dozens of times instead of once.
- `close()` is only needed in tests (process stays alive, directories are deleted before the timer fires). In CLI use, the pending `setTimeout` and the subsequent async fs write both keep the Node.js event loop alive, so the process naturally waits for the write to complete before exiting — no call to `close()` is needed in `Whet.hx`.
- The `sleep(180)` workaround in `test/cache.test.mjs` was replaced with `await env.project.cache.close()`, which is both semantically precise and faster.
