package whet;

import haxe.DynamicAccess;
import haxe.rtti.Meta;

class Whetstone {

    var project:WhetProject;

    public function new(project:WhetProject) {
        this.project = project;
        if (project.stones.exists(this)) project.stones.get(this).push(this);
        else project.stones.set(this, [this]);
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

    public function getSource():WhetSource {
        throw "Not implemented";
    }

    public function findSource(id:SourceId):WhetSource {
        return router == null ? null : router.find(id);
    }

}

abstract WhetstoneID(String) from String to String {

    @:from
    public static inline function fromClass(v:Class<Whetstone>):WhetstoneID
        return Type.getClassName(v);

    @:from
    public static inline function fromInstance(v:Whetstone):WhetstoneID
        return fromClass(Type.getClass(v));
}

class WhetSource {

    public var data:haxe.io.Bytes;
    public var length:Int;
    public var lengthKB(get, never):Int;
    public final source:String;

    var filePath:String = null;

    private function new(data, length, pos:haxe.PosInfos) {
        this.data = data;
        this.length = length;
        this.source = pos.className.split('.').pop();
    }

    public static function fromFile(path:String, ?pos:haxe.PosInfos):WhetSource {
        if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return null;
        var source = fromBytes(sys.io.File.getBytes(path), pos);
        source.filePath = path;
        return source;
    }

    public static function fromString(s:String, ?pos:haxe.PosInfos) {
        return fromBytes(haxe.io.Bytes.ofString(s), pos);
    }

    public static function fromBytes(data:haxe.io.Bytes, ?pos:haxe.PosInfos):WhetSource {
        return new WhetSource(data, data.length, pos);
    }

    public function getFilePath():String {
        if (this.filePath != null) return this.filePath;
        else throw "not implemented yet";
    }

    inline function get_lengthKB() return Math.round(length / 1024);
}
