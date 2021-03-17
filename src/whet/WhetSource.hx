package whet;

import whet.cache.CacheManager;

class WhetSource {

    public final data:Array<WhetSourceData>;
    public final hash:WhetSourceHash;
    public final origin:Stone;
    public final ctime:Float;

    var dirPath:SourceId = null;

    @:allow(whet.Whetstone)
    @:allow(whet.cache)
    private function new(data:Array<WhetSourceData>, hash:WhetSourceHash, origin:Stone, ctime:Float) {
        this.data = data;
        this.hash = hash;
        this.origin = origin;
        this.ctime = ctime;
        for (entry in data) entry.source = this;
    }

    public function hasDir():Bool return dirPath != null;

    /**
     * Returns a directory path where this source data is stored.
     * If none exists yet, generates one through cache.
     */
    public function getDirPath():SourceId {
        if (dirPath == null) {
            dirPath = CacheManager.getDir(origin, hash);
            Utils.ensureDirExist(dirPath);
            // TODO: Should also store all the data entries? Or do we do that on per-data case.
        }
        return dirPath;
    }

    /**
     * Returns first result if `id` is null, or one equals to it.
     */
    public function get(?id:SourceId):WhetSourceData {
        return id == null ? data[0] : Lambda.find(data, entry -> entry.id == id);
    }

}

class WhetSourceData {

    public final data:haxe.io.Bytes;
    public final id:SourceId;

    public final hash:WhetSourceHash; // TODO Lazy byteHash?
    public var length(get, never):Int;
    public var lengthKB(get, never):Int;
    @:allow(whet.WhetSource) public var source(default, null):WhetSource;

    var filePath:SourceId = null;

    private function new(/* source, */ id, data) {
        // this.source = source;
        this.data = data;
        this.id = id;
        this.hash = WhetSourceHash.fromBytes(data);
    }

    public static function fromFile(/* source:WhetSource,  */ id:SourceId, path:String):WhetSourceData {
        if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return null;
        var source = fromBytes(/* source, */ id, sys.io.File.getBytes(path));
        source.filePath = path;
        return source;
    }

    public static function fromString(/* source:WhetSource,  */ id:SourceId, s:String) {
        return fromBytes(/* source, */ id, haxe.io.Bytes.ofString(s));
    }

    public static function fromBytes(/* source:WhetSource,  */ id:SourceId, data:haxe.io.Bytes):WhetSourceData {
        return new WhetSourceData(/* source, */ id, data);
    }

    public function hasFile():Bool return this.filePath != null;

    public function getFilePath():SourceId {
        if (this.filePath == null) {
            if (source == null) throw "Not implemented."; // Do we even want to allow such state?
            this.filePath = id.getPutInDir(source.getDirPath());
            Utils.saveBytes(this.filePath, this.data);
        }
        return this.filePath;
    }

    inline function get_length() return data.length;

    inline function get_lengthKB() return Math.round(length / 1024);

}
