package whet.cache;

import whet.Whetstone;
import whet.cache.Cache;

class CacheManager {

    public static var defaultStrategy:CacheStrategy = None;

    /** Keep last used 5 for a day and last used 1 indefinitely. */
    public static var defaultFileStrategy:CacheStrategy = InFile(Any([
        LimitCountByLastUse(1),
        All([MaxAge(24 * 60 * 60), LimitCountByLastUse(5)])
    ]), AllOnUse);

    static var memCache:MemoryCache = new MemoryCache();
    @:isVar static var fileCache(get, set):FileCache;

    @:access(whet.Whetstone) static public function getSource(stone:Stone):WhetSource {
        return switch stone.cacheStrategy {
            case None: stone.generateSource(stone.generateHash());
            case InMemory(durability, check): memCache.get(stone, durability, check != null ? check : AllOnUse);
            case InFile(durability, check) | AbsolutePath(_, durability, check):
                fileCache.get(stone, durability, check != null ? check : AllOnUse);
        }
    }

    /** 
     * Get valid path to generate a file in. The path is unique per stone id and fileId.
     * If hash is supplied, and a path was already assigned, the same path is returned, assuring consistency.
     * The path is not reserved. Caching depends on stone's `cacheStrategy` and success of source generation.
     * If `fileId` is a directory, the returned path is unique directory for this stone. Consistent if the stone
     * itself has a cached resource.
     * TODO:
     * Do we need `fileId`? Did we use it anywhere? Maybe stones should just get their one folder to
     * do stuff in...
     * We used this from:
     * WhetSource to save itself to a file, as a way of going through the cache.
     * File cache, as a way of storing a source, through the source, ^ which uses the cache.
     * Stones themselves. Seems like mostly just to get a dir to export to.
     */
    static public function getDir(stone:Stone, ?hash:WhetSourceHash):SourceId {
        var baseDir:SourceId = stone.id + '/';
        if (stone.cacheStrategy.match(None | InMemory(_))) baseDir = baseDir.getPutInDir('.temp/');
        baseDir = baseDir.getPutInDir('.whet/');
        var id = switch stone.cacheStrategy {
            case None: baseDir; // TODO should we clean the folder? But when?
            case InMemory(_): memCache.getUniqueDir(stone, baseDir, hash);
            case InFile(_): fileCache.getUniqueDir(stone, baseDir, hash);
            case AbsolutePath(dir, _): dir;
        }
        return id;
        // TODO clean tmp on start/end of process
    }

    // static public function getFilePath(stone:Whetstone, ?fileId:SourceId, ?hash:WhetSourceHash):SourceId {
    //     if (fileId == null) fileId = stone.defaultFilename;
    //     var baseDir:SourceId = stone.id + '/';
    //     if (stone.cacheStrategy.match(None | InMemory(_))) baseDir = baseDir.getPutInDir('.temp/');
    //     baseDir = baseDir.getPutInDir('.whet/');
    //     var id = fileId.getPutInDir(baseDir);
    //     id = switch stone.cacheStrategy {
    //         case None: id;
    //         case InMemory(_): memCache.getUniqueName(stone, id, hash);
    //         case InFile(_): fileCache.getUniqueName(stone, id, hash);
    //         case SingleFile(filepath, _): filepath;
    //     }
    //     if (fileId.isDir()) { // Wanted a directory, find the root.
    //         var rel = id.relativeTo(baseDir);
    //         if (rel == null) throw "Cached file was not in expected base directory.";
    //         return baseDir + '/' + rel.toRelPath().split('/')[0] + '/'; // First directory after base.
    //     } else return id;
    //     // TODO clean tmp on start/end of process
    // }

    static function get_fileCache():FileCache return fileCache != null ? fileCache : (fileCache = new FileCache());

    static function set_fileCache(v):FileCache return fileCache = v;

}
