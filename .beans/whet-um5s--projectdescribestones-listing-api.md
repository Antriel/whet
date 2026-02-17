---
# whet-um5s
title: Project.describeStones() listing API
status: todo
type: task
created_at: 2026-02-17T08:32:57Z
updated_at: 2026-02-17T08:32:57Z
parent: whet-juli
blocked_by:
    - whet-v815
---

Add Project.describeStones() returning metadata for all registered stones: id, className, label (optional), outputFilter info, cacheStrategy.

Used by inspector tooling to discover the stone graph. Keep it simple — just enough metadata for a list view and basic filtering.

Tests: test output shape includes expected fields; test with mixed stone types.
