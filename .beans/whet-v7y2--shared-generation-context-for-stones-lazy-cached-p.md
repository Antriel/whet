---
# whet-v7y2
title: Shared generation context for Stones (lazy-cached per batch)
status: draft
type: feature
priority: normal
created_at: 2026-02-25T09:49:20Z
updated_at: 2026-02-25T09:51:12Z
---

Add a mechanism for Stones to compute expensive shared state once per generation batch and reuse it across all generatePartial() calls.


## Problem

When a Stone implements `generatePartial(sourceId, hash)`, it is called once per output file. Some stones need expensive upfront work (e.g. enumerating all sources, resolving metadata/pipelines, mapping output IDs back to inputs). Currently this work is repeated N times — once per output. There is no built-in way to share computed state across `generatePartial` calls within the same generation cycle.

## Proposed API: `generateContext(hash)`

Add a new overridable method to Stone:

```haxe
// Stone.hx — new overridable method
private function generateContext(hash:SourceHash):Promise<Dynamic> {
    return Promise.resolve(null);
}
```

And an internal cached accessor that caches the **Promise** (not the resolved value) to handle concurrent calls from `Promise.all` in `generate()`:

```haxe
// Stone.hx — internal, not overridable
private var _contextPromise:{ hash:SourceHash, promise:Promise<Dynamic> };

private function getContext(hash:SourceHash):Promise<Dynamic> {
    if (_contextPromise != null
        && (_contextPromise.hash == hash  // covers null == null
            || (_contextPromise.hash != null && _contextPromise.hash.equals(hash))))
        return _contextPromise.promise;
    var p = generateContext(hash);
    _contextPromise = { hash: hash, promise: p };
    return p;
}
```

### Usage by Stone implementers

A Stone overrides `generateContext` to do the expensive upfront work, and calls `getContext(hash)` from within `generatePartial`:

```haxe
override function generateContext(hash) {
    // Expensive: enumerate all inputs, resolve pipelines, build lookup maps
    return dependency.getSource().then(source -> {
        var lookup = new Map();
        for (d in source.data) lookup.set(transformId(d.id), d);
        return (cast lookup : Dynamic);
    });
}

override function generatePartial(sourceId, hash) {
    return getContext(hash).then(ctx -> {
        var lookup:Map<String, SourceData> = cast ctx;
        var input = lookup.get(sourceId);
        return processOne(input);
    });
}
```

### Caching rules

- **Storage**: In-memory only (object reference, no serialization). Just a JS object held on the stone instance.
- **Key**: The generation hash. Same hash = same context. When hash changes, `generateContext` is re-invoked.
- **Lifetime**: Survives across multiple `getSource()`/`getPartialSource()` calls as long as the hash matches. If dependencies have not changed, the context is reused across separate cache lookups.
- **Clearing**: Naturally invalidated when the hash changes. No explicit clearing needed.


## Comparison: Metadata-in-output workaround

An alternative without framework changes: a Stone stores its context as a special output (e.g. `"__context__"`), and each `generatePartial` call retrieves it via `getPartialSource("__context__")` which goes through existing cache machinery.

### How it would work

1. `list()` returns `["__context__", "file1.css", "file2.css", ...]`
2. `generatePartial("__context__", hash)` computes the expensive shared state, serializes it to a Buffer, returns it as SourceData
3. `generatePartial("file1.css", hash)` first calls `this.getPartialSource("__context__")` (which hits cache after first call), deserializes the context, then processes file1.css

### Problems with this approach

- **Weird branching in `generatePartial`**: The method must check "is this a context request or a real output?" — two fundamentally different code paths in the same method.
- **Unwanted output**: `"__context__"` appears in `list()` and the generated Source. Consumers see it as a real file. Would need filtering at the Router level or a naming convention to hide it.
- **Serialization overhead**: Context must be serialized to Buffer and deserialized back. For complex objects (Maps, class instances, closures), this is awkward or impossible. The whole point is to share an in-memory object reference.
- **Cache storage mismatch**: The context gets stored in FileCache/MemoryCache following the stone's cache strategy. But context is ephemeral computed state — it does not need file-backed persistence, and serializing it to disk is pure waste.
- **Indirection and fragility**: `getPartialSource` calling back into the same stone creates a recursive-looking pattern that is hard to reason about, even though the cache layer handles it correctly.
- **Hash as SourceData**: The context's hash would be its own content hash, which is meaningless — we want it keyed by the generation hash, not by what is inside it.

### Verdict

The metadata-in-output approach is a clever hack but fights the system's design. The framework approach (`generateContext`) is cleaner, more efficient (no serialization), and does not pollute the output namespace.


## Open Questions

- [ ] **Type safety**: `Dynamic` return loses type information. Options:
  - (a) Just use `Dynamic` — pragmatic, stone authors cast inside `generatePartial`. Simple.
  - (b) Add a second type parameter: `Stone<Config, Context>` — breaking change, heavy for a feature most stones won't use.
  - (c) Typed wrapper pattern: each stone defines its own `getTypedContext()` wrapping `getContext()` with a cast — boilerplate but type-safe at usage.
  - Leaning toward (a).

- [x] **Null hash**: Resolved. When `generateHash()` returns null, `getPartialSource()` bypasses partial caching entirely — it falls back to full `getSource()` + filter (Stone.hx:246-247). `generatePartial` only receives null hash when called from the default `generate()` batch path via `Promise.all`. The Promise-caching in `getContext` still works correctly here: all concurrent calls from the same `Promise.all` batch share the same Promise. We just need `getContext` to treat `null == null` as a cache hit (both old and new hash are null → reuse). No cross-invocation caching is needed or desired since there's no stable hash to key on — the context is computed once per batch, used N times, and naturally superseded on next invocation.

- [ ] **Concurrent `getContext` calls**: The default `generate()` fires all `generatePartial()` calls via `Promise.all()`. Multiple `getContext(hash)` calls could race. Since JS is single-threaded, the first call's synchronous check will miss, starting `generateContext()`. Before that resolves, other calls also check and miss. **Must cache the Promise, not the resolved value**, to avoid duplicate computation. This is already addressed in the proposed API above.

- [ ] **Method naming**: `generateContext` / `getContext` vs alternatives like `prepareContext` / `getSharedState` / `computeBatchState`. The `generate*` prefix is consistent with the existing `generate`/`generatePartial`/`generateHash` family.

- [ ] **Should context contribute to hash?**: Probably not — context is *derived from* the inputs that already contribute to the hash. Adding it would be circular. But worth confirming this assumption holds.

- [ ] **Interaction with `acquire()` locking**: When `getContext` is called from `generatePartial` (which runs inside `acquire()`), and `generateContext` itself calls `dependency.getSource()`, that call goes to a *different* stone's lock — no deadlock risk. But if `generateContext` somehow needed to call back into the *same* stone (e.g. `this.getPartialSource()`), that would deadlock since `acquire()` is already held. This should be documented as a constraint: `generateContext` must not call back into its own stone.

## Implementation Tasks

- [ ] Add `generateContext(hash)` overridable method to Stone.hx (returns `Promise<Dynamic>`, default returns `Promise.resolve(null)`)
- [ ] Add `getContext(hash)` internal method with Promise-level caching keyed by hash
- [ ] Handle null-hash in `getContext` (`null == null` check, see updated snippet above)
- [ ] Add tests: context computed once across N partial calls, recomputed on hash change, works with individual `getPartialSource` calls
- [ ] Verify no interaction issues with BaseCache locking / acquire
- [ ] Document the constraint that `generateContext` must not call back into the same stone
