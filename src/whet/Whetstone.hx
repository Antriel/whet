package whet;

import whet.WhetSource;
import whet.cache.Cache;
import whet.cache.CacheManager;

#if !macro
@:autoBuild(whet.Macros.addDocsMeta())
#end
abstract class Whetstone<T:WhetstoneConfig> {

    public var config:T;

    // public var defaultFilename:String = "file.dat"; // TODO we don't need this anymore, right?

    /** If true, hash of a cached file (not `stone.getHash()` but actual file contents) won't be checked. */
    public var ignoreFileHash:Bool = false;

    // var project:WhetProject;
    public var id(get, set):WhetstoneId;
    public var cacheStrategy(get, set):CacheStrategy;

    public function new(config:T) {
        this.config = config;
        if (config.id == null) config.id = this;
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultStrategy;
        // project.addCommands(this); // TODO search for commands after calling `init`.
    }

    // var router:WhetSourceRouter;
    // public var routeDynamic:SourceId->Whetstone;
    // public function route(routes:Map<SourceId, Whetstone>):Whetstone {
    //     if (router == null) router = routes;
    //     else if (routes != null) for (k => v in routes) router.add(k, v);
    //     return this;
    // }
    // public function findStone(id:SourceId):Whetstone {
    //     var result = router == null ? null : router.find(id);
    //     if (result == null && routeDynamic != null) {
    //         result = routeDynamic(id);
    //         if (result != null) route([id => result]);
    //     }
    //     return result;
    // }

    /** Get WhetSource for this stone. Goes through the cache. */
    public final function getSource():WhetSource return CacheManager.getSource(this);

    /**
     * Generates new WhetSource. Used by the cache when needed.
     * Hash passed should be the same as is this stone's current one. Passed in as optimization.
     */
    @:allow(whet.cache) final function generateSource(hash:WhetSourceHash):WhetSource {
        var data = generate(hash);
        if (data != null) {
            if (hash == null) { // Default hash is byte hash of the generated result.
                hash = WhetSourceHash.merge(...data.map(d -> WhetSourceHash.fromBytes(d.data)));
            }
            return new WhetSource(data, hash, this, Sys.time());
        } else return null;
    }

    public function getHash():WhetSourceHash return null;

    /**
     * Function that actually generates the source. Passed hash is only non-null
     * if `getHash()` is implemented. It can be used for `CacheManager.getDir` and
     * is passed mainly as optimization.
     */
    private abstract function generate(hash:WhetSourceHash):Array<WhetSourceData>;

    /**
     * Returns a list of sources that this stone generates.
     * Used by Router for finding the correct asset.
     * Default implementation generates the sources to find their ids, but can be overriden
     * to provide optimized implementation that would avoid generating assets we might not need.
     */
    public function list():Array<SourceId> {
        return getSource().data.map(sd -> sd.id);
    }

    /** Caches this resource under supplied `path` as a single, always up-to-date copy. */
    public function cacheAsSingleFile(path:SourceId):Whetstone<T> {
        config.cacheStrategy = SingleAbsolute(path, KeepForever);
        getSource();
        return this;
    }

    private inline function get_id() return config.id;

    private inline function set_id(id:WhetstoneId) return config.id = id;

    private inline function get_cacheStrategy() return config.cacheStrategy;

    private inline function set_cacheStrategy(cacheStrategy:CacheStrategy) return config.cacheStrategy = cacheStrategy;

}

abstract WhetstoneId(String) from String to String {

    @:from
    public static inline function fromClass(v:Class<Stone>):WhetstoneId
        return Type.getClassName(v).split('.').pop();

    @:from
    public static inline function fromInstance(v:Stone):WhetstoneId
        return fromClass(Type.getClass(v));

}

@:structInit class WhetstoneConfig {

    public var cacheStrategy:CacheStrategy = null;
    public var id:WhetstoneId = null;

}

typedef Stone = Whetstone<Dynamic>;

// class WhetSource {
//     public final data:haxe.io.Bytes;
//     public final origin:Whetstone;
//     public final hash:WhetSourceHash;
//     public final ctime:Float;
//     public var length(get, never):Int;
//     public var lengthKB(get, never):Int;
//     var filePath:SourceId = null;
//     private function new(origin, data, hash, ctime = null) {
//         this.data = data;
//         this.hash = hash;
//         this.origin = origin;
//         this.ctime = ctime != null ? ctime : Sys.time();
//     }
//     public static function fromFile(stone:Whetstone, path:String, hash:WhetSourceHash, ctime:Float = null):WhetSource {
//         if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return null;
//         var source = fromBytes(stone, sys.io.File.getBytes(path), hash);
//         source.filePath = path;
//         return source;
//     }
//     public static function fromString(stone:Whetstone, s:String, hash:WhetSourceHash) {
//         return fromBytes(stone, haxe.io.Bytes.ofString(s), hash);
//     }
//     public static function fromBytes(stone:Whetstone, data:haxe.io.Bytes, hash:WhetSourceHash, ctime:Float = null):WhetSource {
//         if (hash == null) hash = WhetSourceHash.fromBytes(data);
//         return new WhetSource(stone, data, hash, ctime);
//     }
//     public function hasFile():Bool return this.filePath != null;
//     public function getFilePath():SourceId {
//         if (this.filePath == null) {
//             this.filePath = CacheManager.getFilePath(origin);
//             Utils.saveBytes(this.filePath, this.data);
//         }
//         return this.filePath;
//     }
//     inline function get_length() return data.length;
//     inline function get_lengthKB() return Math.round(length / 1024);
// }
