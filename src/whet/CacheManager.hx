package whet;

import haxe.DynamicAccess;
import whet.Whetstone;

class CacheManager {

    public static var defaultStrategy:CacheStrategy = None;

    /** Keep last used 5 for a day and last used 1 indefinitely. */
    public static var defaultFileStrategy:CacheStrategy = InFile(Any([
        LimitCountByLastUse(1),
        All([MaxAge(24 * 60 * 60), LimitCountByLastUse(5)])
    ]), AllOnUse);

    static var memCache:MemoryCache = new MemoryCache();
    @:isVar static var fileCache(get, set):FileCache;

    @:access(whet.Whetstone) static public function getSource(stone:Whetstone):WhetSource {
        return switch stone.cacheStrategy {
            case None: stone.generateSource();
            case InMemory(durability, check): memCache.get(stone, durability, check != null ? check : AllOnUse);
            case InFile(durability, check): fileCache.get(stone, durability, check != null ? check : AllOnUse);
            case SingleFile(_, durability): fileCache.get(stone, All([LimitCountByAge(1), durability]), AllOnUse);
        }
    }

    /** 
     * Get valid path to generate a file in. The path is unique per stone id and fileId.
     * If hash is supplied, and a path was already assigned, the same path is returned, assuring consistency.
     * The path is not reserved. Caching depends on stone's `cacheStrategy` and success of source generation.
     */
    static public function getFilePath(stone:Whetstone, ?fileId:SourceId, ?hash:WhetSourceHash):SourceId {
        if (fileId == null) fileId = stone.defaultFilename;
        fileId = fileId.getPutInDir(stone.id + '/');
        if (stone.cacheStrategy.match(None | InMemory(_))) fileId = fileId.getPutInDir('.temp/');
        fileId = fileId.getPutInDir('.whet/');
        return switch stone.cacheStrategy {
            case None: fileId;
            case InMemory(_): memCache.getUniqueName(stone, fileId, hash);
            case InFile(_): fileCache.getUniqueName(stone, fileId, hash);
            case SingleFile(filepath, _): filepath;
        }
        // TODO clean tmp on start/end of process
    }

    static function get_fileCache():FileCache return fileCache != null ? fileCache : (fileCache = new FileCache());

    static function set_fileCache(v):FileCache return fileCache = v;

}

enum CacheStrategy {

    None;
    InMemory(durability:CacheDurability, ?check:DurabilityCheck);
    InFile(durability:CacheDurability, ?check:DurabilityCheck);
    SingleFile(path:SourceId, durability:CacheDurability);
    // TODO combined file+memory cache?

}

enum CacheDurability {

    KeepForever;
    LimitCountByLastUse(count:Int);
    LimitCountByAge(count:Int);
    MaxAge(seconds:Int);
    Custom(keep:WhetSource->Bool);
    All(keepIfAll:Array<CacheDurability>);
    Any(keepIfAny:Array<CacheDurability>);

}

enum DurabilityCheck {

    /** Checks all cached sources for a stone, whenever the cache is used. The default. */
    AllOnUse;

    /**
     * Checks all cached sources for a stone, whenever any resource is being added to the cache.
     * Improves performance, but can leave behind invalid files.
     */
    AllOnSet;

    /** 
     * Checks just the cached source when receiving it. Useful for custom durability checks
     * and situations where the hash isn't ensuring validity.
     */
    SingleOnGet;

}

private interface Cache {

    public function get(stone:Whetstone, durability:CacheDurability, check:DurabilityCheck):WhetSource;
    public function getUniqueName(stone:Whetstone, id:SourceId, ?hash:WhetSourceHash):SourceId;

}

private class BaseCache<Key, Value:{final hash:WhetSourceHash; final ctime:Float;}> implements Cache {

    var cache:Map<Key, Array<Value>>; // Value array is ordered by use time, starting from most recently used.

    @:access(whet.Whetstone) public function get(stone:Whetstone, durability:CacheDurability, check:DurabilityCheck):WhetSource {
        var values = cache.get(key(stone));
        var ageCount = val -> Lambda.count(values, v -> v != val && v.ctime > val.ctime);
        var value:Value = null;
        if (values != null && values.length > 0) {
            var hash = stone.getHash();
            value = Lambda.find(values, v -> v.hash == hash);
            if (value != null && check.match(SingleOnGet) && !shouldKeep(stone, value, durability, v -> 0, ageCount)) {
                remove(stone, value);
                value = null;
            }
            if (value != null) setRecentUseOrder(values, value);
        }
        var src = value != null ? source(stone, value) : null;
        if (src == null) {
            if (check.match(AllOnSet)) checkDurability(stone, values, durability, v -> values.indexOf(v) + 1, v -> ageCount(v) + 1);
            src = source(stone, set(stone, stone.generateSource()));
        }
        if (check.match(AllOnUse | null)) checkDurability(stone, values, durability, v -> values.indexOf(v), ageCount);
        return src;
    }

    function set(stone:Whetstone, source:WhetSource):Value {
        var k = key(stone);
        if (!cache.exists(k)) cache.set(k, []);
        var values = cache.get(k);
        var val = value(stone, source);
        values.unshift(val);
        return val;
    }

    public function getUniqueName(stone:Whetstone, id:SourceId, ?hash:WhetSourceHash):SourceId {
        if (hash != null) {
            var existingVal = Lambda.find(cache.get(key(stone)), v -> v.hash == hash);
            if (existingVal != null) {
                var existingPath = getPathFor(existingVal);
                if (existingPath != null) return existingPath;
            }
        }
        var filenames = getFilenames(stone);
        if (filenames != null) {
            return Utils.makeUnique(id, id -> filenames.indexOf(id) >= 0, (id, v) -> {
                id.withoutExt += v;
                id;
            });
        } else return id;
    }

    function checkDurability(stone:Whetstone, values:Array<Value>, durability:CacheDurability, useIndex:Value->Int,
            ageIndex:Value->Int):Void {
        if (values == null || values.length == 0) return;
        var i = values.length;
        while (--i > 0) {
            if (!shouldKeep(stone, values[i], durability, useIndex, ageIndex)) remove(stone, values[i]);
        }
    }

    function shouldKeep(stone:Whetstone, val:Value, durability:CacheDurability, useIndex:Value->Int, ageIndex:Value->Int):Bool {
        return switch durability {
            case KeepForever: true;
            case LimitCountByLastUse(count): useIndex(val) < count;
            case LimitCountByAge(count): ageIndex(val) < count;
            case MaxAge(seconds): (Sys.time() - val.ctime) <= seconds;
            case Custom(keep): keep(source(stone, val));
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

    function remove(stone:Whetstone, value:Value):Void cache.get(key(stone)).remove(value);

    function key(stone:Whetstone):Key return null;

    function value(stone:Whetstone, source:WhetSource):Value return null;

    function source(stone:Whetstone, value:Value):WhetSource return null;

    function getFilenames(stone:Whetstone):Array<SourceId> return null;

    function getPathFor(value:Value):SourceId return null;

}

private class MemoryCache extends BaseCache<Whetstone, WhetSource> {

    public function new() {
        cache = new Map();
    }

    override function key(stone:Whetstone) return stone;

    override function value(stone:Whetstone, source:WhetSource) return source;

    override function source(stone:Whetstone, value:WhetSource):WhetSource return value;

    override function getFilenames(stone:Whetstone):Array<SourceId> {
        var list = cache.get(stone);
        if (list != null) return list.filter(s -> s.hasFile()).map(s -> s.getFilePath());
        else return null;
    }

    override function getPathFor(value:WhetSource):SourceId return value.hasFile() ? value.getFilePath() : null;

}

typedef FileCacheValue<H, S> = {

    final hash:H;
    final ctime:Float;
    final fileHash:H;
    final filePath:S;

};

typedef DbJson = DynamicAccess<Array<FileCacheValue<String, String>>>;
typedef RuntimeFileCacheValue = FileCacheValue<WhetSourceHash, SourceId>;

private class FileCache extends BaseCache<WhetstoneID, RuntimeFileCacheValue> {

    static inline var dbFile:String = '.whet/cache.json';

    public function new() {
        cache = new Map();
        if (sys.FileSystem.exists(dbFile)) {
            var db:DbJson = haxe.Json.parse(sys.io.File.getContent(dbFile));
            for (key => values in db) cache.set(key, [for (val in values) {
                hash: WhetSourceHash.fromHex(val.hash),
                ctime: val.ctime,
                fileHash: WhetSourceHash.fromHex(val.fileHash),
                filePath: val.filePath
            }]);
        }
    }

    override function key(stone:Whetstone) return stone.id;

    override function value(stone:Whetstone, source:WhetSource):RuntimeFileCacheValue return {
        hash: source.hash,
        ctime: source.ctime,
        fileHash: source.data,
        filePath: source.getFilePath()
    }

    override function source(stone:Whetstone, value:RuntimeFileCacheValue):WhetSource {
        var source = WhetSource.fromFile(stone, value.filePath, value.hash);
        if (source == null || (!stone.ignoreFileHash && value.fileHash != source.data)) {
            remove(stone, value);
            flush();
            return null;
        } else return source;
    }

    override function set(stone:Whetstone, source:WhetSource):RuntimeFileCacheValue {
        var val = super.set(stone, source);
        flush();
        return val;
    }

    override function getFilenames(stone:Whetstone):Array<SourceId> {
        var list = cache.get(stone.id);
        if (list != null) return list.map(s -> s.filePath);
        else return null;
    }

    override function remove(stone:Whetstone, value:RuntimeFileCacheValue):Void {
        if (sys.FileSystem.exists(value.filePath) && Lambda.count(cache.get(stone.id), v -> v.filePath == value.filePath) == 1)
            sys.FileSystem.deleteFile(value.filePath);
        super.remove(stone, value);
        flush();
    }

    override function setRecentUseOrder(values:Array<RuntimeFileCacheValue>, value:RuntimeFileCacheValue):Bool {
        var changed = super.setRecentUseOrder(values, value);
        if (changed) flush();
        return changed;
    }

    override function getPathFor(value:RuntimeFileCacheValue):SourceId return value.filePath;

    function flush() {
        var db:DbJson = {};
        for (id => values in cache) db.set(id, [for (val in values) {
            hash: val.hash.toHex(),
            ctime: val.ctime,
            fileHash: val.fileHash.toHex(),
            filePath: val.filePath
        }]);
        Utils.saveContent(dbFile, haxe.Json.stringify(db, null, '\t'));
    }

}
