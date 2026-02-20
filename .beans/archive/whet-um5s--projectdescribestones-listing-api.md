---
# whet-um5s
title: Project.describeStones() listing API
status: completed
type: task
priority: normal
created_at: 2026-02-17T08:32:57Z
updated_at: 2026-02-17T08:56:13Z
parent: whet-juli
blocked_by:
    - whet-v815
---

Add Project.describeStones() returning metadata for all registered stones: id, className, label (optional), outputFilter info, cacheStrategy.

Used by inspector tooling to discover the stone graph. Keep it simple — just enough metadata for a list view and basic filtering.

Tests: test output shape includes expected fields; test with mixed stone types.

## Summary of Changes\n\nAdded `Project.describeStones():Array<StoneDescription>` method and `StoneDescription` typedef to `src/whet/Project.hx`. Returns metadata for all registered stones: id, className, outputFilter, and cacheStrategy.
