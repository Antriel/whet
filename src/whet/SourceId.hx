package whet;

using haxe.io.Path;

abstract SourceId(String) {

    public var withoutExt(get, set):String;
    public var withExt(get, set):String;
    public var ext(get, set):String;
    public var dir(get, set):SourceId;

    @:from public inline static function fromString(s:String):SourceId {
        var norm = '/$s'.normalize();
        return (s.lastIndexOf('/') == s.length - 1) ? cast norm.addTrailingSlash() : cast norm;
    }

    @:to public inline function toRelPath():String return this.substring(1); // Remove start slash -> make relative to CWD.

    public inline function toAbsolutePath():String return this;

    public inline function isDir():Bool return this == dir;

    public inline function asDir():SourceId return cast this.addTrailingSlash();

    public inline function isInDir(directory:SourceId, nested:Bool = false):Bool {
        assertDir(directory);
        return nested ? dir.toRelPath().indexOf(directory) == 0 : dir == directory;
    }

    public function relativeTo(directory:SourceId):SourceId {
        if (isInDir(directory, true)) {
            var rel = (dir.toRelPath().substr(directory.toRelPath().length):SourceId);
            rel.withExt = withExt;
            return rel;
        } else return null;
    }

    public function getPutInDir(dir:SourceId):SourceId {
        assertDir(dir);
        return dir + this;
    }

    public static inline function assertDir(directory:SourceId) {
        if (!directory.isDir()) throw '"$directory" is not a directory.';
    }

    private inline function get_withExt() return this.withoutDirectory();

    private inline function set_withExt(v:String):String {
        if (v.length > 0) this = cast fromString(Path.join([dir, v]));
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
