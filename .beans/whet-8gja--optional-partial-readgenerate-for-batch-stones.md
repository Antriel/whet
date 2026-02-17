---
# whet-8gja
title: Optional partial read/generate for batch Stones
status: todo
type: feature
created_at: 2026-02-17T08:34:27Z
updated_at: 2026-02-17T08:34:27Z
parent: whet-juli
blocked_by:
    - whet-flfg
---

Add optional per-Stone capability for partial generation:

- New optional API: generate/read only requested output(s) by sourceId, with optional preview config patch.
- If stone doesn't implement it: automatic fallback to full generation + pick requested output.
- Include generation mode/context in hash namespace to avoid cache collisions between partial and full artifacts.
- Full-generation path remains canonical.

Start with SharpStone as first implementor — it already has per-image processing internally. This enables fast live preview (process 1 image instead of 100+).

Tests: test that partial generation returns correct single output; test fallback for stones without partial support; test cache isolation between partial and full generation.
