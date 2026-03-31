---
# whet-mxlr
title: ALS-scoped Stone memoization (within-tree dedup)
status: todo
type: feature
priority: high
created_at: 2026-03-31T07:45:47Z
updated_at: 2026-03-31T07:45:47Z
---

Memoize `getSource()`/`getHash()` per async call tree using AsyncLocalStorage to eliminate redundant cache lookups in DAG diamond dependencies.

## Problem

When multiple paths through the dependency graph converge on the same Stone (diamond dependency), each path independently enters the full cache path: lock acquisition, hash computation, cache lookup. Even with cache hits, each cycle costs 12-26ms per Stone entry (profiled on ScryMultiAtlas). In the game project, a single `AssetsManifest.getHash()` call triggers 7 separate `LockHeld` cycles on ScryMultiAtlas (~120ms total), all returning the same result. Full builds compound to hundreds of redundant entries.

The existing lock (`acquire()`) prevents parallel *generation* but not parallel *cache-checking*. Within a single logical operation (one `getSource()` call tree), a Stone's result is constant — we're paying for proof-of-freshness we don't need after the first check.

## Solution: AsyncLocalStorage-scoped memo

Use a dedicated `AsyncLocalStorage` instance (separate from profiling) to propagate a memo context through the async call tree. The first `getSource()`/`getHash()` call on a Stone creates the context if none exists; all downstream async operations inherit it via ALS. Subsequent calls to the same Stone within the same tree return the memoized Promise immediately — no lock, no hash, no cache lookup.

### Why ALS and not a generation counter

A global counter fails when multiple independent async chains overlap in time (e.g., a game build in progress while a WS config-preview request arrives). Incrementing the counter for the new request invalidates the in-flight build's memos. ALS naturally scopes each async tree independently.

### Key invariant

**Within a single async call tree, a Stone's result is constant.** This assumes Stones don't mutate during generation of other Stones, which is already an implicit requirement (the lock queue could reorder and produce inconsistent results otherwise).

## Design

### New file: `src/whet/cache/MemoContext.hx`

A lightweight context holding two maps (sources and hashes), plus static methods for ALS access.

```haxe
package whet.cache;

class MemoContext {
    // Dedicated ALS instance — independent of profiler's ALS.
    static final als = new AsyncLocalStorage<MemoContext>();

    // Use js.lib.Map for object-identity keys (Stone instances).
    final sources:js.lib.Map<AnyStone, Promise<Source>> = new js.lib.Map();
    final hashes:js.lib.Map<AnyStone, Promise<SourceHash>> = new js.lib.Map();

    public static inline function getStore():Null<MemoContext> return als.getStore();

    /** Run callback within this context. Returns the callback's return value.
        ALS.run is synchronous — it sets the store, runs the callback, restores. 
        Promises created inside inherit the context for their async continuations. */
    public static inline function run<T>(ctx:MemoContext, fn:()->T):T return als.run(ctx, fn);
}
```

Uses `js.lib.Map` (native JS Map) for O(1) object-identity lookups. No Haxe `ObjectMap` overhead.

### Modifications to `src/whet/Stone.hx`

#### `getSource()`

```haxe
public final function getSource():Promise<Source> {
    Log.debug('Getting source.', { stone: this });
    var ctx = MemoContext.getStore();
    if (ctx != null) {
        // Inside existing context — check memo.
        var cached = ctx.sources.get(this);
        if (cached != null) {
            Log.trace('Source memo hit.', { stone: this });
            return cached;
        }
        var p = cache.getSource(this);
        ctx.sources.set(this, p);
        return p;
    }
    // No context — create one. ALS propagates to all async descendants.
    var newCtx = new MemoContext();
    return MemoContext.run(newCtx, () -> {
        var p = cache.getSource(this);
        newCtx.sources.set(this, p);
        return p;
    });
}
```

The auto-creation behavior means no entry points need modification. The first Stone that gets called creates the context; dependencies, routers, and other Stones in the call tree inherit it.

#### `getHash()`

```haxe
public final function getHash():Promise<SourceHash> {
    Log.debug('Generating hash.', { stone: this });
    var ctx = MemoContext.getStore();
    if (ctx != null) {
        var cached = ctx.hashes.get(this);
        if (cached != null) {
            Log.trace('Hash memo hit.', { stone: this });
            return cached;
        }
    }
    var p = finalMaybeHash().then(hash -> {
        if (hash != null) hash else cast getSource().then(s -> s.hash);
    });
    if (ctx != null) {
        ctx.hashes.set(this, p);
    } else {
        // getHash called as entry point (no getSource above it).
        // Create context for downstream calls, but don't wrap the return —
        // getSource inside will create its own context if needed.
        // Actually: we should wrap so downstream getSource calls share context.
        var newCtx = new MemoContext();
        p = MemoContext.run(newCtx, () -> {
            var inner = finalMaybeHash().then(hash -> {
                if (hash != null) hash else cast getSource().then(s -> s.hash);
            });
            newCtx.hashes.set(this, inner);
            return inner;
        });
    }
    return p;
}
```

Note: when `getHash()` is the entry point (no existing context), we need to create the context *before* calling `finalMaybeHash()` so that downstream `getSource()` calls on dependencies participate in the same memo. This means we can't reuse the already-started promise `p` — we restart inside the ALS context.

Simplification: extract the core logic to avoid duplication:

```haxe
public final function getHash():Promise<SourceHash> {
    Log.debug('Generating hash.', { stone: this });
    var ctx = MemoContext.getStore();
    if (ctx != null) {
        var cached = ctx.hashes.get(this);
        if (cached != null) return cached;
        var p = _computeHash();
        ctx.hashes.set(this, p);
        return p;
    }
    var newCtx = new MemoContext();
    return MemoContext.run(newCtx, () -> {
        var p = _computeHash();
        newCtx.hashes.set(this, p);
        return p;
    });
}

private inline function _computeHash():Promise<SourceHash> {
    return finalMaybeHash().then(hash -> {
        if (hash != null) hash else cast getSource().then(s -> s.hash);
    });
}
```

#### `getPartialSource()`

Same pattern — check memo, delegate. Keyed by `(Stone, SourceId)` pair. Since partial sources are less commonly in diamond patterns, this could be deferred to a follow-up if it adds complexity. For now, `getPartialSource()` at minimum benefits from the `getSource()` memo via its `getSource().then(source -> source.filterTo(sourceId))` fallback path, and from the `getHash()` memo via `finalMaybeHash()`.

If we want to memoize `getPartialSource()` itself, the context needs a nested map: `Map<AnyStone, Map<SourceId, Promise<Source>>>`. SourceId is a string abstract, so a nested `js.lib.Map<String, Promise<Source>>` works. Implement only if profiling shows it matters.

#### `listIds()`

Benefits automatically from `getSource()` memoization (its fallback path). No change needed. If a Stone implements `list()` returning a fast array, repeated calls are cheap anyway.

### Auto-creation vs explicit context

The auto-creation design (first call creates context if none exists) means:
- No modification to entry points (commands, server, WS handlers)
- Works transparently for any call pattern
- Each independent top-level call gets its own context

The only downside: if two truly independent `getSource()` calls happen in sequence (not nested), each creates a separate context. The second doesn't benefit from the first's memo. This is correct behavior — between independent calls, files may have changed. Cross-call dedup is handled by the companion in-flight bean (whet-ctap).

### Router interaction

Router is not a Stone — it has its own `get()` and `getHash()` methods. Router.get() calls `stone.listIds()` on each stone, and Router.getHash() calls `stone.getHash()` on each unique stone. Both of these call Stone's public API methods which check the memo. No Router modifications needed.

However, Router.get() starts multiple async operations in parallel via `Promise.all(allRouteProms)`. All these operations inherit the ALS context from the Router.get() call. So if two routes reference the same Stone, the second `listIds()` call hits the memo. This is the core win.

### Profiler interaction

The memo check happens *before* entering the cache (and before any profiler spans). Memo hits won't produce profiler spans — they're invisible to the profiler. This is correct: the work didn't happen, so there's nothing to profile. We add `Log.trace` for memo hits instead.

To track memo effectiveness, we could add a counter to MemoContext (hits/misses) and log it when the context is GC'd or at the end of a command. Optional, not in initial implementation.

### Error handling

If `cache.getSource()` rejects, the memoized promise is a rejected promise. All callers sharing it see the same rejection. This is correct — the underlying failure is real and applies to all callers. The `handleError` mechanism on Stone already handles recovery at the generation level, and that happens inside the cache before the promise we memoize.

No special error handling needed in the memo layer.

## Implementation Tasks

- [ ] Create `src/whet/cache/MemoContext.hx` with ALS instance and `Map`-based storage
- [ ] Modify `Stone.getSource()` to check/populate memo, auto-create context
- [ ] Modify `Stone.getHash()` to check/populate memo, auto-create context
- [ ] Verify `getPartialSource()` benefits from `getSource()`/`getHash()` memos (no change needed initially)
- [ ] Add test: diamond dependency — Stone A depends on B and C, both depend on D. `A.getSource()` triggers D's cache only once (check `D.generateCount`)
- [ ] Add test: separate top-level calls create independent contexts (no cross-call contamination)
- [ ] Add test: `getHash()` memo — multiple `getHash()` calls on same stone in same tree return same promise
- [ ] Add test: works with profiling both enabled and disabled
- [ ] Add test: memo works through Router (Router.getHash() with overlapping stones)
- [ ] Build and run full test suite to verify no regressions
- [ ] Profile game project's `manifest.getSource()` before/after — expect ~80% reduction in ScryMultiAtlas entries

## Open Questions

- [ ] Should `getPartialSource()` get its own memo map? Defer until profiling shows it matters.
- [ ] Should we add memo hit/miss counters to MemoContext for observability? Nice-to-have, not blocking.
- [ ] The existing `whet-v7y2` bean (shared generation context) is a different problem (sharing state across `generatePartial` calls within one Stone). It could potentially piggyback on MemoContext's ALS for propagation, but the use cases are orthogonal. Keep them separate.
