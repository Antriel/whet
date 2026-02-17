---
# whet-jwk0
title: Request-scoped preview config patches
status: todo
type: task
created_at: 2026-02-17T08:33:44Z
updated_at: 2026-02-17T08:33:44Z
parent: whet-juli
blocked_by:
    - whet-a2d8
---

Implement the preview (temporary, request-scoped) config patch flow:

- When a preview patch is applied, it layers on top of base + persisted config for that request only.
- No global mutable overlay — the preview patch is passed through the generation call chain.
- After the request completes, the preview patch is discarded.
- Stone still consumes a single effective config object (base ← persisted ← preview merged).

This avoids the fragile overlay lifecycle from the V1 plan. The key insight: preview is per-request, not per-stone-state.

Design consideration: how to thread the preview patch through generate() without changing every Stone's signature. Options: context object, temporary config swap with restore, or generation-time merge.
