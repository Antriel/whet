package whet;

import whet.CacheManager;
import haxe.DynamicAccess;
import haxe.rtti.Meta;

class Whetstone {

    public final id:WhetstoneID;
    public var cacheMode:CacheMode;

    var project:WhetProject;

    public function new(project:WhetProject, id:WhetstoneID = null, cacheMode = NoCache) {
        this.project = project;
        this.cacheMode = cacheMode;
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

    @:allow(whet.CacheManager) private function generateSource():WhetSource throw "Not implemented";

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
    public final source:String;
    public final hash:WhetSourceHash;

    public var length(get, never):Int;
    public var lengthKB(get, never):Int;

    var filePath:String = null;

    private function new(data, hash, pos:haxe.PosInfos) {
        this.data = data;
        this.hash = hash;
        this.source = pos.className.split('.').pop();
    }

    public static function fromFile(path:String, hash:WhetSourceHash, ?pos:haxe.PosInfos):WhetSource {
        if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return null;
        var source = fromBytes(sys.io.File.getBytes(path), hash, pos);
        source.filePath = path;
        return source;
    }

    public static function fromString(s:String, hash:WhetSourceHash, ?pos:haxe.PosInfos) {
        return fromBytes(haxe.io.Bytes.ofString(s), hash, pos);
    }

    public static function fromBytes(data:haxe.io.Bytes, hash:WhetSourceHash, ?pos:haxe.PosInfos):WhetSource {
        if (hash == null) hash = data;
        return new WhetSource(data, hash, pos);
    }

    public function getFilePath():String {
        if (this.filePath != null) return this.filePath;
        else throw "not implemented yet";
    }

    inline function get_length() return data.length;

    inline function get_lengthKB() return Math.round(length / 1024);
}

abstract WhetSourceHash(haxe.io.Bytes) {

    @:from public static function fromBytes(data:haxe.io.Bytes):WhetSourceHash {
        return cast haxe.crypto.Sha1.make(data);
    }

    @:from public static function fromString(data:String):WhetSourceHash {
        return fromBytes(haxe.io.Bytes.ofString(data));
    }

    @:op(A + B) public static function add(a:WhetSourceHash, b:WhetSourceHash):WhetSourceHash {
        var data = haxe.io.Bytes.alloc(40);
        data.blit(0, cast a, 0, 20);
        data.blit(20, cast b, 0, 20);
        return fromBytes(data);
    }

    @:op(A == B) public function equals(other:WhetSourceHash):Bool
        return this != null && other != null && this.compare(cast other) == 0;

    @:op(A != B) public function notEquals(other:WhetSourceHash):Bool return !equals(other);

    public function toString():String {
        return this == null ? "" : this.toHex();
    }

}
