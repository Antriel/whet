---
# whet-p1bj
title: Data-driven workflow improvements (AudioDb migration)
status: draft
type: feature
priority: low
created_at: 2026-02-17T08:34:45Z
updated_at: 2026-02-17T08:34:45Z
parent: whet-juli
blocked_by:
    - whet-giem
---

Replace ad-hoc dynamic graph patterns in AudioDb with batch-step stones and generic ConfigStore flow:

- Move per-asset editable params into ConfigStore instead of custom JSON DB management.
- Preserve route outputs and external editing UX.
- Reduce code complexity compared to current AudioDb orchestration (syncStones() clearing and rebuilding routes).

This is Phase 6 of the plan — depends on ConfigStore being available. Lower priority, can be done after the core inspector is working.
