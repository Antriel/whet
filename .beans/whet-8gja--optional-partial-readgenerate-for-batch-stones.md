---
# whet-8gja
title: Optional partial read/generate for batch Stones
status: todo
type: feature
priority: normal
created_at: 2026-02-17T08:34:27Z
updated_at: 2026-02-17T09:35:50Z
parent: whet-juli
blocked_by:
    - whet-flfg
---

Add optional per-Stone capability for partial generation, integrated natively into the existing cache infrastructure. Partial and full generation share the same cache pool — files generated partially are reusable by full generation and vice versa.

## Goal

Enable stones that produce many outputs (e.g., SharpStone processing 100+ images) to generate a single requested output efficiently, while caching it in the same pool that full generation uses. This enables fast live preview (process 1 image instead of 100+) and avoids redundant work when full generation later runs.

## Key Constraint: generateHash() Is Required for Partial Caching

Current cache behavior for stones WITHOUT `generateHash()`: the hash is computed from the byte content of ALL generated outputs. This means:
- Full generation hash = hash(all output bytes merged)
- Partial generation would produce a different hash (fewer bytes)
- They can never share cache entries because their hashes differ

**Therefore: stones that want to benefit from partial generation MUST implement `generateHash()`.** This is already recommended as an optimization (Files stone does it). For stones without `generateHash()`, partial requests fall back to full generation + filter — the existing behavior, just formalized.

This is a reasonable soft requirement, not a breaking change. Document it clearly.

## Cache Entry Model: Growable Entries

Currently, one cache entry = one complete Source (hash + all files). The proposal: cache entries can be **partial** (a subset of outputs) and **grow** as more outputs are requested.

### Entry structure change

Current `RuntimeFileCacheValue`:
```
{ hash, ctime, baseDir, files: [{ id, fileHash, filePath, mtime, size }] }
```

Add a `complete` flag:
```
{ hash, ctime, baseDir, complete: Bool, files: [{ id, fileHash, filePath, mtime, size }] }
```

- `complete = true`: all stone outputs are present (equivalent to current behavior)
- `complete = false`: only some outputs are present

For MemoryCache, the Value is `Source`. Source would need a similar `complete` flag (or a wrapper).

### Cache lookup behavior

**Partial request** (`getPartialSource(sourceId)`):
1. Find entry by hash
2. If entry exists and contains the requested sourceId -> return it (cache hit)
3. If entry exists but doesn't contain sourceId, and `complete = true` -> sourceId doesn't exist in this stone
4. If entry exists but doesn't contain sourceId, and `complete = false` -> generate just this output, add to entry
5. If no entry -> generate just this output, create new partial entry

**Full request** (`getSource()`, existing path):
1. Find entry by hash
2. If entry exists and `complete = true` -> return all (existing behavior, no change)
3. If entry exists and `complete = false` -> partial entry found, need to complete it (see "Completing a partial entry" below)
4. If no entry -> generate everything, store as complete (existing behavior, no change)

### Completing a partial entry (full generation finds partial cache)

This is the interesting case. Options for what happens when `getSource()` finds a partial cache entry:

**Option A: Generate everything fresh, replace partial entry**
- Simplest. Full generation always calls `generate(hash)` which produces all outputs.
- The partial entry is replaced with the complete one. Partial files on disk are reused if they end up in the same directory.
- Pro: No change to full generation path. Simple.
- Con: Doesn't reuse partial work (though files on disk may overlap).

**Option B: Generate only missing outputs, merge into entry**
- Requires `list()` to know the full set, and `generatePartial()` to produce individual missing items.
- For each output in `list()` not in the partial entry: call `generatePartial()`, add to entry. Mark complete.
- Pro: Maximum reuse. No redundant computation.
- Con: Requires both `list()` and `generatePartial()` to be implemented. More complex merge logic. What if `list()` output changes between sessions (e.g., input files added)?
- Con: The merged Source would have items generated at different times — is the combined hash still valid? (Yes, if using `generateHash()` — the hash is input-based, not output-based.)

**Option C: Validate partial files, generate everything, skip already-valid files**
- Call `generate(hash)` as normal. But during file writing (in FileCache), check if a file already exists with matching fileHash. If so, skip writing.
- Pro: Full generation path unchanged. Disk I/O savings but still processes everything in memory.
- Con: Doesn't save computation time (stone still generates all). Only saves disk writes.

**Recommendation**: Start with **Option A** for simplicity. Annotate as future optimization point. Option B can be added later for stones that implement both `list()` and `generatePartial()`, once we have a real use case (SharpStone).

## Stone API Changes

### New optional override: `generatePartial`

```haxe
/**
 * Optional override for partial generation.
 * Called when a single output is requested via getPartialSource().
 * Return data for the requested sourceId, or null to signal
 * "not supported" (triggers fallback to full generation + filter).
 */
private function generatePartial(sourceId:SourceId, hash:SourceHash):Promise<Null<Array<SourceData>>> {
    return Promise.resolve(null); // Default: not supported
}
```

### New public final: `getPartialSource`

```haxe
/**
 * Get source for a single output by sourceId.
 * If the stone implements generatePartial(), generates just the requested output.
 * Otherwise falls back to full generation + filter.
 * Uses the same cache as getSource() — partial and full share the pool.
 */
public final function getPartialSource(sourceId:SourceId):Promise<Source> {
    return cache.getPartialSource(this, sourceId);
}
```

### New internal: `generatePartialSource`

Similar to `generateSource` but for partial generation. Called by cache on miss. Handles:
1. Initialize dependencies (same as generateSource)
2. Try `generatePartial(sourceId, hash)`
3. If returns data -> wrap in Source (with `complete = false`)
4. If returns null -> fall back to `generateSource(hash)` then filter to sourceId (with `complete = true` on the full result cached, filtered view returned)

## Cache Interface Changes

### `Cache.hx` — add to interface

```haxe
public function getPartial(stone:AnyStone, sourceId:SourceId, durability:CacheDurability, check:DurabilityCheck):Promise<Source>;
```

### `BaseCache.hx` — add `getPartial` method

Similar to `get()` but:
- Uses the SAME hash (no augmentation — partial and full share the hash because both use `generateHash()`).
- On cache hit: checks if the entry contains the requested sourceId. If yes, returns filtered Source. If entry is complete but sourceId not found, returns null/error.
- On cache miss (entry doesn't have sourceId): calls `generatePartialSource(sourceId, hash)`, then **adds the result to the existing entry** (or creates new partial entry).
- Needs to handle the `complete` flag: an incomplete entry that lacks sourceId triggers partial generation; a complete entry that lacks sourceId means the sourceId doesn't exist.

### `BaseCache.hx` — modify `get` method (full generation path)

- After finding an entry by hash, check the `complete` flag.
- If `complete = false`: treat as cache miss (for Option A — generate everything fresh, replace entry).
- If `complete = true`: existing behavior (validate and return).

### `FileCache.hx` — changes

- Add `complete` field to `RuntimeFileCacheValue` and `FileCacheValue`.
- Serialize/deserialize in cache.json.
- **Existing entries without `complete` field**: treat as `complete = true` (backward compatible — all existing entries are full generations).
- `value()` function: set `complete = true` when storing from `generateSource` (full), `complete = false` from `generatePartialSource`.
- Partial file storage: same baseDir as full would use (same hash -> same getUniqueDir). Files accumulate in the directory.

### `MemoryCache.hx` — changes

- Value type is `Source`. Need to add `complete` flag to Source or use a wrapper.
- **Open question**: should `Source` get a `complete` field, or should MemoryCache use a wrapper like `{ source: Source, complete: Bool }`?
  - Source already has a private constructor — adding a field is straightforward but changes a core type.
  - Wrapper keeps Source clean but adds indirection.
  - **Recommendation**: Add `complete` to Source. It's a cache-related concern but Source is already cache-aware (has `origin`, `ctime`, `getDirPath`).

### `CacheManager.hx` — add routing method

```haxe
public function getPartialSource(stone:AnyStone, sourceId:SourceId):Promise<Source> {
    return switch stone.cacheStrategy {
        case None:
            stone.acquire(() -> stone.finalMaybeHash().then(hash ->
                stone.generatePartialSource(sourceId, hash)));
        case InMemory(durability, check):
            memCache.getPartial(stone, sourceId, durability, check ?? AllOnUse);
        case InFile(durability, check) | AbsolutePath(_, durability, check):
            fileCache.getPartial(stone, sourceId, durability, check ?? AllOnUse);
    };
}
```

## Project API Change

Update `getStoneSource` to use partial path when sourceId is provided:

```haxe
public function getStoneSource(id:String, ?sourceId:SourceId):Promise<Null<Source>> {
    final stone = getStone(id);
    return if (stone == null) Promise.resolve(null)
    else if (sourceId != null) stone.getPartialSource(sourceId)
    else stone.getSource();
}
```

## Interaction Matrix

| Stone capabilities | Partial request | Full request |
|---|---|---|
| No `generateHash`, no `generatePartial`, no `list` | Falls back to full gen + filter. No partial caching benefit (hash would differ). | Unchanged. |
| Has `generateHash`, no `generatePartial` | Falls back to full gen + filter. Cached as complete entry. Subsequent partial requests served from that cached full entry. | Unchanged. |
| Has `generateHash` + `generatePartial`, no `list` | Generates single output, cached as partial entry. | Finds partial entry -> generates everything fresh, replaces with complete (Option A). |
| Has `generateHash` + `generatePartial` + `list` | Generates single output, cached as partial entry. | (Future Option B) Could complete partial entry by generating only missing outputs. For now: same as above (Option A). |

## Open Questions

### Q1: How should `getPartial` in BaseCache handle adding to an existing partial entry?

BaseCache.getPartial needs to add a new file to an existing entry. Currently entries are immutable after creation. Two options:

- **Mutable entries**: After generating a partial output, mutate the existing entry's file list and update the cache. FileCache flushes to disk.
- **Replace entry**: Remove old partial entry, create new one with old files + new file. Simpler conceptually but more churn.

Recommendation: Mutable entries (simpler for FileCache which already mutates for use-ordering).

### Q2: Cache directory sharing between partial and full

If partial generates to `.whet/SharpStone/v1/sprite1.png` and full generation later runs, should full also use `v1/`?

Yes — `getUniqueDir` already returns the same dir for the same hash. Since partial and full share the hash, they naturally share the directory. Full generation would overwrite/add files in the same dir.

### Q3: What about the None cache strategy?

For `CacheStrategy.None`, there's no caching. Partial just generates and returns without storing. This is fine — stones with None caching regenerate every time anyway.

### Q4: Durability rules and partial entries

Partial entries should follow the same durability rules as full entries. A partial entry counts as one "use" for `LimitCountByLastUse`. No special treatment needed — durability is already per-entry.

### Q5: Concurrency — partial request while full generation is running?

The lock (`acquire()`) already prevents concurrent generation. If a partial request comes in while full generation is locked, it waits in the queue. When it runs, it finds the full entry and filters. No special handling needed.

## Files to Modify

1. `src/whet/Stone.hx` — add `generatePartial`, `getPartialSource`, `generatePartialSource`
2. `src/whet/Source.hx` — add `complete` field
3. `src/whet/cache/Cache.hx` — add `getPartial` to interface
4. `src/whet/cache/BaseCache.hx` — add `getPartial`, modify `get` for complete flag
5. `src/whet/cache/FileCache.hx` — add `complete` to value type, serialization
6. `src/whet/cache/MemoryCache.hx` — handle partial Source values
7. `src/whet/cache/CacheManager.hx` — add `getPartialSource` routing
8. `src/whet/Project.hx` — update `getStoneSource`

## TODO

- [ ] Design: resolve open questions
- [ ] Implement Stone API (generatePartial, getPartialSource, generatePartialSource)
- [ ] Implement Source.complete flag
- [ ] Implement Cache.getPartial interface method
- [ ] Implement BaseCache.getPartial with growable entry support
- [ ] Modify BaseCache.get to handle complete flag on existing entries
- [ ] Update FileCache value type and serialization for complete flag
- [ ] Update MemoryCache for partial Source handling
- [ ] Add CacheManager.getPartialSource routing
- [ ] Update Project.getStoneSource to use partial path
- [ ] Test: partial generation returns correct single output (fallback path)
- [ ] Test: partial generation with generatePartial override
- [ ] Test: cache sharing — partial then full, full then partial
- [ ] Test: cache isolation — different sourceIds cached correctly within same entry
