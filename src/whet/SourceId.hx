package whet;

using haxe.io.Path;

abstract SourceId(String) {

    public var withoutExt(get, set):String;
    public var withExt(get, set):String;
    public var ext(get, set):String;
    public var dir(get, set):SourceId;

    @:from public inline static function fromString(s:String):SourceId {
        var norm = '/' + (if (s.charAt(0) == '/') s.substr(1) else s).normalize();
        return (s.lastIndexOf('/') == s.length - 1) ? cast norm.addTrailingSlash() : cast norm;
    }

    public inline function toRelPath(root:RootDir):String // Remove start slash -> make relative to CWD.
        return if ((cast root:String).length == 1) this.substring(1);
        // Remove start and end slash of root and join with `this` which starts with slash.
        else (cast root:String).substring(1, (cast root:String).length - 1) + this;

    public inline function isDir():Bool return this == dir;

    public inline function asDir():SourceId return cast this.addTrailingSlash();

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
        if (!directory.isDir()) throw '"$directory" is not a directory.';
    }

    private inline function get_withExt() return this.withoutDirectory();

    private inline function set_withExt(v:String):String {
        if (v.length > 0) this = (cast dir:String) + v;
        return v;
    }

    private inline function get_ext() return this.extension();

    private inline function set_ext(v):String {
        var p = new Path(this);
        p.ext = v;
        return this = cast fromString(p.toString());
    }

    private inline function get_withoutExt() return this.withoutDirectory().withoutExtension();

    private inline function set_withoutExt(v):String return this = '/$dir$v' + (ext == "" ? "" : '.$ext');

    private inline function get_dir():SourceId return this.directory().addTrailingSlash();

    private inline function set_dir(v):SourceId throw "Not implemented";

}

@:forward abstract RootDir(SourceId) from SourceId to SourceId {

    @:from public static function fromProject(p:Project):RootDir return p.rootDir;

}
