package whet;

import js.node.Path.posix as Path;

abstract SourceId(String) {

    public var withoutExt(get, set):String;
    public var withExt(get, set):String;
    public var ext(get, set):String;
    public var dir(get, set):SourceId;

    @:from public inline static function fromString(s:String):SourceId {
        s = Path.normalize(if (s.length > 1 && startsWithSlash(s)) s.substr(1) else s);
        s = StringTools.replace(s, '\\', '/');
        return cast if (startsWithSlash(s)) s; else '/' + s;
    }

    public inline function toCwdPath(root:RootDir):String { // Remove start slash -> make relative to CWD.
        // Check for badly formed SourceId. Could happen when some internal interface is used from JS.
        if (this.charAt(0) != '/') throw new js.lib.Error("Badly formed SourceId.");
        return Path.join('.', (cast root:String), '.', this);
    }

    public inline function isDir():Bool return endsWithSlash(cast this);

    public inline function isInDir(directory:SourceId, nested:Bool = false):Bool {
        assertDir(directory);
        return nested ? (cast dir:String).indexOf((cast directory:String)) == 0 : dir == directory;
    }

    public function relativeTo(directory:SourceId):SourceId {
        if (isInDir(directory, true)) {
            var rel:SourceId = cast this.substr((cast directory:String).length - 1);
            return rel;
        } else return null;
    }

    public function getPutInDir(dir:SourceId):SourceId {
        assertDir(dir);
        if (dir == '/') return this; // Don't put '/' in front.
        else return dir + this;
    }

    public inline function compare(other:SourceId):Int
        return if (this < (cast other:String)) -1
        else if (this > (cast other:String)) 1
        else 0;

    public static inline function assertDir(directory:SourceId) {
        if (!directory.isDir()) throw new js.lib.Error('"$directory" is not a directory.');
    }

    private inline function get_withExt() return this.substring(this.lastIndexOf('/'));

    private inline function set_withExt(v:String):String {
        if (v.length > 0) this = (cast dir:String) + v;
        return v;
    }

    private inline function get_ext() return Path.extname(this);

    private inline function set_ext(v:String):String {
        if (v.length > 0 && v.charCodeAt(0) != '.'.code) v = '.' + v;
        this = (cast dir:String) + withoutExt + v;
        return v;
    }

    private inline function get_withoutExt() return Path.parse(withExt).name;

    private inline function set_withoutExt(v):String {
        this = (cast dir:String) + v + ext;
        return v;
    }

    private inline function get_dir():SourceId return this.substring(0, this.lastIndexOf('/') + 1);

    private inline function set_dir(v):SourceId throw new js.lib.Error("Not implemented");

}

@:forward abstract RootDir(SourceId) from SourceId to SourceId {

    @:from public static function fromProject(p:Project):RootDir return p.rootDir;

}

private function startsWithSlash(str:String) return str.charCodeAt(0) == '/'.code;
private function endsWithSlash(str:String) return str.charCodeAt(str.length - 1) == '/'.code;
