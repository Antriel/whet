package whet;

import haxe.DynamicAccess;
import whet.Whetstone;

class CacheManager {

    public static var defaultStrategy:CacheStrategy = None;

    /** Keep last 5 for a day and last 1 indefinitely. */
    public static var defaultFileStrategy:CacheStrategy = InFile(Any([
        All([MaxAge(24 * 60 * 60), MaxVersions(5)]),
        MaxVersions(1)
    ]));

    static var memCache:MemoryCache = new MemoryCache();
    static var fileCache:FileCache;

    static public function getSource(stone:Whetstone):WhetSource {
        var cache:Cache = getCache(stone);
        var source = cache.get(stone);
        if (source == null) {
            source = stone.generateSource();
            cache.set(stone, source);
        }
        return source;
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
        return getCache(stone).getUniqueName(stone, fileId);
        // TODO clean tmp on start/end of process
    }

    static function getCache(stone:Whetstone):Cache return switch stone.cacheStrategy {
        case None: NoCache.instance;
        case InMemory(_): memCache;
        case InFile(_): fileCache != null ? fileCache : (fileCache = new FileCache());
    }
}

enum CacheStrategy {

    None;
    InMemory(durability:CacheDurability);
    InFile(durability:CacheDurability);
    // TODO combined file+memory cache?

}

enum CacheDurability {

    KeepForever;
    MaxVersions(count:Int);
    MaxAge(seconds:Int);
    Custom(keep:WhetSource->Bool);
    All(keepIfAll:Array<CacheDurability>);
    Any(keepIfAny:Array<CacheDurability>);

}

private interface Cache {

    public function get(stone:Whetstone):WhetSource;
    public function set(stone:Whetstone, source:WhetSource):Void;
    public function getUniqueName(stone:Whetstone, id:SourceId):SourceId;

}

private class BaseCache<Key, Value:{final hash:WhetSourceHash;}> implements Cache {

    var cache:Map<Key, Array<Value>>;

    public function get(stone:Whetstone):WhetSource {
        var values = cache.get(key(stone));
        if (values != null && values.length > 0) {
            var hash = stone.getHash();
            for (val in values) if (val.hash == hash) return source(stone, val);
        }
        return null;
    }

    public function set(stone:Whetstone, source:WhetSource):Void {
        var k = key(stone);
        if (!cache.exists(k)) cache.set(k, []);
        cache.get(k).push(value(stone, source));
        // TODO eviction
    }

    public function getUniqueName(stone:Whetstone, id:SourceId):SourceId {
        var list = cache.get(key(stone));
        var filenames = getFilenames(stone);
        if (filenames != null) {
            return Utils.makeUnique(id, id -> filenames.indexOf(id) >= 0, (id, v) -> {
                id.withoutExt += v;
                id;
            });
        } else return id;
    }

    function key(stone:Whetstone):Key return null;

    function value(stone:Whetstone, source:WhetSource):Value return null;

    function source(stone:Whetstone, value:Value):WhetSource return null;

    function getFilenames(stone:Whetstone):Array<SourceId> return null;
}

private class NoCache implements Cache {

    public static final instance:NoCache = new NoCache();

    private function new() { }

    public function get(stone:Whetstone):WhetSource return null;

    public function set(stone:Whetstone, source:WhetSource):Void { }

    public function getUniqueName(stone:Whetstone, id:SourceId):SourceId return id;
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
                fileHash: WhetSourceHash.fromHex(val.fileHash),
                filePath: val.filePath
            }]);
        }
    }

    override function key(stone:Whetstone) return stone.id;

    override function value(stone:Whetstone, source:WhetSource):RuntimeFileCacheValue return {
        hash: source.hash,
        fileHash: source.data,
        filePath: source.getFilePath()
    }

    override function source(stone:Whetstone, value:RuntimeFileCacheValue):WhetSource {
        var source = WhetSource.fromFile(stone, value.filePath, value.hash);
        if (source == null || value.fileHash != source.data) {
            cache.get(stone.id).remove(value); // remove from DB
            flush();
            return null;
        } else return source;
    }

    public override function set(stone:Whetstone, source:WhetSource):Void {
        super.set(stone, source);
        flush();
    }

    override function getFilenames(stone:Whetstone):Array<SourceId> {
        var list = cache.get(stone);
        if (list != null) return list.map(s -> s.filePath);
        else return null;
    }

    function flush() {
        var db:DbJson = {};
        for (id => values in cache) db.set(id, [for (val in values) {
            hash: val.hash.toHex(),
            fileHash: val.fileHash.toHex(),
            filePath: val.filePath
        }]);
        Utils.saveContent(dbFile, haxe.Json.stringify(db, null, '\t'));
    }

}
