package whet;

import haxe.DynamicAccess;
import whet.Whetstone;

class CacheManager {

    public static var defaultStrategy:CacheStrategy = None;

    /** Keep last used 5 for a day and last used 1 indefinitely. */
    public static var defaultFileStrategy:CacheStrategy = InFile(Any([
        LimitCountByLastUse(1),
        All([MaxAge(24 * 60 * 60), LimitCountByLastUse(5)])
    ]), AllOnUse);

    static var memCache:MemoryCache = new MemoryCache();
    @:isVar static var fileCache(get, set):FileCache;

    @:access(whet.Whetstone) static public function getSource(stone:Whetstone):WhetSource {
        return switch stone.cacheStrategy {
            case None: stone.generateData(); // TODO needs change.
            case InMemory(durability, check): memCache.get(stone, durability, check != null ? check : AllOnUse);
            case InFile(durability, check): fileCache.get(stone, durability, check != null ? check : AllOnUse);
            case SingleFile(_, durability): fileCache.get(stone, All([LimitCountByAge(1), durability]), AllOnUse);
        }
    }

    /** 
     * Get valid path to generate a file in. The path is unique per stone id and fileId.
     * If hash is supplied, and a path was already assigned, the same path is returned, assuring consistency.
     * The path is not reserved. Caching depends on stone's `cacheStrategy` and success of source generation.
     * If `fileId` is a directory, the returned path is unique directory for this stone. Consistent if the stone
     * itself has a cached resource.
     */
    static public function getFilePath(stone:Whetstone, ?fileId:SourceId, ?hash:WhetSourceHash):SourceId {
        if (fileId == null) fileId = stone.defaultFilename;
        var baseDir:SourceId = stone.id + '/';
        if (stone.cacheStrategy.match(None | InMemory(_))) baseDir = baseDir.getPutInDir('.temp/');
        baseDir = baseDir.getPutInDir('.whet/');
        var id = fileId.getPutInDir(baseDir);
        id = switch stone.cacheStrategy {
            case None: id;
            case InMemory(_): memCache.getUniqueName(stone, id, hash);
            case InFile(_): fileCache.getUniqueName(stone, id, hash);
            case SingleFile(filepath, _): filepath;
        }
        if (fileId.isDir()) { // Wanted a directory, find the root.
            var rel = id.relativeTo(baseDir);
            if (rel == null) throw "Cached file was not in expected base directory.";
            return baseDir + '/' + rel.toRelPath().split('/')[0] + '/'; // First directory after base.
        } else return id;
        // TODO clean tmp on start/end of process
    }

    static function get_fileCache():FileCache return fileCache != null ? fileCache : (fileCache = new FileCache());

    static function set_fileCache(v):FileCache return fileCache = v;

}
