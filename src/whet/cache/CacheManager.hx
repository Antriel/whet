package whet.cache;

class CacheManager {

    public final project:Project;
    public var defaultStrategy:CacheStrategy = None;

    final memCache:MemoryCache = null;
    final fileCache:FileCache = null;

    public function new(project:Project) {
        this.project = project;
        fileCache = new FileCache(project);
        memCache = new MemoryCache(project);
    }

    /** Keep last used 5 for a day and last used 1 indefinitely. */
    public var defaultFileStrategy:CacheStrategy = InFile(Any([
        LimitCountByLastUse(1),
        All([MaxAge(24 * 60 * 60), LimitCountByLastUse(5)])
    ]), AllOnUse);

    @:access(whet.Stone) public function getSource(stone:AnyStone):Promise<Source> {
        Log.trace('Looking for cached value.', { stone: stone, strategy: stone.cacheStrategy.getName() });
        return switch stone.cacheStrategy {
            case None: stone.generateHash().then(hash -> stone.generateSource(hash));
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
    public function getDir(stone:AnyStone, ?hash:SourceHash):SourceId {
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

}
