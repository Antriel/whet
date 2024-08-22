package whet;

import js.node.Path;
import whet.Source;
import whet.magic.MaybeArray.makeArray;
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

    var lockQueue:Array<{
        run:Void->Promise<Any>,
        res:Dynamic->Void,
        rej:Dynamic->Void
    }> = [];
    var locked:Bool = false;

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
        addCommands();
    }

    /** Override this to set config defaults. */
    function initConfig():Void { }

    /** Override this to register commands via `this.project.addCommand`. */
    function addCommands():Void { }

    /**
     * Locks this stone for generating. Used to prevent parallel generation of the same sources.
     */
    @:allow(whet) final function acquire<T>(run:Void->Promise<T>):Promise<T> {
        Log.trace('Acquiring lock on a stone.', { stone: this });
        if (locked) {
            Log.debug('Stone is locked, waiting.', { stone: this });
            var deferredRes:T->Void;
            var deferredRej:Dynamic;
            var deferred = new Promise((res, rej) -> {
                deferredRes = res;
                deferredRej = rej;
            });
            lockQueue.push({
                run: run,
                res: deferredRes,
                rej: deferredRej
            });
            return deferred;
        } else {
            locked = true;
            function runNext() {
                if (lockQueue.length > 0) {
                    Log.debug('Running next queued-up lock acquire function.', { stone: this });
                    var queued = lockQueue.shift();
                    queued.run().then(queued.res).catchError(queued.rej).finally(runNext);
                } else {
                    locked = false;
                    Log.trace('No function in lock queue. Stone is now unlocked.', { stone: this });
                }
            }
            return run().finally(runNext);
        }
    }

    /** 
     * **Do not override.**
     * Get Source for this stone. Goes through the cache.
     */
    public final function getSource():Promise<Source> {
        Log.debug('Getting source.', { stone: this });
        return cache.getSource(this);
    }

    /** 
     * **Do not override.**
     * Hash of this stone with its current config. Defaults to hash of generated source.
     * Hashes of dependency stones (see `config.dependencies`) will be added to the hash.
     */
    public final function getHash():Promise<SourceHash> {
        Log.debug('Generating hash.', { stone: this });
        return finalMaybeHash().then(hash -> {
            if (hash != null) hash else cast getSource().then(s -> s.hash);
        });
    }

    /**
     * **Do not override.**
     * Should only be used internally.
     * Used to finalize a hash in `getHash` or in `generateSource` if `getHash` isn't implemented.
     * Also used by the cache for the same purpose.
     */
    final function finalizeHash(hash:SourceHash):Promise<Null<SourceHash>> {
        return if (hash == null || config.dependencies == null) Promise.resolve(hash)
        else Promise.all([for (stone in makeArray(config.dependencies)) stone.getHash()])
            .then((hashes:Array<SourceHash>) -> hash.add(SourceHash.merge(...hashes)));
    }

    /**
     * **Do not override.**
     * Generates new Source. Used by the cache when needed.
     * Hash passed should be the same as is this stone's current one. Passed in as optimization.
     */
    @:allow(whet.cache) final function generateSource(hash:Null<SourceHash>):Promise<Source> {
        if (!this.locked) throw new js.lib.Error("Acquire a lock before generating.");
        Log.debug('Generating source.', { stone: this, hash: hash });
        var init = if (config.dependencies != null) Promise.all([
            // Make sure dependencies are up to date.
            for (stone in makeArray(config.dependencies)) stone.getSource()
        ]) else Promise.resolve(null);
        return init.then(_ -> {
            var dataPromise = generate(hash);
            return if (dataPromise != null) dataPromise.then(data -> {
                // If we have a hash, it's already finalized. Otherwise default hash is
                // byte hash of the generated result, with the dependencies' hash added to it.
                var finalHash = if (hash != null) Promise.resolve(hash)
                else finalizeHash(SourceHash.merge(...data.map(d -> SourceHash.fromBytes(d.data))));
                return finalHash.then(hash -> new Source(data, hash, this, Sys.time()));
            }) else null;
        }).catchError(e -> handleError(e).then(data -> {
            Log.warn('Error happened and was handled by `handleError`.', { stone: this, error: e });
            // Use file hash even if might have explicit hash, as this is a fallback value.
            final hash = SourceHash.merge(...data.map(d -> SourceHash.fromBytes(d.data)));
            new Source(data, hash, this, Sys.time());
        }));
    }

    /**
     * To be used externally (i.e. `myStone.handleError = err => ...`) for providing a fallback value
     * where it might make sense.
     * @param err Any error that might have happened during `generateSource`.
     */
    public dynamic function handleError(err:Dynamic):Promise<Array<SourceData>> {
        Log.error("Error while generating.", { stone: this, err: err });
        return Promise.reject(err); // Don't handle anything by default.
    }

    /**
     * Optionally overridable hash generation as optimization.
     * Do not use directly. Use `getHash` instead.
     */
    private function generateHash():Promise<SourceHash> return Promise.resolve(null);

    /**
     * **Do not override.**
     * Used by cache. Returns either null, or result of `generateHash` finalized by adding 
     * dependencies.
     */
    @:allow(whet.cache) function finalMaybeHash():Promise<Null<SourceHash>>
        return generateHash().then(hash -> finalizeHash(hash));

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
     * @param path
     * If `path` is a directory, stores the file(s) under that path, using their standard names.
     * If `path` is a file and this stone generates only single data source, stores it under the supplied path.
     * @param generate If true (default), the source is exported right away. Will not re-save the file, if it already
     * exists under the same path and hash.
     */
    @:keep public function setAbsolutePath(path:String, generate:Bool = true):Promise<Source> {
        cacheStrategy = AbsolutePath(path, LimitCountByAge(1));
        return if (generate) getSource() else Promise.resolve(null);
    }

    /**
     * Stores this resource in the supplied path, without changing cache strategy.
     * @param path Path relative to this stone's project.
     * Can be a directory or a file path (only if this resource generates single source).
     */
    @:keep public function exportTo(path:SourceId):Promise<Nothing> {
        Log.info('Exporting file(s).', { path: path, stone: this });
        final isDir = path.isDir();
        return getSource().then(src -> {
            if (src.data.length > 1 && !isDir)
                throw new js.lib.Error('Path is not a directory for multiple source export.');
            cast Promise.all([for (data in src.data) {
                var id = isDir ? data.id.getPutInDir(path) : path;
                Utils.saveBytes(id.toCwdPath(project), data.data);
            }]);
        });
    }

    /**
     * Convenient function to get CWD-relative path from project-relative one.
     * Useful for pure JS stones.
     */
    @:keep public function cwdPath(path:SourceId):String {
        return path.toCwdPath(project);
    }

    private inline function get_cache() return project.cache;

    @:keep public function toString():String {
        return '$id:${getTypeName(this)}';
    }

}

typedef StoneConfig = {

    /**
     * Defaults to `project.cache.defaultStrategy`.
     * **Do not modify after initialization – it is ignored.**
     * After stone is initialized, change `stone.cacheStrategy` directly.
     */
    var ?cacheStrategy:CacheStrategy;

    /** Defaults to the Stone's class name. */
    var ?id:StoneIdType;

    /** Defaults to the last instanced project. */
    var ?project:Project;

    /**
     * Registers another stone(s) as dependency of this one. Useful for external processes
     * that use a source of some stone, but don't go via Whet to get it.
     * Use with combination of `setAbsolutePath` on the dependency, so that the external process
     * can rely on a fixed path.
     * Will make sure the cached file is up to date when generating this stone.
     * Hash of the dependency is automatically combined with hash generated by this stone. There's no
     * need to add it manually.
     * Do not create cyclic dependencies!
     */
    var ?dependencies:whet.magic.MaybeArray<AnyStone>;

    // Note: See `SourceHash.fromConfig` when adding fields here.

}

typedef AnyStone = Stone<Dynamic>;
