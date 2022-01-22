package whet;

import js.node.Buffer;
import js.node.Fs;
import whet.Stone;

class Source {

    public final data:Array<SourceData>;
    public final hash:SourceHash;
    public final origin:AnyStone;
    public final ctime:Float;

    var dirPath:SourceId = null;

    @:allow(whet.Stone)
    @:allow(whet.cache)
    private function new(data:Array<SourceData>, hash:SourceHash, origin:AnyStone, ctime:Float) {
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
        // if (dirPath == null) {
        //     dirPath = origin.cache.getDir(origin, hash);
        //     Utils.ensureDirExist(dirPath.toRelPath(origin.project));
        //     // TODO: Should also store all the data entries? Or do we do that on per-data case.
        // }
        return dirPath;
    }

    /**
     * Returns first result if `id` is null, or one equals to it.
     */
    public function get(?id:SourceId):SourceData {
        return id == null ? data[0] : Lambda.find(data, entry -> entry.id == id);
    }

}

class SourceData {

    public final data:Buffer;
    public final id:SourceId;

    public final hash:SourceHash;
    public var length(get, never):Int;
    public var lengthKB(get, never):Int;
    @:allow(whet.Source) public var source(default, null):Source;

    var filePathId:SourceId = null;
    var filePath:String = null;

    private function new(id, data) {
        this.data = data;
        this.id = id;
        this.hash = SourceHash.fromBytes(data);
    }

    /**
     * `path` is the actual cwd-relative path. `pathId` is the project-relative source Id.
     */
    public static function fromFile(id:SourceId, path:String, pathId:SourceId):Promise<SourceData> {
        if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return null;
        return new Promise((res, rej) -> Fs.readFile(path, (err, buffer) -> {
            if (err != null) res(null);
            var source = fromBytes(id, buffer);
            source.filePath = path;
            source.filePathId = pathId;
            res(source);
        }));
    }

    public static function fromString(id:SourceId, s:String) {
        return fromBytes(id, Buffer.from(s, 'utf-8'));
    }

    public static function fromBytes(id:SourceId, data:Buffer):SourceData {
        return new SourceData(id, data);
    }

    public function hasFile():Bool return this.filePath != null;

    /** Same as `getFilePath` but relative to project, not CWD. */
    public function getFilePathId():SourceId {
        if (filePathId == null) getFilePath();
        return filePathId;
    }

    /** Path to a file for this source, relative to CWD. */
    public function getFilePath():String {
        if (filePath == null) {
            if (source == null) new js.lib.Error("Data without source.");
            filePathId = id.getPutInDir(source.getDirPath());
            filePath = filePathId.toRelPath(source.origin.project);
            Utils.saveBytes(filePath, this.data);
        }
        return filePath;
    }

    inline function get_length() return data.length;

    inline function get_lengthKB() return Math.round(length / 1024);

}
