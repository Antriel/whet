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
            case InMemory(durability, check): memCache.get(stone, durability, check);
            case InFile(durability, check): fileCache.get(stone, durability, check);
        }
    }

    /** 
     * Get valid path to generate a file in. The path is unique per stone id and fileId.
     * The path is not reserved. Caching depends on stone's `cacheStrategy` and success of source generation.
     */
    static public function getFilePath(stone:Whetstone, ?fileId:SourceId):SourceId {
        if (fileId == null) fileId = "file.dat";
        fileId = fileId.getPutInDir(stone.id + '/');
        if (stone.cacheStrategy.match(None | InMemory(_))) fileId = fileId.getPutInDir('.temp/');
        fileId = fileId.getPutInDir('.whet/');
        return switch stone.cacheStrategy {
            case None: fileId;
            case InMemory(_): memCache.getUniqueName(stone, fileId);
            case InFile(_): fileCache.getUniqueName(stone, fileId);
        }
        // TODO clean tmp on start/end of process
    }

    static function get_fileCache():FileCache return fileCache != null ? fileCache : (fileCache = new FileCache());

    static function set_fileCache(v):FileCache return fileCache = v;
}

enum CacheStrategy {

    None;
    InMemory(durability:CacheDurability, check:DurabilityCheck);
    InFile(durability:CacheDurability, check:DurabilityCheck);
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
    public function getUniqueName(stone:Whetstone, id:SourceId):SourceId;

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

    public function getUniqueName(stone:Whetstone, id:SourceId):SourceId {
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

    function setRecentUseOrder(values:Array<Value>, value:Value):Void {
        values.remove(value);
        values.unshift(value);
    }

    function remove(stone:Whetstone, value:Value):Void cache.get(key(stone)).remove(value);

    function key(stone:Whetstone):Key return null;

    function value(stone:Whetstone, source:WhetSource):Value return null;

    function source(stone:Whetstone, value:Value):WhetSource return null;

    function getFilenames(stone:Whetstone):Array<SourceId> return null;
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
        if (source == null || value.fileHash != source.data) {
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
        var list = cache.get(stone);
        if (list != null) return list.map(s -> s.filePath);
        else return null;
    }

    override function remove(stone:Whetstone, value:RuntimeFileCacheValue):Void {
        if (sys.FileSystem.exists(value.filePath))
            sys.FileSystem.deleteFile(value.filePath);
        super.remove(stone, value);
        flush();
    }

    override function setRecentUseOrder(values:Array<RuntimeFileCacheValue>, value:RuntimeFileCacheValue):Void {
        super.setRecentUseOrder(values, value);
        flush();
    }

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
