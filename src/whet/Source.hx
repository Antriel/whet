package whet;

import js.node.Buffer;
import js.node.Fs;
import whet.Stone;
import whet.magic.MinimatchType;

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

    public function tryDirPath():Null<SourceId> return dirPath;

    /**
     * Returns a directory path where this source data is stored.
     * If none exists yet, generates a usable path through cache.
     */
    public function getDirPath():SourceId {
        if (dirPath == null)
            dirPath = origin.cache.getDir(origin, hash);
        return dirPath;
    }

    /**
     * Returns first result if `pattern` is null, or first one it matches.
     */
    public function get(?pattern:MinimatchType):SourceData {
        return if (pattern == null) data[0] else {
            final filter = makeMinimatch(pattern);
            Lambda.find(data, entry -> filter.match(entry.id));
        }
    }

}

class SourceData {

    public final data:Buffer;

    /** Name relative to the stone that generated it. */
    public final id:SourceId;

    public final hash:SourceHash;
    public var length(get, never):Int;
    public var lengthKB(get, never):Int;
    @:allow(whet.Source) public var source(default, null):Source;

    var filePathId:SourceId = null; // Relative to project.
    var filePath:String = null; // CWD relative path.

    private function new(id, data, ?knownHash:SourceHash) {
        this.data = data;
        this.id = id;
        this.hash = knownHash != null ? knownHash : SourceHash.fromBytes(data);
    }

    /**
     * @param id Path id relative to stone that generates it.
     * @param path Actual path relative to CWD.
     * @param pathId Path Id relative to project.
     * @return Promise<SourceData>
     */
    public static function fromFile(id:String, path:String, pathId:String):Promise<SourceData> {
        return new Promise((res, rej) -> Fs.readFile(path, (err, buffer) -> {
            if (err != null) {
                Log.error("File does not exist.", { id: id, path: path, error: err });
                rej(err);
            } else {
                var source = fromBytes(id, buffer);
                source.filePath = path;
                source.filePathId = pathId;
                res(source);
            }
        }));
    }

    /**
     * Read file without recomputing hash. Used when mtime validation passed.
     * @param id Path id relative to stone that generates it.
     * @param path Actual path relative to CWD.
     * @param pathId Path Id relative to project.
     * @param knownHash The hash from cache (already validated via mtime).
     */
    public static function fromFileSkipHash(id:String, path:String, pathId:String, knownHash:SourceHash):Promise<SourceData> {
        return new Promise((res, rej) -> Fs.readFile(path, (err, buffer) -> {
            if (err != null) {
                Log.error("File does not exist.", { id: id, path: path, error: err });
                rej(err);
            } else {
                var source = new SourceData(id, buffer, knownHash);
                source.filePath = path;
                source.filePathId = pathId;
                res(source);
            }
        }));
    }

    public static function fromString(id:String, s:String) {
        return fromBytes(id, Buffer.from(s, 'utf-8'));
    }

    public static function fromBytes(id:String, data:Buffer):SourceData {
        return new SourceData(id, data);
    }

    public function hasFile():Bool return this.filePath != null;

    /** Same as `getFilePath` but relative to project, not CWD. */
    public function getFilePathId(idOverride:SourceId = null):Promise<SourceId> {
        return if (filePathId == null) getFilePath(idOverride).then(_ -> filePathId);
        else Promise.resolve(filePathId);
    }

    /**
     * Path to a file for this source, relative to CWD.
     * Useful for working with sources outside of Whet ecosystem.
     * @param [idOverride] Use to change the name/directory of the file. Ignored if source already has a filepath.
     */
    public function getFilePath(idOverride:SourceId = null):Promise<String> {
        return if (filePath == null) {
            if (source == null) new js.lib.Error("Data without source.");
            var dir = source.getDirPath();
            // Only use `idOverride` fully if it's not a directory,
            // otherwise it's already handled in `getDirPath`, or rather `CacheManager.getDir`.
            var name = if (idOverride != null && !idOverride.isDir()) idOverride else id;
            filePathId = name.getPutInDir(dir);
            filePath = filePathId.toCwdPath(source.origin.project);
            Utils.saveBytes(filePath, this.data).then(_ -> filePath);
        } else Promise.resolve(filePath);
    }

    inline function get_length() return data.length;

    inline function get_lengthKB() return Math.round(length / 1024);

}

