---
# whet-i36f
title: 'Bug: async cache eviction is not awaited and can race file removal'
status: scrapped
type: bug
priority: high
created_at: 2026-02-14T08:29:35Z
updated_at: 2026-02-17T07:01:39Z
parent: whet-4ve1
---


In BaseCache.checkDurability, remove() is called without awaiting Promise completion (`src/whet/cache/BaseCache.hx:99`, `src/whet/cache/BaseCache.hx:105`). This allows overlapping unlink/rmdir operations and can leave transient locks; likely contributor to current Windows EBUSY test failures.

**Closed as not a bug.** Two mitigations make the described race inert:

1. `getUniqueDir` allocates a fresh versioned directory (`v1/`, `v2/`, …) for every stone generation, so concurrent `remove()` calls from `checkDurability` always operate on distinct directories and cannot interfere with each other's `unlink`/`rmdir` operations.
2. `FileCache.remove()` guards file deletion with an `isAlone` check (evaluated synchronously before any I/O), preventing deletion when another cache entry shares the same `baseDir` — the only scenario where overlap could occur (`AbsolutePath` strategy).

Fixing this would require changing `checkDurability` to return `Promise<Nothing>` and using `Promise.all` over the remove calls (sequential awaiting would unnecessarily serialize independent directory operations). The cost is not justified. The Windows EBUSY failures seen in CI were most likely caused by Dropbox locking files, not this code path.
