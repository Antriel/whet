---
# whet-mwft
title: Unified routed asset contract (IRouteSource / AssetRef direction)
status: draft
type: feature
priority: low
created_at: 2026-02-17T08:34:38Z
updated_at: 2026-02-17T08:34:38Z
parent: whet-juli
---

Introduce shared abstractions for routed assets:

- IRouteSource: common contract that both Stone and Router provide for routed asset access.
- AssetRef: routed result abstraction with serveId, stable origin reference, lazy getData(), hash access.

Goal: Stone and Router both provide routed assets through the same external-facing model. Removes friction when configs evolve between single-source and batch/routed behavior. Lets Router avoid over-generation when a source supports partial operations.

Migration strategy: introduce shared interface first, keep existing internals (Source, RouteResult) and adapt incrementally. Not a big-bang rewrite.

Final method names/types TBD during implementation. This is Phase 5 of the plan — lower priority than core inspector flow.
