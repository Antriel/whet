package whet;

import js.node.Path.posix as Path;

@:using(whet.SourceId.IdUtils) @:forward abstract SourceId(String) from String to String {

    public var withoutExt(get, set):String;
    public var withExt(get, set):SourceId;
    public var ext(get, set):String;
    public var dir(get, set):SourceId;

    private inline function get_withExt() return cast((this:SourceId).getWithExt());

    private inline function set_withExt(v:SourceId):SourceId {
        this = cast((this:SourceId).setWithExt(v));
        return v;
    }

    private inline function get_ext() return (this:SourceId).getExt();

    private inline function set_ext(v:String):String {
        this = cast((this:SourceId).setExt(v));
        return v;
    }

    private inline function get_withoutExt() return cast(this:SourceId).getWithoutExt();

    private inline function set_withoutExt(v:String):String {
        this = cast((this:SourceId).setWithoutExt(v));
        return v;
    }

    private inline function get_dir():SourceId return (this:SourceId).getDir();

    private inline function set_dir(v):SourceId {
        this = cast((this:SourceId).setDir(v));
        return v;
    }

}

@:expose class IdUtils {

    public static inline function toCwdPath(id:SourceId, root:RootDir):String {
        return Path.join('.', cast root, '.', id);
    }

    public static inline function isDir(id:SourceId):Bool return id.length == 0 || endsWithSlash(id);

    public static inline function isInDir(id:SourceId, directory:SourceId, nested:Bool = false):Bool {
        assertDir(directory);
        return nested ? getDir(id).indexOf(directory) == 0 : getDir(id) == directory;
    }

    public static inline function getRelativeTo(id:SourceId, directory:SourceId):SourceId {
        if (isInDir(id, directory, true)) {
            return id.substring(directory.length);
        } else return null;
    }

    public static inline function getPutInDir(id:SourceId, dir:SourceId):SourceId {
        assertDir(dir);
        return Path.join(dir, id);
    }

    public static inline function compare(a:SourceId, b:SourceId):Int
        return if ((a:String) < (b:String)) -1
        else if ((a:String) > (b:String)) 1
        else 0;

    public static inline function assertDir(directory:SourceId) {
        if (!isDir(directory)) throw new js.lib.Error('"$directory" is not a directory.');
    }

    public static inline function getWithExt(id:SourceId) {
        return id.substring(id.lastIndexOf('/') + 1);
    }

    public static inline function setWithExt(id:SourceId, name:SourceId):SourceId {
        return Path.join(getDir(id), name);
    }

    public static inline function getExt(id:SourceId) return Path.extname(id);

    public static inline function setExt(id:SourceId, ext:SourceId):SourceId {
        if (ext.length > 0 && StringTools.fastCodeAt(ext, 0) != '.'.code) ext = '.' + ext;
        return Path.join(getDir(id), getWithoutExt(id)) + ext;
    }

    public static inline function getWithoutExt(id:SourceId):SourceId {
        return Path.parse(id).name;
    }

    public static inline function setWithoutExt(id:SourceId, name:SourceId):SourceId {
        return Path.join(getDir(id), name) + getExt(id);
    }

    public static inline function getDir(id:SourceId):SourceId {
        var dir = id.substring(0, id.lastIndexOf('/') + 1);
        return if (dir.length == 0) './' else dir;
    }

    public static inline function setDir(id:SourceId, dir:SourceId):SourceId {
        return Path.join(dir, getWithExt(id));
    }

    public static function fromCwdPath(s:SourceId, root:RootDir):SourceId {
        var absPath:String = Path.resolve(normalize(s));
        var rootStr = Path.resolve((root:SourceId));
        return Path.relative(rootStr, absPath);
    }

}

@:forward abstract RootDir(SourceId) from String from SourceId to SourceId {

    @:from public static function fromProject(p:Project):RootDir return p.rootDir;

}

inline function normalize(str:String) {
    if (str.length > 0) {
        str = Path.normalize(str);
        str = StringTools.replace(str, '\\', '/');
    }
    return str;
}

inline function startsWithSlash(str:String) {
    return StringTools.fastCodeAt(str, 0) == '/'.code;
}

inline function endsWithSlash(str:String) {
    return StringTools.fastCodeAt(str, str.length - 1) == '/'.code;
}
