package whet.cache;

import haxe.DynamicAccess;
import sys.FileSystem;
import whet.WhetSource.WhetSourceData;
import whet.Whetstone.WhetstoneId;

class FileCache extends BaseCache<WhetstoneId, RuntimeFileCacheValue> {

    /**
     * TODO:
     * As an optimization, maybe we could re-use the existing runtime value in `source`,
     * especially if we add multiple formats such as runtime vs in-file, etc.)
     * TODO: test that with caching rules to only have 1 file, we won't generate
     * multiple folders for build files. And ideally if 'hinting' the build filename
     * such as server_standalone.js and replay.js would stay in that same folder?
     * What about clearing that folder before exporting? We don't want to remove logs...
     */
    static inline var dbFileBase:String = '.whet/cache.json';

    final dbFile:String;

    public function new(rootDir:RootDir) {
        super(rootDir, new Map());
        dbFile = rootDir + dbFileBase;
        if (sys.FileSystem.exists(dbFile)) {
            var db:DbJson = haxe.Json.parse(sys.io.File.getContent(dbFile));
            for (key => values in db) cache.set(key, [for (val in values) {
                hash: WhetSourceHash.fromHex(val.hash),
                ctime: val.ctime,
                baseDir: val.baseDir,
                files: [for (file in val.files) {
                    fileHash: WhetSourceHash.fromHex(file.fileHash),
                    filePath: file.filePath,
                    id: file.id
                }]
            }]);
        }
    }

    function key(stone:Stone) return stone.id;

    function value(source:WhetSource):RuntimeFileCacheValue {
        return {
            hash: source.hash,
            ctime: source.ctime,
            baseDir: source.getDirPath(),
            files: [for (data in source.data) {
                fileHash: WhetSourceHash.fromBytes(data.data),
                filePath: data.getFilePathId(),
                id: data.id
            }]
        }
    }

    function source(stone:Stone, value:RuntimeFileCacheValue):WhetSource {
        var data = [];
        for (file in value.files) {
            var path = file.filePath.toRelPath(rootDir);
            var sourceData = WhetSourceData.fromFile(file.id, path, file.filePath);
            if (sourceData == null || (!stone.ignoreFileHash && !sourceData.hash.equals(file.fileHash))) {
                return null;
            } else data.push(sourceData);
        }
        return new WhetSource(data, value.hash, stone, value.ctime);
    }

    override function set(source:WhetSource):RuntimeFileCacheValue {
        var val = super.set(source);
        flush();
        return val;
    }

    function getExistingDirs(stone:Stone):Array<SourceId> {
        var list = cache.get(stone.id);
        if (list != null) return list.map(s -> s.baseDir);
        else return null;
    }

    override function remove(stone:Stone, value:RuntimeFileCacheValue):Void {
        if (FileSystem.exists(value.baseDir.toRelPath(rootDir)) && Lambda.count(cache.get(stone.id), v -> v.baseDir == value.baseDir) == 1)
            Utils.deleteRecursively(value.baseDir.toRelPath(rootDir));
        super.remove(stone, value);
        flush();
    }

    override function setRecentUseOrder(values:Array<RuntimeFileCacheValue>, value:RuntimeFileCacheValue):Bool {
        var changed = super.setRecentUseOrder(values, value);
        if (changed) flush();
        return changed;
    }

    function getDirFor(value:RuntimeFileCacheValue):SourceId return value.baseDir;

    function flush() {
        var db:DbJson = {};
        for (id => values in cache) db.set(id, [for (val in values) {
            hash: val.hash.toHex(),
            ctime: val.ctime,
            ctimePretty: Date.fromTime(val.ctime * 1000).toString(),
            baseDir: val.baseDir.toRelPath('/'),
            files: [for (file in val.files) {
                fileHash: file.fileHash.toHex(),
                filePath: file.filePath.toRelPath('/'),
                id: file.id.toRelPath('/')
            }]
        }]);
        Utils.saveContent(dbFile, haxe.Json.stringify(db, null, '\t'));
    }

}

typedef FileCacheValue<H, S> = {

    final hash:H;
    final ctime:Float;
    @:optional final ctimePretty:String;
    final baseDir:S;
    final files:Array<{
        final id:S;
        final fileHash:H;
        final filePath:S;
    }>;

};

typedef DbJson = DynamicAccess<Array<FileCacheValue<String, String>>>;
typedef RuntimeFileCacheValue = FileCacheValue<WhetSourceHash, SourceId>;
