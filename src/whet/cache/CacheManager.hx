package whet.cache;

import whet.Whetstone;
import whet.cache.Cache;

@:structInit class CacheManager {

    public final project:WhetProject;
    public var defaultStrategy:CacheStrategy = None;

    /** Keep last used 5 for a day and last used 1 indefinitely. */
    public var defaultFileStrategy:CacheStrategy = InFile(Any([
        LimitCountByLastUse(1),
        All([MaxAge(24 * 60 * 60), LimitCountByLastUse(5)])
    ]), AllOnUse);

    @:isVar var memCache:MemoryCache = null;
    @:isVar var fileCache(get, set):FileCache = null;

    @:access(whet.Whetstone) public function getSource(stone:Stone):WhetSource {
        return switch stone.cacheStrategy {
            case None: stone.generateSource(stone.generateHash());
            case InMemory(durability, check): memCache.get(stone, durability, check != null ? check : AllOnUse);
            case InFile(durability, check) | AbsolutePath(_, durability, check):
                fileCache.get(stone, durability, check != null ? check : AllOnUse);
        }
    }

    /** 
     * Get valid directory to generate files in. The path is unique per stone based on caching rules.
     * If hash is supplied, and a path was already assigned, the same path is returned, assuring consistency.
     * The path is not reserved. Caching depends on stone's `cacheStrategy` and success of source generation.
     */
    public function getDir(stone:Stone, ?hash:WhetSourceHash):SourceId {
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

    function get_fileCache():FileCache return fileCache != null ? fileCache : (fileCache = new FileCache(project));

    function set_fileCache(v):FileCache return fileCache = v;

    function get_memoryCache():MemoryCache return memCache != null ? memCache : (memCache = new MemoryCache(project));

    function set_memoryCache(v):MemoryCache return memCache = v;

}
