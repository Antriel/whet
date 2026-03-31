---
# whet-ctap
title: In-flight promise deduplication (cross-tree dedup)
status: todo
type: feature
created_at: 2026-03-31T07:45:48Z
updated_at: 2026-03-31T07:45:48Z
---

Cache in-flight `getSource()`/`getHash()` promises on Stone instances to deduplicate concurrent callers from independent async trees.

## Problem

The ALS-scoped memo (whet-mxlr) deduplicates within a single async call tree. But independent call trees that overlap in time can still redundantly enter the same Stone. Concrete scenario: a game build serves index.html, which triggers asset loading — 100+ individual requests for sounds, images, etc. Each request is an independent async tree. If they all need to check the same upstream Stone's hash (e.g., ScryMultiAtlas), each independently goes through the full lock → hash → cache-hit cycle.

The lock prevents parallel *generation*, but each caller still waits in the lock queue, recomputes the hash, and checks the cache — only to get the same result as the caller ahead of it.

## Solution: In-flight promise field on Stone

Cache the currently in-flight `getSource()` / `getHash()` promise directly on the Stone instance. If a new caller arrives while a previous call is still pending, return the same promise. Once the promise settles (resolves or rejects), clear the field so the next caller starts fresh.

```haxe
// On Stone:
var _inflightSource:Promise<Source> = null;
var _inflightHash:Promise<SourceHash> = null;
```

This is pure promise coalescing — no ALS, no context management, no invalidation logic.

### Complementary to ALS memo

| Layer | Deduplicates | Scope | Lifetime |
|-------|-------------|-------|----------|
| ALS memo (whet-mxlr) | Same Stone via multiple paths in one call tree | Within a tree (diamond) | Until root promise settles, then GC'd |
| In-flight promise (this) | Same Stone requested by concurrent independent callers | Across trees | While promise is pending |

They solve different problems and compose naturally. When both are present, in-flight check happens first (it's cheaper — just a field read), then ALS memo check.

## Design

### Integration with `getSource()`

When ALS memo (whet-mxlr) is also implemented, the combined flow in `Stone.getSource()`:

```
getSource()
  ├─ _inflightSource != null? → return it (+ store in ALS memo)
  ├─ ALS memo hit? → return cached promise
  └─ Neither → start cache.getSource(), store as _inflightSource, store in ALS memo
       └─ .finally(() -> _inflightSource = null)
```

Standalone (without whet-mxlr):

```haxe
public final function getSource():Promise<Source> {
    Log.debug('Getting source.', { stone: this });
    if (_inflightSource != null) return _inflightSource;
    var p = cache.getSource(this);
    _inflightSource = p;
    p.finally(() -> { _inflightSource = null; });
    return p;
}
```

### Integration with `getHash()`

Same pattern:

```haxe
public final function getHash():Promise<SourceHash> {
    Log.debug('Generating hash.', { stone: this });
    if (_inflightHash != null) return _inflightHash;
    var p = finalMaybeHash().then(hash -> {
        if (hash != null) hash else cast getSource().then(s -> s.hash);
    });
    _inflightHash = p;
    p.finally(() -> { _inflightHash = null; });
    return p;
}
```

### Combined with ALS memo (whet-mxlr)

When both features are present, the `getSource()` flow becomes:

```haxe
public final function getSource():Promise<Source> {
    Log.debug('Getting source.', { stone: this });

    // Layer 1: Cross-tree dedup — another async tree already computing this.
    if (_inflightSource != null) {
        // Store in our ALS memo so subsequent same-tree calls also hit.
        var ctx = MemoContext.getStore();
        if (ctx != null) ctx.sources.set(this, _inflightSource);
        return _inflightSource;
    }

    // Layer 2: Same-tree dedup — already resolved in this ALS context.
    var ctx = MemoContext.getStore();
    if (ctx != null) {
        var cached = ctx.sources.get(this);
        if (cached != null) return cached;
    }

    // Layer 3: Actually compute.
    var p = /* ... create context if needed, call cache.getSource(this) ... */;
    _inflightSource = p;
    p.finally(() -> { _inflightSource = null; });
    if (ctx != null) ctx.sources.set(this, p);
    return p;
}
```

Key detail: when an in-flight promise from another tree is found, we store it in the current tree's ALS memo. This way, subsequent calls within *this* tree hit the ALS memo directly, without rechecking the in-flight field.

### `getPartialSource()` and `listIds()`

Not memoized at the in-flight level initially. `getPartialSource` is keyed by `(Stone, SourceId)` which makes the in-flight map more complex (would need `Map<SourceId, Promise>`). `listIds()` benefits from `getSource()` dedup via its fallback path. Revisit if profiling shows need.

### Error handling

On rejection, `.finally()` clears `_inflightSource`. The next caller starts a fresh computation — correct behavior since the failure may be transient (network error, temporary file lock, etc.). All callers that joined the failed promise see the same rejection.

### `refreshSource()` interaction

`CacheManager.refreshSource()` bypasses normal caching to force regeneration. It goes through `stone.acquire()` internally, so it's serialized with other operations. The in-flight dedup should NOT apply to `refreshSource()` — if the user explicitly asks to refresh, they want a new computation, not a cached in-flight promise.

Since `refreshSource()` is called on `CacheManager` (not through `Stone.getSource()`), it naturally bypasses the in-flight field. No special handling needed.

### Thread safety (JS single-threaded)

JS is single-threaded, so the check-then-set pattern is safe — no race between reading `_inflightSource` and setting it. The `.finally()` callback runs as a microtask after the promise settles, before any new synchronous code runs. Between settlement and `.finally()`, no other code can observe the stale field.

## Implementation Tasks

- [ ] Add `_inflightSource:Promise<Source>` and `_inflightHash:Promise<SourceHash>` fields to Stone
- [ ] Modify `getSource()` to check/set in-flight promise with `.finally()` cleanup
- [ ] Modify `getHash()` to check/set in-flight promise with `.finally()` cleanup
- [ ] If whet-mxlr is already implemented, integrate: in-flight check first, then ALS memo, with cross-storage on hit
- [ ] Add test: two concurrent `getSource()` calls return the same promise instance
- [ ] Add test: after resolution, next `getSource()` starts fresh (field is cleared)
- [ ] Add test: after rejection, next `getSource()` retries (field is cleared)
- [ ] Add test: `refreshSource()` is not affected by in-flight dedup
- [ ] Add test: concurrent `getHash()` calls return same promise
- [ ] Profile game project's server mode — many simultaneous asset requests should show reduced Stone entries

## When to implement

This is lower priority than whet-mxlr. The ALS memo handles the primary problem (diamond dependencies within a build). The in-flight dedup helps with the concurrent-requests scenario (server mode, many parallel asset loads). Implement after whet-mxlr, measure, and decide if the additional complexity is justified.

## Open Questions

- [ ] Should `listIds()` get its own in-flight field? It's frequently called by Router.get() and falls back to `getSource()`. If `list()` is implemented (returns fast), the fallback doesn't trigger. Only matters for Stones without `list()`.
- [ ] Should we track in-flight dedup hits in logs/profiler for observability?
