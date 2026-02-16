---
# whet-i36f
title: 'Bug: async cache eviction is not awaited and can race file removal'
status: todo
type: bug
priority: high
created_at: 2026-02-14T08:29:35Z
updated_at: 2026-02-14T08:30:05Z
parent: whet-4ve1
---

In BaseCache.checkDurability, remove() is called without awaiting Promise completion (`src/whet/cache/BaseCache.hx:99`, `src/whet/cache/BaseCache.hx:105`). This allows overlapping unlink/rmdir operations and can leave transient locks; likely contributor to current Windows EBUSY test failures.
