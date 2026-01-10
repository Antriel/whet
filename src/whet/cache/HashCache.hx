package whet.cache;

import js.node.Buffer;
import js.node.Fs;

/**
 * In-memory cache for file hashes based on mtime+size.
 * Avoids re-reading and re-hashing file contents when files haven't changed.
 */
class HashCache {

    static var instance:HashCache;

    var cache:Map<String, CachedHash>;

    function new() {
        cache = new Map();
    }

    public static function get():HashCache {
        if (instance == null) instance = new HashCache();
        return instance;
    }

    /**
     * Get hash for file, using cache if mtime/size match.
     * Returns cached hash or computes new one.
     */
    public function getFileHash(path:String):Promise<SourceHash> {
        return new Promise((res, rej) -> {
            Fs.stat(path, (err, stats) -> {
                if (err != null) {
                    rej(err);
                    return;
                }

                var cached = cache.get(path);
                var mtimeMs:Float = (cast stats).mtimeMs;
                if (cached != null && cached.mtime == mtimeMs && cached.size == Std.int(stats.size)) {
                    res(SourceHash.fromHex(cached.hash));
                    return;
                }

                // Cache miss - read and hash
                Fs.readFile(path, (err, data) -> {
                    if (err != null) {
                        rej(err);
                        return;
                    }
                    var hash = SourceHash.fromBytes(data);
                    cache.set(path, {
                        mtime: mtimeMs,
                        size: Std.int(stats.size),
                        hash: hash.toHex()
                    });
                    res(hash);
                });
            });
        });
    }

    /**
     * Get file stats (mtime and size) for a path.
     * Useful for storing alongside cache entries.
     */
    public static function getStats(path:String):Promise<FileStats> {
        return new Promise((res, rej) -> {
            Fs.stat(path, (err, stats) -> {
                if (err != null) rej(err);
                else res({ mtime: (cast stats).mtimeMs, size: Std.int(stats.size) });
            });
        });
    }

}

typedef CachedHash = {
    final mtime:Float;
    final size:Int;
    final hash:String;
}

typedef FileStats = {
    final mtime:Float;
    final size:Int;
}
