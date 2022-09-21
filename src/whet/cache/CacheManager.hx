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
    @:keep public var defaultFileStrategy:CacheStrategy = InFile(Any([
        LimitCountByLastUse(1),
        All([MaxAge(24 * 60 * 60), LimitCountByLastUse(5)])
    ]), AllOnUse);

    public function getSource(stone:AnyStone):Promise<Source> {
        Log.trace('Determining cache status.', { stone: stone, strategy: stone.cacheStrategy.getName() });
        return switch stone.cacheStrategy {
            case None: stone.acquire(() -> stone.finalMaybeHash().then(hash -> stone.generateSource(hash)));
            case InMemory(durability, check): memCache.get(stone, durability, check != null ? check : AllOnUse);
            case InFile(durability, check) | AbsolutePath(_, durability, check):
                fileCache.get(stone, durability, check != null ? check : AllOnUse);
        }
    }

    /**
     * Re-generates source even if the currently cached value is valid.
     */
    @:keep public function refreshSource(stone:AnyStone):Promise<Source> {
        Log.trace('Re-generating cached stone.', { stone: stone });
        return switch stone.cacheStrategy {
            case None: stone.acquire(() -> stone.finalMaybeHash().then(hash -> stone.generateSource(hash)));
            case InMemory(_): memCache.get(stone, MaxAge(-1), SingleOnGet);
            case InFile(_) | AbsolutePath(_):
                fileCache.get(stone, MaxAge(-1), SingleOnGet);
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
            case AbsolutePath(path, _): path.dir;
        }
        return id;
        // TODO clean tmp on start/end of process
    }

}
