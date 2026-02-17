package whet.cache;

import whet.cache.Cache;

abstract class BaseCache<Key, Value:{final hash:SourceHash; final ctime:Float; final complete:Bool;}> implements Cache {

    final cache:Map<Key, Array<Value>>; // Value array is ordered by use time, starting from most recently used.
    final rootDir:RootDir;

    public function new(rootDir:RootDir, cache) {
        if (!rootDir.isDir()) throw new js.lib.Error("Root dir is a not a dir.");
        this.rootDir = rootDir;
        this.cache = cache;
    }

    public function get(stone:AnyStone, durability:CacheDurability, check:DurabilityCheck):Promise<Source> {
        return stone.acquire(() -> return stone.finalMaybeHash().then(hash -> {
            // Default hash is hash of generated source, but generate it only once as optimization.
            if (hash == null)
                Log.debug('Generating source, because it does not supply a hash.', { stone: stone, cache: this });
            return if (hash == null) stone.generateSource(null).then(generatedSource -> {
                generatedSource: generatedSource,
                hash: generatedSource.hash
            }) else {
                Log.debug('Stone provided hash.', { stone: stone, hash: hash.toHex() });
                Promise.resolve({
                    generatedSource: null,
                    hash: hash
                });
            }
        }).then(data -> {
            var generatedSource = data.generatedSource;
            var hash = data.hash;
            var values = cache.get(key(stone));
            var ageCount = val -> Lambda.count(values, v -> v != val && v.ctime > val.ctime);
            var value:Value = null;
            if (values != null && values.length > 0) {
                value = Lambda.find(values, v -> v.hash.equals(hash));
                if (value != null && check.match(SingleOnGet) && !shouldKeep(stone, value, durability, v -> 0, ageCount)) {
                    remove(stone, value);
                    value = null;
                }
                if (value != null) setRecentUseOrder(values, value);
            }
            var srcPromise = (value != null ? source(stone, value) : Promise.resolve(null)).then(src -> {
                return if (src == null) {
                    Log.trace('Not cached.', { stone: stone, cache: this });
                    (if (value != null) remove(stone, value) else Promise.resolve(null)).then(_ -> {
                        if (check.match(AllOnSet)) checkDurability(stone, values, durability,
                            v -> values.indexOf(v) + 1, v -> ageCount(v) + 1);
                        (generatedSource != null ? Promise.resolve(generatedSource) : stone.generateSource(hash))
                            .then(src -> set(src)).then(val -> source(stone, val));
                    });
                } else if (!src.complete) {
                    Log.trace('Found partial entry in cache, completing.', { stone: stone, cache: this });
                    completePartialEntry(stone, value, hash).then(val -> source(stone, val));
                } else {
                    Log.trace('Found in cache', { stone: stone, cache: this });
                    Promise.resolve(src);
                }
            });
            return srcPromise.then(src -> {
                if (check.match(AllOnUse | null)) checkDurability(stone, values, durability, v -> values.indexOf(v), ageCount);
                return src;
            });
        }));
    }

    public function getPartial(stone:AnyStone, sourceId:SourceId, durability:CacheDurability, check:DurabilityCheck):Promise<Null<Source>> {
        // Hash is guaranteed non-null here (gated in Stone.getPartialSource).
        return stone.acquire(() -> stone.finalMaybeHash().then(hash -> {
            var values = cache.get(key(stone));
            var value:Value = null;
            if (values != null && values.length > 0) {
                value = Lambda.find(values, v -> v.hash.equals(hash));
                if (value != null) setRecentUseOrder(values, value);
            }
            if (value != null && hasSourceId(value, sourceId)) {
                // Cache hit — entry has the requested sourceId.
                return source(stone, value).then(src -> src != null ? src.filterTo(sourceId) : null);
            } else if (value != null && value.complete) {
                // Entry is complete but doesn't have sourceId — it doesn't exist.
                return Promise.resolve(null);
            } else {
                // Need to generate: either no entry, or incomplete entry missing this sourceId.
                return stone.generatePartialSource(sourceId, hash).then(result -> {
                    if (result.complete) {
                        // generatePartial not supported — got full source back.
                        var storePromise = if (value != null)
                            replaceEntry(stone, value, result.source)
                        else
                            set(result.source);
                        return storePromise.then(_ -> result.source.filterTo(sourceId));
                    } else {
                        // Got partial result. Merge into entry or create new one.
                        if (value != null) {
                            return mergePartial(stone, value, result.source, false)
                                .then(_ -> result.source.filterTo(sourceId));
                        } else {
                            return set(result.source).then(_ -> result.source.filterTo(sourceId));
                        }
                    }
                });
            }
        }));
    }

    function set(source:Source):Promise<Value> {
        Log.trace('Setting source in cache.', { source: source });
        var k = key(source.origin);
        if (!cache.exists(k)) cache.set(k, []);
        return value(source).then(val -> {
            var values = cache.get(k);
            values.unshift(val);
            return val;
        });
    }

    public function getUniqueDir(stone:AnyStone, baseDir:SourceId, ?hash:SourceHash):SourceId {
        if (hash != null) {
            var values = cache.get(key(stone));
            if (values != null) {
                var existingVal = Lambda.find(values, v -> v.hash.equals(hash));
                if (existingVal != null) {
                    var existingPath = getDirFor(existingVal);
                    if (existingPath != null) return existingPath;
                }
            }
        }
        var filenames = getExistingDirs(stone);
        var maxNum = if (filenames != null) Lambda.fold(filenames, (fn, num) -> {
            var parts = fn.dir.toCwdPath(rootDir).split('/');
            var name = parts.length > 1 ? parts[parts.length - 2] : '';
            Math.max(num, name.charAt(0) == 'v' ? Std.parseInt(name.substr(1)) : 0);
        }, 0);
        else 0;
        maxNum++;
        return ('v$maxNum/':SourceId).getPutInDir(baseDir);
    }

    /**
     * Complete a partial cache entry. Tries list() for incremental completion,
     * falls back to full generateSource() if list() returns null.
     */
    function completePartialEntry(stone:AnyStone, existing:Value, hash:SourceHash):Promise<Value> {
        return stone.list().then(allIds -> {
            if (allIds != null) {
                // Incremental completion: generate only missing items.
                var missingIds = allIds.filter(id -> !hasSourceId(existing, id));
                if (missingIds.length == 0) {
                    // All present, just mark complete.
                    return mergePartial(stone, existing, null, true);
                }
                var chain:Promise<Value> = Promise.resolve(existing);
                for (missingId in missingIds) {
                    chain = chain.then(current ->
                        stone.generatePartialSource(missingId, hash).then(result ->
                            mergePartial(stone, current, result.source, false)
                        )
                    );
                }
                // After all missing items merged, mark complete.
                return chain.then(current -> mergePartial(stone, current, null, true));
            } else {
                // Can't enumerate — full generation, replace entry.
                return stone.generateSource(hash).then(fullSource ->
                    replaceEntry(stone, existing, fullSource)
                );
            }
        });
    }

    function checkDurability(stone:AnyStone, values:Array<Value>, durability:CacheDurability, useIndex:Value->Int,
            ageIndex:Value->Int):Void {
        Log.debug("Checking durability.", { stone: stone, durability: Std.string(durability) });
        if (values == null || values.length == 0) return;
        var i = values.length;
        while (--i > 0) {
            if (!shouldKeep(stone, values[i], durability, useIndex, ageIndex)) remove(stone, values[i]);
        }
    }

    function shouldKeep(stone:AnyStone, val:Value, durability:CacheDurability, useIndex:Value->Int, ageIndex:Value->Int):Bool {
        return switch durability {
            case KeepForever: true;
            case LimitCountByLastUse(count): useIndex(val) < count;
            case LimitCountByAge(count): ageIndex(val) < count;
            case MaxAge(seconds): (Sys.time() - val.ctime) <= seconds;
            case Custom(keep): keep(stone, val);
            case All(keepIfAll): Lambda.foreach(keepIfAll, d -> shouldKeep(stone, val, d, useIndex, ageIndex));
            case Any(keepIfAny): Lambda.exists(keepIfAny, d -> shouldKeep(stone, val, d, useIndex, ageIndex));
        }
    }

    function setRecentUseOrder(values:Array<Value>, value:Value):Bool {
        if (values[0] == value) return false;
        values.remove(value);
        values.unshift(value);
        return true;
    }

    function remove(stone:AnyStone, value:Value):Promise<Nothing> {
        Log.debug('Removing cached value.', { stone: stone, valueHash: value.hash.toHex() });
        cache.get(key(stone)).remove(value);
        return Promise.resolve(null);
    }

    abstract function key(stone:AnyStone):Key;

    abstract function value(source:Source):Promise<Value>;

    abstract function source(stone:AnyStone, value:Value):Promise<Source>;

    abstract function getExistingDirs(stone:AnyStone):Array<SourceId>;

    abstract function getDirFor(value:Value):SourceId;

    /** Check if entry contains a specific sourceId. */
    abstract function hasSourceId(value:Value, sourceId:SourceId):Bool;

    /** Merge partial source data into an existing entry, returns the updated value. */
    abstract function mergePartial(stone:AnyStone, existing:Value, addition:Source, markComplete:Bool):Promise<Value>;

    /** Replace an existing entry with a new complete source. */
    abstract function replaceEntry(stone:AnyStone, existing:Value, replacement:Source):Promise<Value>;

    @:keep public function toString() {
        return Type.getClassName(Type.getClass(this));
    }

}
