package whet.cache;

class FileCache extends BaseCache<WhetstoneID, RuntimeFileCacheValue> {

    static inline var dbFile:String = '.whet/cache.json';

    public function new() {
        cache = new Map();
        if (sys.FileSystem.exists(dbFile)) {
            var db:DbJson = haxe.Json.parse(sys.io.File.getContent(dbFile));
            for (key => values in db) cache.set(key, [for (val in values) {
                hash: WhetSourceHash.fromHex(val.hash),
                ctime: val.ctime,
                fileHash: WhetSourceHash.fromHex(val.fileHash),
                filePath: val.filePath
            }]);
        }
    }

    override function key(stone:Whetstone) return stone.id;

    override function value(stone:Whetstone, source:WhetSource):RuntimeFileCacheValue return {
        hash: source.hash,
        ctime: source.ctime,
        fileHash: WhetSourceHash.fromBytes(source.data),
        filePath: source.getFilePath()
    }

    override function source(stone:Whetstone, value:RuntimeFileCacheValue):WhetSource {
        var source = WhetSource.fromFile(stone, value.filePath, value.hash);
        if (source == null || (!stone.ignoreFileHash && !value.fileHash.equals(WhetSourceHash.fromBytes(source.data)))) {
            remove(stone, value);
            flush();
            return null;
        } else return source;
    }

    override function set(stone:Whetstone, source:WhetSource):RuntimeFileCacheValue {
        var val = super.set(stone, source);
        flush();
        return val;
    }

    override function getFilenames(stone:Whetstone):Array<SourceId> {
        var list = cache.get(stone.id);
        if (list != null) return list.map(s -> s.filePath);
        else return null;
    }

    override function remove(stone:Whetstone, value:RuntimeFileCacheValue):Void {
        if (sys.FileSystem.exists(value.filePath) && Lambda.count(cache.get(stone.id), v -> v.filePath == value.filePath) == 1)
            sys.FileSystem.deleteFile(value.filePath);
        super.remove(stone, value);
        flush();
    }

    override function setRecentUseOrder(values:Array<RuntimeFileCacheValue>, value:RuntimeFileCacheValue):Bool {
        var changed = super.setRecentUseOrder(values, value);
        if (changed) flush();
        return changed;
    }

    override function getPathFor(value:RuntimeFileCacheValue):SourceId return value.filePath;

    function flush() {
        var db:DbJson = {};
        for (id => values in cache) db.set(id, [for (val in values) {
            hash: val.hash.toHex(),
            ctime: val.ctime,
            fileHash: val.fileHash.toHex(),
            filePath: val.filePath
        }]);
        Utils.saveContent(dbFile, haxe.Json.stringify(db, null, '\t'));
    }

}

typedef FileCacheValue<H, S> = {

    final hash:H;
    final ctime:Float;
    final fileHash:H;
    final filePath:S;

};

typedef DbJson = DynamicAccess<Array<FileCacheValue<String, String>>>;
typedef RuntimeFileCacheValue = FileCacheValue<WhetSourceHash, SourceId>;
