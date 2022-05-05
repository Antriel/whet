package whet;

import js.node.Path;
import whet.Source;
import whet.magic.StoneId.StoneIdType;
import whet.magic.StoneId.getTypeName;
import whet.magic.StoneId.makeStoneId;

@:expose
abstract class Stone<T:StoneConfig> {

    public var config:T;

    /** If true, hash of a cached file (not `stone.getHash()` but actual file contents) won't be checked. */
    public var ignoreFileHash:Bool = false;

    public var id(default, null):String;
    public var cacheStrategy:CacheStrategy;
    public var cache(get, never):CacheManager;
    public final project:Project;

    public final function new(config:T) {
        Log.trace('Instantiating new Stone.', { type: getTypeName(this) });
        if (config == null) throw new js.lib.Error('Config must be supplied.');
        this.config = config;
        project = if (config.project != null) config.project else Project.projects[Project.projects.length - 1];
        if (project == null) throw new js.lib.Error("Did not find a project. Create one before creating stones.");
        project.stones.push(this);
        initConfig();
        id = if (config.id != null) makeStoneId(config.id) else makeStoneId(this);
        cacheStrategy = config.cacheStrategy == null ? cache.defaultStrategy : config.cacheStrategy;
        for (cmd in getCommands()) project.addCommand(cmd, this);
    }

    /** Override this to set config defaults. */
    function initConfig():Void { }

    /** Override this to register commands. */
    function getCommands():Array<commander.Command> return [];

    /** 
     * **Do not override.**
     * Get Source for this stone. Goes through the cache.
     */
    public final function getSource():Promise<Source> {
        Log.debug('Getting source.', { stone: this });
        return cache.getSource(this);
    }

    /** Hash of this stone with its current config. Defaults to hash of generated source. */
    public final function getHash():Promise<SourceHash> {
        Log.debug('Generating hash.', { stone: this });
        return generateHash().then(hash -> if (hash != null) hash else cast getSource().then(s -> s.hash));
    }

    /**
     * **Do not override.**
     * Generates new Source. Used by the cache when needed.
     * Hash passed should be the same as is this stone's current one. Passed in as optimization.
     */
    @:allow(whet.cache) final function generateSource(hash:SourceHash):Promise<Source> {
        Log.debug('Generating source.', { stone: this, hash: hash });
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
    @:allow(whet.cache) function generateHash():Promise<SourceHash> return Promise.resolve(null);

    /**
     * Abstract method.
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
     * If `path` is a directory, stores the file(s) under that path, using their standard names.
     * If `path` is a file and this stone generates only single data source, stores it under the supplied path.
     * If `generate` is true, the source is exported right away.
     */
    @:keep public function setAbsolutePath(path:String, generate:Bool = true):Promise<Source> {
        cacheStrategy = AbsolutePath(path, LimitCountByAge(1));
        return if (generate) getSource() else Promise.resolve(null);
    }

    /**
     * Convenient function to get CWD-relative path from project-relative one.
     * Useful for pure JS stones.
     */
    @:keep public function cwdPath(path:String):String {
        // return (path:SourceId).toRelPath(project);
        return Path.join('./', cast project.rootDir, path);
    }

    private inline function get_cache() return project.cache;

    @:keep public function toString():String {
        return '$id:${getTypeName(this))}';
    }

}

typedef StoneConfig = {

    var ?cacheStrategy:CacheStrategy;

    /** Defaults to the Stone's class name. */
    var ?id:StoneIdType;

    /** Defaults to the last instanced project. */
    var ?project:Project;

}

typedef AnyStone = Stone<Dynamic>;
