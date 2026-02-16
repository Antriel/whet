---
# whet-2plr
title: 'Performance: wildcard queries bypass output-filter pruning'
status: todo
type: task
priority: normal
created_at: 2026-02-14T08:29:36Z
updated_at: 2026-02-14T08:30:06Z
parent: whet-4ve1
---

OutputFilterMatcher only applies pattern check for non-wildcard queries (`src/whet/route/OutputFilterMatcher.hx:32`) and returns true for wildcard queries by default. Adding glob-intersection logic would prune large subtrees for broad queries and speed Router.get.
