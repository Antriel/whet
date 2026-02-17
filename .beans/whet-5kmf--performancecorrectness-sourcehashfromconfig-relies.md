---
# whet-5kmf
title: 'Performance/Correctness: SourceHash.fromConfig relies on unstable object iteration order'
status: todo
type: task
priority: normal
created_at: 2026-02-14T08:29:36Z
updated_at: 2026-02-14T08:30:06Z
parent: whet-4ve1
---

SourceHash.fromConfig iterates dynamic object keys without sorting (`src/whet/SourceHash.hx:72`). Equivalent configs with different insertion order may hash differently and trigger unnecessary invalidations/rebuilds. Normalize keys before hashing.
