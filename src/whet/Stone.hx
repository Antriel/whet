package whet;

import whet.Source;
import whet.magic.StoneId.StoneIdType;
import whet.magic.StoneId.makeStoneId;

// import whet.cache.Cache;
// import whet.cache.CacheManager;
#if !macro
@:autoBuild(whet.Macros.addDocsMeta())
#end
abstract class Stone<T:StoneConfig> {

    public var config:T;

    /** If true, hash of a cached file (not `stone.getHash()` but actual file contents) won't be checked. */
    public var ignoreFileHash:Bool = false;

    public final id:String;
    // public var cacheStrategy(get, set):CacheStrategy;
    // public var cache(get, set):CacheManager;
    public final project:Project;

    public final function new(config:T) {
        if (config == null) throw new js.lib.Error('Config must be supplied.');
        this.config = config;
        initConfig();
        id = if (config.id != null) makeStoneId(config.id) else makeStoneId(this);
        project = if (config.project != null) config.project else Project.projects[Project.projects.length - 1];
        if (project == null) throw new js.lib.Error("Did not find a project. Create one before creating stones.");
        // config.project.addCommands(this);
    }

    /** Override this to set config defaults. */
    function initConfig():Void {
        // if (config.cacheStrategy == null) config.cacheStrategy = cache.defaultStrategy;
    }

    /** Get Source for this stone. Goes through the cache. */
    // public final function getSource():Promise<Source> cache.getSource(this);
    public final function getSource():Promise<Source> return generate(null).then(ss -> new Source(ss, null, this, null));

    /** Hash of this stone with its current config. Defaults to hash of generated source. */
    public final function getHash():Promise<SourceHash> {
        var hash = generateHash();
        return if (hash != null) hash else getSource().then(s -> s.hash);
    }

    /**
     * Generates new Source. Used by the cache when needed.
     * Hash passed should be the same as is this stone's current one. Passed in as optimization.
     */
    @:allow(whet.cache) final function generateSource(hash:SourceHash):Promise<Source> {
        var dataPromise = generate(hash);
        return if (dataPromise != null) dataPromise.then(data -> {
            if (hash == null) { // Default hash is byte hash of the generated result.
                hash = SourceHash.merge(...data.map(d -> SourceHash.fromBytes(d.data)));
            }
            return new Source(data, hash, this, Sys.time());
        }) else return null;
    }

    /**
     * Optionally overridable hash generation as optimization.
     */
    @:allow(whet.cache) function generateHash():Promise<SourceHash> return null;

    /**
     * Function that actually generates the source. Passed hash is only non-null
     * if `generateHash()` is implemented. It can be used for `CacheManager.getDir` and
     * is passed mainly as optimization.
     */
    private abstract function generate(hash:SourceHash):Promise<Array<SourceData>>;

    /**
     * Returns a list of sources that this stone generates.
     * Used by Router for finding the correct asset.
     * Default implementation generates the sources to find their ids, but can be overriden
     * to provide optimized implementation that would avoid generating assets we might not need.
     */
    public function list():Promise<Array<SourceId>> {
        return getSource().then(source -> source.data.map(sd -> sd.id));
    }

    /** 
     * Caches this resource under supplied `path` as a single copy.
     * If `path` is not a directory, changes `filename` or `id` of this stone.
     * If `generate` is true, the source is exported right away.
     */
    // public function cachePath(path:SourceId, generate:Bool = true):Stone<T> {
    //     config.cacheStrategy = AbsolutePath(path.dir, LimitCountByAge(1));
    //     if (!path.isDir()) if (Reflect.hasField(config, 'filename')) {
    //         // Warning: We are setting `SourceId` via reflection. Need to include first slash.
    //         Reflect.setField(config, 'filename', '/' + path.withExt);
    //     } else this.id = path.withExt;
    //     if (generate) getSource();
    //     return this;
    // }
    // private inline function get_id() return makeStoneId(config.id);
    // private inline function set_id(id:StoneIdType) return config.id = id;
    // private inline function get_cacheStrategy() return config.cacheStrategy;
    // private inline function set_cacheStrategy(cacheStrategy:CacheStrategy) return config.cacheStrategy = cacheStrategy;
    // private inline function get_cache() return config.project.config.cache;
    // private inline function set_cache(cache:CacheManager) return config.project.config.cache = cache;

    private inline function get_project() return config.project;

}

typedef StoneConfig = {

    // public var cacheStrategy:CacheStrategy = null;

    /** Defaults to the Stone's class name. */
    var ?id:StoneIdType;

    /** Defaults to the last instanced project. */
    var ?project:Project;

}

typedef AnyStone = Stone<Dynamic>;
