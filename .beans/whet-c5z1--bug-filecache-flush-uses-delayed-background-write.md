---
# whet-c5z1
title: 'Bug: FileCache flush uses delayed background write without lifecycle sync'
status: todo
type: bug
priority: high
created_at: 2026-02-14T08:29:35Z
updated_at: 2026-02-14T08:30:05Z
parent: whet-4ve1
---

FileCache.flush batches writes with setTimeout and does not expose completion/shutdown hook (`src/whet/cache/FileCache.hx:164`, `src/whet/cache/FileCache.hx:167`). Background writes can race project/test cleanup and hold directory handles, causing flaky teardown on Windows.
