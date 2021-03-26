package whet;

import haxe.PosInfos;
import whet.WhetSource;
import whet.cache.Cache;
import whet.cache.CacheManager;

#if !macro
@:autoBuild(whet.Macros.addDocsMeta())
#end
abstract class Whetstone<T:WhetstoneConfig> {

    public var config:T;

    /** If true, hash of a cached file (not `stone.getHash()` but actual file contents) won't be checked. */
    public var ignoreFileHash:Bool = false;

    public var id(get, set):WhetstoneId;
    public var cacheStrategy(get, set):CacheStrategy;
    public var cache(get, set):CacheManager;
    public var project(get, never):WhetProject;

    public final function new(config:T, ?posInfos:PosInfos) {
        this.config = config;
        if (config.project == null) config.project = WhetProject.projects.get(posInfos.fileName);
        if (config.project == null) throw "Did not find a project. Did you create one before making this instance?";
        // TODO ^ Might want to do look for parent dirs? Or do we want to keep that explicit by making the user register the project for other files too?
        initConfig();
        if (config.id == null) config.id = this;
        if (config.cacheStrategy == null) config.cacheStrategy = cache.defaultStrategy;
        config.project.addCommands(this);
    }

    /** Override this to set config defaults. */
    function initConfig():Void { }

    /** Get WhetSource for this stone. Goes through the cache. */
    public final function getSource():WhetSource return cache.getSource(this);

    /** Hash of this stone with its current config. Defaults to hash of generated source. */
    public final function getHash():WhetSourceHash {
        var hash = generateHash();
        return if (hash != null) hash else getSource().hash;
    }

    /**
     * Generates new WhetSource. Used by the cache when needed.
     * Hash passed should be the same as is this stone's current one. Passed in as optimization.
     */
    @:allow(whet.cache) final function generateSource(hash:WhetSourceHash):WhetSource {
        var data = generate(hash);
        if (data != null) {
            if (hash == null) { // Default hash is byte hash of the generated result.
                hash = WhetSourceHash.merge(...data.map(d -> WhetSourceHash.fromBytes(d.data)));
            }
            return new WhetSource(data, hash, this, Sys.time());
        } else return null;
    }

    /**
     * Optionally overridable hash generation as optimization.
     */
    @:allow(whet.cache) function generateHash():WhetSourceHash return null;

    /**
     * Function that actually generates the source. Passed hash is only non-null
     * if `generateHash()` is implemented. It can be used for `CacheManager.getDir` and
     * is passed mainly as optimization.
     */
    private abstract function generate(hash:WhetSourceHash):Array<WhetSourceData>;

    /**
     * Returns a list of sources that this stone generates.
     * Used by Router for finding the correct asset.
     * Default implementation generates the sources to find their ids, but can be overriden
     * to provide optimized implementation that would avoid generating assets we might not need.
     */
    public function list():Array<SourceId> {
        return getSource().data.map(sd -> sd.id);
    }

    /** 
     * Caches this resource under supplied `path` as a single copy.
     * If `path` is not a directory, changes `filename` or `id` of this stone.
     * If `generate` is true, the source is exported right away.
     */
    public function cachePath(path:SourceId, generate:Bool = true):Whetstone<T> {
        config.cacheStrategy = AbsolutePath(path.dir, LimitCountByAge(1));
        if (!path.isDir()) if (Reflect.hasField(config, 'filename')) {
            // Warning: We are setting `SourceId` via reflection. Need to include first slash.
            Reflect.setField(config, 'filename', '/' + path.withExt);
        } else this.id = path.withExt;
        if (generate) getSource();
        return this;
    }

    private inline function get_id() return config.id;

    private inline function set_id(id:WhetstoneId) return config.id = id;

    private inline function get_cacheStrategy() return config.cacheStrategy;

    private inline function set_cacheStrategy(cacheStrategy:CacheStrategy) return config.cacheStrategy = cacheStrategy;

    private inline function get_cache() return config.project.config.cache;

    private inline function set_cache(cache:CacheManager) return config.project.config.cache = cache;

    private inline function get_project() return config.project;

}

@:transitive abstract WhetstoneId(String) from String to String {

    @:from
    public static inline function fromClass(v:Class<Stone>):WhetstoneId
        return Type.getClassName(v).split('.').pop();

    @:from
    public static inline function fromInstance(v:Stone):WhetstoneId
        return fromClass(Type.getClass(v));

}

@:structInit class WhetstoneConfig {

    public var cacheStrategy:CacheStrategy = null;
    public var id:WhetstoneId = null;
    public var project:WhetProject = null;

}

typedef Stone = Whetstone<Dynamic>;

abstract class FileWhetstone<T:WhetstoneConfig> extends Whetstone<T> {

    override function initConfig() {
        if (config.cacheStrategy == null) config.cacheStrategy = cache.defaultFileStrategy;
    }

}
