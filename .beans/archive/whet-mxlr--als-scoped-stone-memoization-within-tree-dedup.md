---
# whet-mxlr
title: ALS-scoped Stone memoization (within-tree dedup)
status: completed
type: feature
priority: high
created_at: 2026-03-31T07:45:47Z
updated_at: 2026-04-01T07:18:51Z
---

Memoize `getSource()`/`getHash()`/`getPartialSource()` per async call tree using AsyncLocalStorage to eliminate redundant cache lookups in DAG diamond dependencies.

## Problem

When multiple paths through the dependency graph converge on the same Stone (diamond dependency), each path independently enters the full cache path: lock acquisition, hash computation, cache lookup. Even with cache hits, each cycle costs 12-26ms per Stone entry (profiled on ScryMultiAtlas). In the game project, a single `AssetsManifest.getHash()` call triggers 7 separate `LockHeld` cycles on ScryMultiAtlas (~120ms total), all returning the same result. Full builds compound to hundreds of redundant entries.

The existing lock (`acquire()`) prevents parallel *generation* but not parallel *cache-checking*. Within a single logical operation (one `getSource()` call tree), a Stone's result is constant — we're paying for proof-of-freshness we don't need after the first check.

## Solution: AsyncLocalStorage-scoped memo

Use a dedicated `AsyncLocalStorage` instance (separate from profiling) to propagate a memo context through the async call tree. The first entry point (`getSource()`/`getHash()`/`getPartialSource()` on a Stone, or `Router.get()`/`Router.getHash()`) creates the context if none exists; all downstream async operations inherit it via ALS. Subsequent calls to the same Stone within the same tree return the memoized Promise immediately — no lock, no hash, no cache lookup.

### Why ALS and not a generation counter

A global counter fails when multiple independent async chains overlap in time (e.g., a game build in progress while a WS config-preview request arrives). Incrementing the counter for the new request invalidates the in-flight build's memos. ALS naturally scopes each async tree independently.

### Key invariant

**Within a single async call tree, a Stone's result is constant.** This assumes Stones don't mutate during generation of other Stones, which is already an implicit requirement (the lock queue could reorder and produce inconsistent results otherwise).

## Design

### New file: `src/whet/cache/MemoContext.hx`

A lightweight context holding three maps (sources, hashes, partials), plus static methods for ALS access.

```haxe
package whet.cache;

class MemoContext {
    // Dedicated ALS instance — independent of profiler's ALS.
    static final als = new AsyncLocalStorage<MemoContext>();

    // Use js.lib.Map for object-identity keys (Stone instances).
    final sources:js.lib.Map<AnyStone, Promise<Source>> = new js.lib.Map();
    final hashes:js.lib.Map<AnyStone, Promise<SourceHash>> = new js.lib.Map();
    // Nested map: Stone → (SourceId string → Promise<Null<Source>>)
    final partials:js.lib.Map<AnyStone, js.lib.Map<String, Promise<Null<Source>>>> = new js.lib.Map();

    public static inline function getStore():Null<MemoContext> return als.getStore();

    /** Run callback within this context. Returns the callback's return value.
        ALS.run is synchronous — it sets the store, runs the callback, restores.
        Promises created inside inherit the context for their async continuations. */
    public static inline function run<T>(ctx:MemoContext, fn:()->T):T return als.run(ctx, fn);

    /** Execute fn within a MemoContext. Reuses existing context or creates a new one. */
    public static function ensure<T>(fn:()->T):T {
        if (als.getStore() != null) return fn();
        return als.run(new MemoContext(), fn);
    }
}
```

Uses `js.lib.Map` (native JS Map) for O(1) object-identity lookups. Nested map for partials keyed by `(Stone, SourceId string)`.

The `AsyncLocalStorage` extern already exists in `Profiler.hx` — extract it to a shared location (e.g., keep in `MemoContext.hx` or a small shared file, and import from both `Profiler.hx` and `MemoContext.hx`).

### Modifications to `src/whet/Stone.hx`

#### `getSource()`

```haxe
public final function getSource():Promise<Source> {
    Log.debug('Getting source.', { stone: this });
    var ctx = MemoContext.getStore();
    if (ctx != null) {
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
    return MemoContext.ensure(() -> {
        var newCtx = MemoContext.getStore();
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
        var p = _computeHash();
        ctx.hashes.set(this, p);
        return p;
    }
    return MemoContext.ensure(() -> {
        var newCtx = MemoContext.getStore();
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

```haxe
public final function getPartialSource(sourceId:SourceId):Promise<Null<Source>> {
    var ctx = MemoContext.getStore();
    if (ctx != null) {
        // Check partial memo first.
        var partialMap = ctx.partials.get(this);
        if (partialMap != null) {
            var cached = partialMap.get((sourceId:String));
            if (cached != null) {
                Log.trace('Partial source memo hit.', { stone: this, sourceId: sourceId });
                return cached;
            }
        }
        // Check if full source is already memoized — just filter it.
        var fullCached = ctx.sources.get(this);
        if (fullCached != null)
            return fullCached.then(s -> s.filterTo(sourceId));
        // Compute and store in memo.
        var p = _computePartialSource(sourceId);
        if (partialMap == null) {
            partialMap = new js.lib.Map();
            ctx.partials.set(this, partialMap);
        }
        partialMap.set((sourceId:String), p);
        return p;
    }
    return MemoContext.ensure(() -> {
        var newCtx = MemoContext.getStore();
        var p = _computePartialSource(sourceId);
        var partialMap = new js.lib.Map();
        newCtx.partials.set(this, partialMap);
        partialMap.set((sourceId:String), p);
        return p;
    });
}

private function _computePartialSource(sourceId:SourceId):Promise<Null<Source>> {
    return finalMaybeHash().then(hash -> {
        if (hash == null)
            return cast getSource().then(source -> source.filterTo(sourceId));
        else
            return cache.getPartialSource(this, sourceId);
    });
}
```

Key feature: when a full source is already memoized (e.g., `listIds()` fell through to `getSource()` during Router resolution), `getPartialSource()` just filters it — no cache/lock interaction at all. This directly benefits the server pattern where `router.get()` resolves routes and then `routeResult.get()` fetches individual files.

#### `listIds()`

No memoization needed. Either `list()` returns a fast array directly, or it falls through to `getSource()` which is memoized.

### Modifications to `src/whet/route/Router.hx`

#### `get()`

```haxe
public function get(pattern:MinimatchType = null):Promise<Array<RouteResult>> {
    return MemoContext.ensure(
        () -> getResults(new Filters(pattern != null ? makeMinimatch(pattern) : null), [])
    );
}
```

#### `getHash()`

```haxe
public function getHash(pattern:MinimatchType = null):Promise<SourceHash> {
    return MemoContext.ensure(() -> get(pattern).then(items -> {
        var uniqueStones = [];
        var serveIds = [];
        for (item in items) {
            if (uniqueStones.indexOf(item.source) == -1) uniqueStones.push(item.source);
            serveIds.push(item.serveId);
        }
        serveIds.sort((a, b) -> a.compare(b));
        Promise.all(uniqueStones.map(s -> s.getHash()))
            .then((hashes:Array<SourceHash>) -> {
                hashes.sort((a, b) -> a.toString() < b.toString() ? -1 : a.toString() > b.toString() ? 1 : 0);
                return SourceHash.merge(...hashes).add(SourceHash.fromString(serveIds.join('\n')));
            });
    }));
}
```

No other Router methods need changes — `saveInto()`, `listContents()`, `getData()`, `getString()`, `getJson()` all delegate through `get()` which creates the context. The context propagates through `.then()` continuations, so downstream `routeResult.get()` calls inherit it.

### Entry point summary

**Context creators** (create if none exists via `MemoContext.ensure`):
- `Router.get()`, `Router.getHash()` — batch boundaries for cross-stone dedup
- `Stone.getSource()`, `Stone.getHash()`, `Stone.getPartialSource()` — safety net for direct calls

**Context consumers** (check memo, never create):
- `finalizeHash()` → `stone.getHash()` on dependencies — inherits from caller
- `generateSource()` → `stone.getSource()` on dependencies — inherits from caller
- `RouteResult.get()` → `stone.getPartialSource()` — inherits from Router's context

**Not needed**:
- `Project.getStoneSource()` / `Project.listStoneOutputs()` — Stone's auto-create handles it
- `Stone.acquire()` — too deep in the call chain, memo check happens before cache entry
- `Stone.exportTo()` / `setAbsolutePath()` — Stone's auto-create handles it

### ALS propagation through the server pattern

In the UwsServerStone, each HTTP request flows as:

```
serveFile() → router.get(url) → [creates MemoContext]
  → getResults() → stone.listIds() for each route  [shares context]
  .then(results →
    serveRouteResult(results[0]) → routeResult.get()
      → stone.getPartialSource(sourceId)  [inherits context, checks sources map]
  )
```

The `.then()` continuation inherits the ALS context from the promise created inside `MemoContext.ensure()`. So `getPartialSource()` sees the same context and can check the `sources` map for a full-source shortcut.

For the `serveFromRouter` double-lookup case (directory search → index.html fallback), the second `router.get()` inside the `.then()` sees the existing context via `MemoContext.ensure()` and reuses it — both searches share the same memo.

Each HTTP request fires on a separate event loop tick with no ALS context, so each request auto-creates an independent memo. Correct isolation.

### Auto-creation vs explicit context

The auto-creation design (first call creates context if none exists) means:
- No modification to entry points (commands, server, WS handlers)
- Works transparently for any call pattern
- Each independent top-level call gets its own context

The only downside: if two truly independent `getSource()` calls happen in sequence (not nested), each creates a separate context. The second doesn't benefit from the first's memo. This is correct behavior — between independent calls, files may have changed. Cross-call dedup is handled by the companion in-flight bean (whet-ctap).

### Profiler interaction

The memo check happens *before* entering the cache (and before any profiler spans). Memo hits won't produce profiler spans — they're invisible to the profiler. This is correct: the work didn't happen, so there's nothing to profile. We add `Log.trace` for memo hits instead.

### Error handling

If `cache.getSource()` rejects, the memoized promise is a rejected promise. All callers sharing it see the same rejection. This is correct — the underlying failure is real and applies to all callers. The `handleError` mechanism on Stone already handles recovery at the generation level, and that happens inside the cache before the promise we memoize.

No special error handling needed in the memo layer.

## Implementation Tasks

- [x] Extract `AsyncLocalStorage` extern to shared location (out of `Profiler.hx`)
- [x] Create `src/whet/cache/MemoContext.hx` with ALS instance, three maps, `getStore()`, `run()`, and `ensure()` helper
- [x] Modify `Stone.getSource()` to check/populate memo, auto-create context
- [x] Modify `Stone.getHash()` to check/populate memo, auto-create context, extract `_computeHash()`
- [x] Modify `Stone.getPartialSource()` to check partial memo, check full `sources` map shortcut, auto-create context, extract `_computePartialSource()`
- [x] Modify `Router.get()` to wrap in `MemoContext.ensure()`
- [x] Modify `Router.getHash()` to wrap in `MemoContext.ensure()`
- [x] Add test: diamond dependency — Stone A depends on B and C, both depend on D. `A.getSource()` triggers D's cache only once
- [x] Add test: separate top-level calls create independent contexts (no cross-call contamination)
- [x] Add test: `getHash()` memo — multiple `getHash()` calls on same stone in same tree return same promise
- [x] Add test: `getPartialSource()` returns filtered full source when full source is memoized
- [x] Add test: memo works through Router (`Router.get()` with overlapping stones shares context with subsequent `routeResult.get()`)
- [x] Add test: works with profiling both enabled and disabled
- [x] Build and run full test suite to verify no regressions
- [ ] Profile game project's `manifest.getSource()` before/after — expect ~80% reduction in ScryMultiAtlas entries

## Open Questions

- [ ] Should we add memo hit/miss counters to MemoContext for observability? Nice-to-have, not blocking.
- [ ] The existing `whet-v7y2` bean (shared generation context) is a different problem (sharing state across `generatePartial` calls within one Stone). It could potentially piggyback on MemoContext's ALS for propagation, but the use cases are orthogonal. Keep them separate.
