---
# whet-arlg
title: 'Performance: Router.get allocates heavily via filter cloning and full list scans'
status: todo
type: task
priority: high
created_at: 2026-02-14T08:29:36Z
updated_at: 2026-02-14T08:30:05Z
parent: whet-4ve1
---

Router clones Filters per route and again per source entry (`src/whet/route/Router.hx:35`, `src/whet/route/Router.hx:63`) after calling stone.list() for every candidate (`src/whet/route/Router.hx:60`). Complexity grows with route fanout and asset count; consider immutable filter snapshots and direct-query APIs.
