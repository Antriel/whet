---
# whet-2plr
title: 'Performance: wildcard queries bypass output-filter pruning'
status: scrapped
type: task
priority: normal
created_at: 2026-02-14T08:29:36Z
updated_at: 2026-02-17T08:24:01Z
parent: whet-4ve1
---


OutputFilterMatcher only applies pattern check for non-wildcard queries (`src/whet/route/OutputFilterMatcher.hx:32`) and returns true for wildcard queries by default. Adding glob-intersection logic would prune large subtrees for broad queries and speed Router.get.

## Reasons for Scrapping

Not worth the complexity. The existing extension check (stage 1) and route prefix filtering via `routeUnder` already handle the high-value pruning cases. Wildcard queries tend to be "give me everything" queries, and literal-prefix intersection would only help in rare cases with disjoint directory prefixes. Low impact for the added complexity.
