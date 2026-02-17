---
# whet-pepc
title: Project.getStone(id) lookup method
status: todo
type: task
created_at: 2026-02-17T08:32:51Z
updated_at: 2026-02-17T08:32:51Z
parent: whet-juli
blocked_by:
    - whet-v815
---

Add a Project.getStone(id) method that looks up a stone by its unique ID. Returns the Stone instance or null/throws if not found.

This is foundational for the entire inspector surface — ConfigStore, introspection API, and Scry protocol all need to address stones by ID.

Tests: test lookup by auto-deduped ID and explicit ID; test not-found behavior.
