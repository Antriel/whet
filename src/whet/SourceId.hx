package whet;

using haxe.io.Path;

abstract SourceId(String) {

    public var withoutExt(get, set):String;
    public var withExt(get, set):String;
    public var ext(get, set):String;
    public var dir(get, set):String;

    @:from public inline static function fromString(s:String):SourceId {
        var norm = '/$s'.normalize();
        return (s.lastIndexOf('/') == s.length - 1) ? cast norm.addTrailingSlash() : cast norm;
    }

    @:to public inline function toRelPath():String return this.substring(1); // Remove start slash -> make relative to CWD.

    public inline function isDir():Bool return this == dir;

    public inline function isInDir(directory:SourceId, nested:Bool = false):Bool {
        if (!directory.isDir()) throw '"$directory" is not a directory.';
        return nested ? (dir:String).indexOf(directory) == 0 : dir == directory;
    }

    private inline function get_withExt() return this.withoutDirectory();

    private inline function set_withExt(v):String {
        this = Path.join([dir, v]);
        return v;
    }

    private inline function get_ext() return this.extension();

    private inline function set_ext(v):String throw "Not implemented.";

    private inline function get_withoutExt() return this.withoutDirectory().withoutExtension();

    private inline function set_withoutExt(v):String throw "Not implemented.";

    private inline function get_dir() return this.directory().addTrailingSlash();

    private inline function set_dir(v):String throw "Not implemented";

}
