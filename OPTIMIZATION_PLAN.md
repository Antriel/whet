# Whet Router Performance Optimization Plan

## Problem Summary

When routing requests through a complex Stone dependency tree, hash computation cascades through all dependencies. A single `get()` call on the bundle router takes ~200ms, with 70% spent on hash computation (1500 hashes across 270MB of source files).

The cascade happens because:
1. `Router.get(pattern)` calls `list()` on each source Stone
2. `Stone.list()` defaults to `getSource()` which validates cache via hash
3. Hash validation calls `generateHash()` which hashes all config Routers
4. `Router.getHash()` calls `get()` on its sources, recursing into more Stones

Even with file-based caching, every request recomputes hashes to validate cache entries.

---

## Optimization 1: Mtime-Based Caching

### Goal
Avoid re-reading and re-hashing file contents when files haven't changed. Use file modification time (mtime) and size as a proxy for content changes.

### Design

Two complementary improvements:

**A) In-memory HashCache for Stone hash computation**
- Caches `(filePath, mtime, size) → contentHash` in memory
- Used by `SourceHash.fromFile()` to avoid re-reading unchanged files
- No persistence needed - rebuilds quickly on process start

**B) Mtime-based validation in FileCache**
- Store mtime+size alongside fileHash in `cache.json`
- On cache validation, check mtime+size match instead of re-reading and re-hashing
- If match, trust stored fileHash without disk I/O

### Implementation Steps

#### Step 1: Create HashCache class (in-memory only)

Location: `src/whet/cache/HashCache.hx`

```haxe
class HashCache {
    static var instance:HashCache;

    var cache:Map<String, CachedHash>;  // path → {mtime, size, hash}

    public static function get():HashCache {
        if (instance == null) instance = new HashCache();
        return instance;
    }

    /**
     * Get hash for file, using cache if mtime/size match.
     * Returns cached hash or computes new one.
     */
    public function getFileHash(path:String):Promise<SourceHash> {
        return new Promise((res, rej) -> {
            Fs.stat(path, (err, stats) -> {
                if (err != null) { rej(err); return; }

                var cached = cache.get(path);
                if (cached != null &&
                    cached.mtime == stats.mtimeMs &&
                    cached.size == stats.size) {
                    res(SourceHash.fromHex(cached.hash));
                    return;
                }

                // Cache miss - read and hash
                Fs.readFile(path, (err, data) -> {
                    if (err != null) { rej(err); return; }
                    var hash = SourceHash.fromBytes(data);
                    cache.set(path, {
                        mtime: stats.mtimeMs,
                        size: stats.size,
                        hash: hash.toHex()
                    });
                    res(hash);
                });
            });
        });
    }
}

typedef CachedHash = {
    final mtime:Float;
    final size:Int;
    final hash:String;
}
```

#### Step 2: Modify SourceHash.fromFile()

Location: `src/whet/SourceHash.hx`

```haxe
public static function fromFile(path:String):Promise<SourceHash> {
    return HashCache.get().getFileHash(path);
}
```

#### Step 3: Add mtime validation to FileCache

Location: `src/whet/cache/FileCache.hx`

Update the stored file structure to include mtime+size:

```haxe
// In FileCacheValue typedef, add to files array:
final files:Array<{
    final id:S;
    final fileHash:H;
    final filePath:S;
    final mtime:Float;   // NEW
    final size:Int;      // NEW
}>;
```

Update `value()` to store mtime+size:

```haxe
function value(source:Source):Promise<RuntimeFileCacheValue> {
    // ... existing code ...
    return Promise.all([for (data in source.data) {
        var filePath = data.getFilePathId(idOverride);
        filePath.then(fp -> Fs.promises.stat(fp.toCwdPath(rootDir))).then(stats -> {
            fileHash: SourceHash.fromBytes(data.data),
            filePath: filePath,
            id: data.id,
            mtime: stats.mtimeMs,
            size: stats.size
        });
    }]);
}
```

Update `source()` to validate via mtime+size first:

```haxe
function source(stone:AnyStone, value:RuntimeFileCacheValue):Promise<Source> {
    // ... existing path validation ...

    return Promise.all([for (file in value.files) new Promise(function(res, rej) {
        var path = file.filePath.toCwdPath(rootDir);

        // First check mtime+size (fast)
        Fs.stat(path, (statErr, stats) -> {
            if (statErr != null) { rej('Invalid.'); return; }

            var mtimeMatch = file.mtime != null &&
                             stats.mtimeMs == file.mtime &&
                             stats.size == file.size;

            if (mtimeMatch && !stone.ignoreFileHash) {
                // Mtime matches - trust cached hash, just read data
                SourceData.fromFileSkipHash(file.id, path, file.filePath, file.fileHash)
                    .then(res, rej);
            } else {
                // Mtime changed or no mtime stored - fall back to hash validation
                SourceData.fromFile(file.id, path, file.filePath).then(sourceData -> {
                    if (sourceData == null ||
                        (!stone.ignoreFileHash && !sourceData.hash.equals(file.fileHash))) {
                        rej('Invalid.');
                    } else res(sourceData);
                }, err -> rej(err));
            }
        });
    })]).then(
        data -> new Source(cast data, value.hash, stone, value.ctime),
        rejected -> rejected == 'Invalid.' ? null : { js.Syntax.code('throw {0}', rejected); null; }
    );
}
```

Add helper to SourceData:

```haxe
// In Source.hx, add to SourceData:
public static function fromFileSkipHash(id:SourceId, cwdPath:String,
        filePath:SourceId, knownHash:SourceHash):Promise<SourceData> {
    return new Promise((res, rej) -> Fs.readFile(cwdPath, (err, data) -> {
        if (err != null) rej(err);
        else res(new SourceData(id, data, knownHash, filePath));
    }));
}
```

### Expected Impact

- First run: Same as before (read all files, compute hashes)
- Subsequent runs within same process: ~0.1ms per file (stat) instead of ~1ms (read+hash)
- FileCache validation: Skip hash recomputation when mtime+size unchanged
- For 1500 files: ~150ms stat time vs ~1500ms read+hash time
- Overall: 200ms → ~50-70ms (estimated 65-75% reduction)

### Correctness Guarantee

Mtime-based caching is deterministically correct:
- If file content changes, OS updates mtime
- If mtime unchanged, content is unchanged
- This is the same guarantee used by `make`, `ninja`, and other build tools

---

## Optimization 2: Output Pattern Filtering

### Goal
Skip entire Stone subtrees when their output patterns can't possibly match the query. When looking for `audio/n_1.ogg`, don't enumerate image-producing Stones at all.

### Design

**Two-stage filtering:**

1. **Quick check (O(1))**: Extension-based lookup
   - Stone declares: `outputExtensions: ['png', 'webp']`
   - Query has extension `.ogg` → no match → skip Stone entirely

2. **Precise check (O(pattern count))**: Glob pattern matching
   - Stone declares: `outputPatterns: ['multiatlas_*.png', 'multiatlas.json']`
   - Query `title.png` doesn't match any pattern → skip Stone

Stage 2 only runs if Stage 1 passes (extensions overlap).

### Data Structures

```haxe
typedef OutputFilter = {
    /**
     * File extensions this Stone can produce (without dot). Null = any.
     * Supports compound extensions like "png.meta.json" for metadata files.
     */
    var ?extensions:Array<String>;

    /** Glob patterns for output files. Null = matches any file with valid extension. */
    var ?patterns:Array<String>;
}
```

### Implementation Steps

#### Step 1: Add outputFilter to Stone base class

Location: `src/whet/Stone.hx`

```haxe
abstract class Stone<T:StoneConfig> {
    /**
     * Optional filter describing what this Stone can produce.
     * Used by Router to skip Stones that can't match a query.
     * If null, Stone is assumed to potentially produce anything.
     *
     * This should be a function (not a static value) because Stone outputs
     * may depend on runtime config which can change externally.
     */
    public function getOutputFilter():Null<OutputFilter> {
        return null;  // Default: no filter, could produce anything
    }

    // ... existing code
}

typedef OutputFilter = {
    /**
     * File extensions this Stone can produce (without dot). Null = any.
     * Supports compound extensions like "png.meta.json".
     */
    var ?extensions:Array<String>;

    /** Glob patterns for output files. Null = matches any file with valid extension. */
    var ?patterns:Array<String>;
}
```

#### Step 2: Create OutputFilterMatcher utility

Location: `src/whet/route/OutputFilterMatcher.hx`

```haxe
class OutputFilterMatcher {

    /**
     * Check if a query could possibly match a Stone's output filter.
     * Returns true if the Stone should be enumerated, false if it can be skipped.
     *
     * @param query The search pattern (often a specific file path)
     * @param filter The Stone's output filter (null = matches anything)
     * @param queryIsPattern True if query contains wildcards
     */
    public static function couldMatch(query:SourceId, filter:Null<OutputFilter>,
            queryIsPattern:Bool):Bool {
        if (filter == null) return true;  // No filter = could produce anything

        // Stage 1: Extension check
        if (filter.extensions != null) {
            var queryExt = getExtension(query);
            if (queryExt != null && !extensionMatches(queryExt, filter.extensions)) {
                return false;  // Extension mismatch - definitely skip
            }
            // If query has no extension (pattern like 'assets/**'), can't filter by ext
        }

        // Stage 2: Pattern check (only for specific file queries)
        if (!queryIsPattern && filter.patterns != null) {
            // Query is a specific file - check if it matches any output pattern
            for (pattern in filter.patterns) {
                if (Minimatch.make(pattern).match(query)) {
                    return true;  // Matches at least one pattern
                }
            }
            return false;  // Doesn't match any pattern
        }

        // Query is a pattern - would need pattern intersection check
        // For now, conservatively return true
        return true;
    }

    /**
     * Extract extension from path, supporting compound extensions.
     * "title.png" → "png"
     * "title.png.meta.json" → "png.meta.json"
     * Returns null if no extension or contains wildcard.
     */
    static function getExtension(path:SourceId):Null<String> {
        var name = path.withExt;  // filename with extension
        var firstDot = name.indexOf('.');
        if (firstDot == -1 || firstDot == name.length - 1) return null;
        var ext = name.substring(firstDot + 1).toLowerCase();
        // Ignore if extension contains wildcard
        if (ext.indexOf('*') != -1) return null;
        return ext;
    }

    /**
     * Check if query extension matches any filter extension.
     * Handles compound extensions: query "png.meta.json" matches filter "json" or "meta.json" or "png.meta.json"
     */
    static function extensionMatches(queryExt:String, filterExts:Array<String>):Bool {
        for (filterExt in filterExts) {
            if (queryExt == filterExt || queryExt.endsWith('.' + filterExt)) {
                return true;
            }
        }
        return false;
    }
}
```

#### Step 3: Modify Router.getResults() to use filtering

Location: `src/whet/route/Router.hx`

```haxe
function getResults(mainFilters:Filters, results:Array<RouteResult>):Promise<Array<RouteResult>> {
    return new Promise((res, rej) -> {
        var allRouteProms = [];

        // Determine if the query is a specific file or a pattern
        var queryPattern = mainFilters.getQueryPattern();
        var queryIsPattern = queryPattern != null &&
            (queryPattern.indexOf('*') != -1 || queryPattern.indexOf('?') != -1);

        for (route in routes) {
            var routeFilters = mainFilters.clone();
            var possible = if (route.routeUnder.isDir()) routeFilters.step(route.routeUnder)
                else routeFilters.finalize(route.routeUnder);

            if (!possible) continue;

            // NEW: Output filter check
            var outputFilter:Null<OutputFilter> = null;
            if (route.source is AnyStone) {
                outputFilter = (cast route.source:AnyStone).getOutputFilter();
            } else if (route.source is Router) {
                outputFilter = (cast route.source:Router).getOutputFilter();
            }

            if (outputFilter != null) {
                var remainingQuery = routeFilters.getRemainingQuery();
                if (!OutputFilterMatcher.couldMatch(remainingQuery, outputFilter, queryIsPattern)) {
                    continue;  // Skip this source entirely
                }
            }

            // ... rest of existing logic
        }
    });
}
```

#### Step 4: Add outputFilter to relevant Stones

(Skipped, the Stone files are in a different project.)

#### Step 5: Router computes combined outputFilter

```haxe
class Router {
    /**
     * Compute combined output filter from all routes.
     * Must be dynamic (not cached) because Stone configs can change externally.
     */
    public function getOutputFilter():Null<OutputFilter> {
        var allExtensions = new Array<String>();
        var allPatterns = new Array<String>();
        var hasUnfiltered = false;

        for (route in routes) {
            var childFilter:Null<OutputFilter> = null;

            if (route.source is AnyStone) {
                childFilter = (cast route.source:AnyStone).getOutputFilter();
            } else if (route.source is Router) {
                childFilter = (cast route.source:Router).getOutputFilter();
            }

            if (childFilter == null) {
                hasUnfiltered = true;
                break;  // Can't filter if any child is unfiltered
            }

            if (childFilter.extensions != null)
                for (ext in childFilter.extensions)
                    if (!allExtensions.contains(ext)) allExtensions.push(ext);

            if (childFilter.patterns != null)
                for (p in childFilter.patterns) {
                    // Prepend route prefix to pattern
                    var prefixed = Path.posix.join(route.routeUnder, p);
                    allPatterns.push(prefixed);
                }
        }

        if (hasUnfiltered) return null;
        return {
            extensions: allExtensions.length > 0 ? allExtensions : null,
            patterns: allPatterns.length > 0 ? allPatterns : null
        };
    }
}
```

### Pattern Matching Considerations

**For specific file queries (most common in dev server):**
- Query: `audio/ogg/n_1.ogg`
- Check extension: `ogg`
- Check patterns: does `n_1.ogg` match `multiatlas_*.png`? No → skip

**For pattern queries:**
- Query: `**/*.png`
- Extension check: `png` matches some Stones
- Pattern intersection is complex, so conservatively include matching Stones

**Compound extensions:**
- Query: `title.png.meta.json`
- Extracted extension: `png.meta.json`
- Matches filters: `json`, `meta.json`, or `png.meta.json`

**Edge cases:**
- Query with no extension: `README` → can't filter by extension
- Query is pure pattern: `**/*` → can't filter at all
- Stone has no filter: conservatively include it

### Expected Impact

For audio file queries:
- Before: Enumerate assetsOpt, assetsLossy, atlasFormats, audioRouter
- After: Skip image Stones, only enumerate audioRouter

For the 75 audio files case:
- Each request skips ~90% of the Stone tree
- Estimated: 200ms → 20-30ms per request

Combined with Optimization 1:
- Mtime cache: 200ms → 50-70ms
- Output filtering: 50-70ms → 10-20ms (for audio queries)

---

## Implementation Order

### Phase 1: Mtime Hash Cache
1. Create `HashCache.hx` (in-memory only)
2. Modify `SourceHash.fromFile()` to use cache
3. Test with existing project

### Phase 2: FileCache Mtime Validation
1. Add mtime+size fields to FileCacheValue
2. Update `value()` to store mtime+size
3. Update `source()` to validate via mtime first
4. Add `SourceData.fromFileSkipHash()` helper

### Phase 3: Output Filter Infrastructure
1. Add `OutputFilter` typedef and `getOutputFilter()` method to Stone
2. Create `OutputFilterMatcher` utility with compound extension support
3. Modify `Router.getResults()` to check filters
4. Add `getOutputFilter()` method to Router

### Phase 4: Annotate Stones
1. Add getOutputFilter to SharpStone
2. Add getOutputFilter to ScryMultiAtlas
3. Add getOutputFilter to OxiPng, AudioDb, other relevant Stones
4. Test with audio file queries

### Phase 5: Validation & Tuning
1. Profile to verify improvements
2. Adjust pattern matching logic if needed
3. Add more Stone annotations as discovered

---

## Design Decisions

1. **Pattern intersection**: Deferred. Not trivial to implement and conservative matching is acceptable for now.

2. **Dynamic output filters**: Yes. `getOutputFilter()` is a method, not a cached property, because Stone outputs depend on config which can change externally.

3. **HashCache persistence**: Not needed. In-memory cache rebuilds quickly on process start. FileCache mtime validation provides persistence benefits.

4. **Router filter caching**: Must be dynamic (computed on each access) for same reason as #2.

5. **Compound extensions**: Supported. Files like `title.png.meta.json` can be filtered by `json`, `meta.json`, or `png.meta.json`.
