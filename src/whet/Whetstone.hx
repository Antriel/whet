package whet;

import whet.CacheManager;

#if !macro
@:autoBuild(whet.Macros.addDocsMeta())
#end
class Whetstone {

    public final id:WhetstoneID;
    public var cacheStrategy:CacheStrategy;
    public var defaultFilename:String = "file.dat";

    /** If true, hash of a cached file (not `stone.getHash()` but actual file contents) won't be checked. */
    public var ignoreFileHash:Bool = false;

    var project:WhetProject;

    public function new(project:WhetProject, id:WhetstoneID = null, cacheStrategy = null) {
        this.project = project;
        this.cacheStrategy = cacheStrategy != null ? cacheStrategy : CacheManager.defaultStrategy;
        this.id = project.add(this, id != null ? id : this);
        project.addCommands(this);
    }

    var router:WhetSourceRouter;

    public var routeDynamic:SourceId->Whetstone;

    public function route(routes:Map<SourceId, Whetstone>):Whetstone {
        if (router == null) router = routes;
        else if (routes != null) for (k => v in routes) router.add(k, v);
        return this;
    }

    public function findStone(id:SourceId):Whetstone {
        var result = router == null ? null : router.find(id);
        if (result == null && routeDynamic != null) {
            result = routeDynamic(id);
            if (result != null) route([id => result]);
        }
        return result;
    }

    public final function getSource():WhetSource return CacheManager.getSource(this);

    public function getHash():WhetSourceHash {
        return generateSource().hash;
    }

    private function generateSource():WhetSource throw "Not implemented";

    /** Caches this resource under supplied `path` as a single, always up-to-date copy. */
    public function cacheAsSingleFile(path:SourceId):Whetstone {
        this.cacheStrategy = SingleFile(path, KeepForever);
        getSource();
        return this;
    }

}

abstract WhetstoneID(String) from String to String {

    @:from
    public static inline function fromClass(v:Class<Whetstone>):WhetstoneID
        return Type.getClassName(v).split('.').pop();

    @:from
    public static inline function fromInstance(v:Whetstone):WhetstoneID
        return fromClass(Type.getClass(v));

}

class WhetSource {

    public final data:haxe.io.Bytes;
    public final origin:Whetstone;
    public final hash:WhetSourceHash;
    public final ctime:Float;

    public var length(get, never):Int;
    public var lengthKB(get, never):Int;

    var filePath:SourceId = null;

    private function new(origin, data, hash, ctime = null) {
        this.data = data;
        this.hash = hash;
        this.origin = origin;
        this.ctime = ctime != null ? ctime : Sys.time();
    }

    public static function fromFile(stone:Whetstone, path:String, hash:WhetSourceHash, ctime:Float = null):WhetSource {
        if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return null;
        var source = fromBytes(stone, sys.io.File.getBytes(path), hash);
        source.filePath = path;
        return source;
    }

    public static function fromString(stone:Whetstone, s:String, hash:WhetSourceHash) {
        return fromBytes(stone, haxe.io.Bytes.ofString(s), hash);
    }

    public static function fromBytes(stone:Whetstone, data:haxe.io.Bytes, hash:WhetSourceHash, ctime:Float = null):WhetSource {
        if (hash == null) hash = WhetSourceHash.fromBytes(data);
        return new WhetSource(stone, data, hash, ctime);
    }

    public function hasFile():Bool return this.filePath != null;

    public function getFilePath():SourceId {
        if (this.filePath == null) {
            this.filePath = CacheManager.getFilePath(origin);
            Utils.saveBytes(this.filePath, this.data);
        }
        return this.filePath;
    }

    inline function get_length() return data.length;

    inline function get_lengthKB() return Math.round(length / 1024);

}

@:using(whet.Whetstone.WhetSourceHash)
class WhetSourceHash {

    static inline var HASH_LENGTH:Int = 20;

    final bytes:haxe.io.Bytes;

    function new(bytes:haxe.io.Bytes) {
        this.bytes = bytes;
    }

    public static function fromBytes(data:haxe.io.Bytes):WhetSourceHash {
        return new WhetSourceHash(haxe.crypto.Sha1.make(data));
    }

    public static function fromString(data:String):WhetSourceHash {
        return fromBytes(haxe.io.Bytes.ofString(data));
    }

    public static function add(a:WhetSourceHash, b:WhetSourceHash):WhetSourceHash {
        var data = haxe.io.Bytes.alloc(HASH_LENGTH * 2);
        data.blit(0, a.bytes, 0, HASH_LENGTH);
        data.blit(HASH_LENGTH, b.bytes, 0, HASH_LENGTH);
        return fromBytes(data);
    }

    public static function equals(a:WhetSourceHash, b:WhetSourceHash):Bool {
        return a != null && b != null && a.bytes.compare(b.bytes) == 0;
    }

    public static function toHex(hash:WhetSourceHash):String {
        return hash == null ? "" : hash.toString();
    }

    @:noCompletion public function toString():String return bytes.toHex();

    public static function fromHex(hex:String):WhetSourceHash {
        var hash = haxe.io.Bytes.ofHex(hex);
        if (hash.length != HASH_LENGTH) return null;
        else return new WhetSourceHash(hash);
    }

}
