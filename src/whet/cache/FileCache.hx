package whet.cache;

import haxe.DynamicAccess;
import js.node.Fs;
import whet.Source.SourceData;

class FileCache extends BaseCache<String, RuntimeFileCacheValue> {

    /**
     * TODO:
     * As an optimization, maybe we could re-use the existing runtime value in `source`,
     * especially if we add multiple formats such as runtime vs in-file, etc.)
     * TODO: test that with caching rules to only have 1 file, we won't generate
     * multiple folders for build files. And ideally if 'hinting' the build filename
     * such as server_standalone.js and replay.js would stay in that same folder?
     * What about clearing that folder before exporting? We don't want to remove logs...
     */
    static inline var dbFileBase:SourceId = '.whet/cache.json';

    final dbFile:String;
    var flushQueued:Bool = false;

    public function new(rootDir:RootDir) {
        super(rootDir, new Map());
        dbFile = dbFileBase.toCwdPath(rootDir);
        try {
            var db:DbJson = haxe.Json.parse(Fs.readFileSync(dbFile, { encoding: 'utf-8' }));
            for (key => values in db) cache.set(key, [for (val in values) {
                hash: SourceHash.fromHex(val.hash),
                ctime: val.ctime,
                baseDir: val.baseDir,
                files: [for (file in val.files) {
                    fileHash: SourceHash.fromHex(file.fileHash),
                    filePath: file.filePath,
                    id: file.id,
                    mtime: file.mtime,
                    size: file.size
                }]
            }]);
        } catch (_) { }
    }

    function key(stone:AnyStone) return stone.id;

    function value(source:Source):Promise<RuntimeFileCacheValue> {
        var idOverride:SourceId = switch source.origin.cacheStrategy {
            case AbsolutePath(path, _) if (source.data.length == 1): path.withExt;
            case _: null;
        }
        return Promise.all([for (data in source.data) data.getFilePathId(idOverride).then(filePath -> {
            var cwdPath = filePath.toCwdPath(rootDir);
            HashCache.getStats(cwdPath).then(stats -> {
                fileHash: SourceHash.fromBytes(data.data),
                filePath: filePath,
                id: data.id,
                mtime: stats.mtime,
                size: stats.size
            });
        })]).then(files -> {
            hash: source.hash,
            ctime: source.ctime,
            baseDir: source.getDirPath(),
            ctimePretty: null, // For some reason Haxe doesn't like this missing.
            files: cast files
        });
    }

    function source(stone:AnyStone, value:RuntimeFileCacheValue):Promise<Source> {
        switch stone.cacheStrategy {
            case AbsolutePath(path, _):
                var invalidPath = if (value.files.length == 1 && !path.isDir()) {
                    value.files[0].filePath != path;
                } else {
                    value.baseDir != path.dir;
                }
                if (invalidPath) return Promise.resolve(null);
            case _:
        }
        return Promise.all([for (file in value.files) new Promise(function(res, rej) {
            var path = file.filePath.toCwdPath(rootDir);
            // First check mtime+size (fast stat-based validation)
            Fs.stat(path, (statErr, stats) -> {
                if (statErr != null) {
                    if (statErr is js.lib.Error && (statErr:Dynamic).code == 'ENOENT') rej('Invalid.');
                    else rej(statErr);
                    return;
                }

                var mtimeMs:Float = (cast stats).mtimeMs;
                var mtimeMatch = file.mtime != null && mtimeMs == file.mtime
                    && Std.int(stats.size) == file.size;

                if (mtimeMatch && !stone.ignoreFileHash) {
                    // Mtime matches - trust cached hash, just read data without rehashing
                    SourceData.fromFileSkipHash(file.id, path, file.filePath, file.fileHash)
                        .then(res, rej);
                } else {
                    // Mtime changed or no mtime stored - fall back to hash validation
                    SourceData.fromFile(file.id, path, file.filePath).then(sourceData -> {
                        if (sourceData == null
                            || (!stone.ignoreFileHash && !sourceData.hash.equals(file.fileHash))) {
                            rej('Invalid.');
                        } else res(sourceData);
                    }, err -> if (err is js.lib.Error && (err:Dynamic).code == 'ENOENT') rej('Invalid.');
                        else rej(err)
                    );
                }
            });
        })]).then(
            data -> new Source(cast data, value.hash, stone, value.ctime),
            rejected -> rejected == 'Invalid.' ? null : { js.Syntax.code('throw {0}', rejected); null; }
        );
    }

    override function set(source:Source):Promise<RuntimeFileCacheValue> {
        return super.set(source).then(vals -> {
            flush();
            vals;
        });
    }

    function getExistingDirs(stone:AnyStone):Array<SourceId> {
        var list = cache.get(stone.id);
        if (list != null) return list.map(s -> s.baseDir);
        else return null;
    }

    override function remove(stone:AnyStone, value:RuntimeFileCacheValue):Promise<Nothing> {
        Log.debug('Removing stone from file cache.', { stone: stone, valueHash: value.hash.toHex() });
        // Only remove if there's nothing else in the cache with the same path, as a precaution against
        // invalid cache state.
        final isAlone = Lambda.count(cache.get(stone.id), v -> v.baseDir == value.baseDir) == 1;
        return super.remove(stone, value).then(_ -> {
            flush();
            if (!isAlone) Promise.resolve(null) else
                Promise.all([for (file in value.files) new Promise((res, rej) -> {
                    Log.debug('Deleting file.', { path: file.filePath.toCwdPath(rootDir) });
                    Fs.unlink(file.filePath.toCwdPath(rootDir), err -> {
                        if (err != null) Log.error("Error deleting file.", { file: file, error: err });
                        res(null);
                    });
                })]);
        }).then(_ -> new Promise((res, rej) -> Fs.readdir(value.baseDir.toCwdPath(rootDir), (err, files) -> {
            if (err != null) {
                Log.error("Error reading directory", { dir: value.baseDir.toCwdPath(rootDir), error: err });
                res(null);
            } else if (files.length == 0)
                Fs.rmdir(value.baseDir.toCwdPath(rootDir), err -> {
                    if (err != null) Log.error("Error removing directory.", { dir: value.baseDir.toCwdPath(rootDir), error: err });
                    res(null);
                })
            else res(null);
        })));
    }

    override function setRecentUseOrder(values:Array<RuntimeFileCacheValue>, value:RuntimeFileCacheValue):Bool {
        var changed = super.setRecentUseOrder(values, value);
        if (changed) flush();
        return changed;
    }

    function getDirFor(value:RuntimeFileCacheValue):SourceId return value.baseDir;

    function flush() {
        if (flushQueued) return;
        flushQueued = true;
        js.Node.setTimeout(function() {
            flushQueued = false;
            var db:DbJson = {};
            for (id => values in cache) db.set(id, [for (val in values) {
                hash: val.hash.toHex(),
                ctime: val.ctime,
                ctimePretty: Date.fromTime(val.ctime * 1000).toString(),
                baseDir: val.baseDir.toCwdPath('./'),
                files: [for (file in val.files) {
                    fileHash: file.fileHash.toHex(),
                    filePath: file.filePath.toCwdPath('./'),
                    id: file.id.toCwdPath('./'),
                    mtime: file.mtime,
                    size: file.size,
                }]
            }]);
            Utils.saveContent(dbFile, haxe.Json.stringify(db, null, '\t')).then(
                _ -> Log.trace('FileCache DB saved.'),
                err -> Log.error('FileCache DB save error.', err)
            );
        }, 100);
    }

}

typedef FileCacheValue<H, S> = {

    final hash:H;
    final ctime:Float;
    final ?ctimePretty:String;
    final baseDir:S;
    final files:Array<{
        final id:S;
        final fileHash:H;
        final filePath:S;
        final ?mtime:Float;
        final ?size:Int;
    }>;

};

typedef DbJson = DynamicAccess<Array<FileCacheValue<String, String>>>;
typedef RuntimeFileCacheValue = FileCacheValue<SourceHash, SourceId>;
