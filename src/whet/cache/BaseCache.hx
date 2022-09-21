package whet.cache;

import whet.cache.Cache;

abstract class BaseCache<Key, Value:{final hash:SourceHash; final ctime:Float;}> implements Cache {

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

    @:keep public function toString() {
        return Type.getClassName(Type.getClass(this));
    }

}
