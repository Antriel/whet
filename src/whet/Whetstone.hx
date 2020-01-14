package whet;

import whet.CacheManager;
import haxe.DynamicAccess;
import haxe.rtti.Meta;

class Whetstone {

    public final id:WhetstoneID;
    public var cacheStrategy:CacheStrategy;
    public var defaultFilename:String = "file.dat";

    var project:WhetProject;

    public function new(project:WhetProject, id:WhetstoneID = null, cacheStrategy = null) {
        this.project = project;
        this.cacheStrategy = cacheStrategy != null ? cacheStrategy : CacheManager.defaultStrategy;
        this.id = project.add(this, id != null ? id : this);
        var meta:DynamicAccess<Dynamic> = Meta.getFields(Type.getClass(this));
        for (name => val in meta) {
            if (Reflect.hasField(val, 'command')) {
                var justClass = ((this:WhetstoneID):String).split('.').pop();
                var fnc = function(arg) Reflect.callMethod(this, Reflect.field(this, name), [arg]);
                project.commands.set('$justClass.$name', fnc);
                if (!project.commands.exists(name)) { // add short alias if none yet exists
                    project.commands.set(name, fnc);
                }
            }
        }
    }

    var router:WhetSourceRouter;

    public function route(routes:Map<SourceId, Whetstone>) {
        if (router == null) router = routes;
        else for (k => v in routes) router.add(k, v);
        return this;
    }

    public function findStone(id:SourceId):Whetstone return router == null ? null : router.find(id);

    public final function getSource():WhetSource return CacheManager.getSource(this);

    public function getHash():WhetSourceHash return generateSource().hash;

    private function generateSource():WhetSource throw "Not implemented";

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
        if (hash == null) hash = data;
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

abstract WhetSourceHash(haxe.io.Bytes) {

    static inline var HASH_LENGTH:Int = 20;

    @:from public static function fromBytes(data:haxe.io.Bytes):WhetSourceHash {
        return cast haxe.crypto.Sha1.make(data);
    }

    @:from public static function fromString(data:String):WhetSourceHash {
        return fromBytes(haxe.io.Bytes.ofString(data));
    }

    @:op(A + B) public static function add(a:WhetSourceHash, b:WhetSourceHash):WhetSourceHash {
        var data = haxe.io.Bytes.alloc(HASH_LENGTH * 2);
        data.blit(0, cast a, 0, HASH_LENGTH);
        data.blit(HASH_LENGTH, cast b, 0, HASH_LENGTH);
        return fromBytes(data);
    }

    @:op(A == B) public function equals(other:WhetSourceHash):Bool
        return this != null && other != null && this.compare(cast other) == 0;

    @:op(A != B) public function notEquals(other:WhetSourceHash):Bool return !equals(other);

    public function toHex():String {
        return this == null ? "" : this.toHex();
    }

    public static function fromHex(hex:String):WhetSourceHash {
        var hash = haxe.io.Bytes.ofHex(hex);
        if (hash.length != HASH_LENGTH) return null;
        else return cast hash;
    }

}
