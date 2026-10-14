package whet.stones;

import whet.Stone.OutputFilter;

/**
 * A JSON-file-backed data stone. Holds parsed JSON in `data`, generates it as a pretty-printed file
 * (the stone id doubles as the output filename), and can `load`/`save` against a path on disk.
 *
 * The bound file is an *input*: generating never writes it. Only `save()` does, and it refuses to
 * overwrite a file someone else changed since it was last read. External edits are picked up on the
 * next access (see `refresh`) unless `data` has unsaved changes.
 *
 * Promoted from AudioDb's private `JsonDb`; backs StoneStore and any data-driven factory.
 */
class JsonDb extends Stone<JsonDbConfig> {

    /** `code` of the error `reload` rejects with when `data` has unsaved changes. */
    public static inline final UNSAVED_CHANGES = 'WHET_UNSAVED_CHANGES';

    /** Parsed JSON contents — whatever `JSON.parse` yields (array or object). */
    public var data:Dynamic;

    /** Project-relative path bound by `load`; null until then. */
    public var path(default, null):Null<String> = null;

    var file:Null<TrackedFile> = null;
    /** Serialised `data` as of the last load/save/reload; drives `isDirty`. */
    var savedJson:Null<String> = null;
    var refreshing:Null<Promise<Bool>> = null;
    /** Set once a disk change was kept out because of unsaved edits, so it's warned about once. */
    var warnedDiskChange = false;
    final reloadListeners:Array<Void->Dynamic> = [];

    override function generate(hash:SourceHash):Promise<Array<SourceData>> {
        return Promise.resolve([SourceData.fromString(this.id, serialize())]);
    }

    /** Not a hash (that would cost the same `stringify` as generating): just the freshness check. */
    override function generateHash():Promise<SourceHash> {
        return refresh().then(_ -> null);
    }

    override function list():Promise<Null<Array<SourceId>>>
        return Promise.resolve([(this.id:SourceId)]);

    override public function getOutputFilter():Null<OutputFilter>
        return { extensions: ['json'] };

    /**
     * Bind `path` (project-relative) and load it. Missing file → warn and fall back to
     * `config.defaultData ?? []`. Doesn't fire `onReload` listeners. Resolves with `this`.
     */
    @:keep public function load(path:String):Promise<JsonDb> {
        this.path = path;
        file = new TrackedFile(cwdPath(path));
        return readFile().then(_ -> this);
    }

    /** True if `data` serialises differently from the last load/save. */
    @:keep public function isDirty():Bool {
        return serialize() != savedJson;
    }

    /** True if the bound file changed on disk since it was last read/written. */
    @:keep public function diskChanged():Promise<Bool> {
        return file == null ? Promise.resolve(false) : file.changed();
    }

    /**
     * Write `data` to the bound file. Rejects with a `TrackedFile.CONFLICT` error if the file changed
     * on disk since it was last read/written, unless `force`. Without unsaved changes it's a no-op, so
     * a hand-formatted file isn't reformatted. Resolves true if bytes were written.
     */
    @:keep public function save(force:Bool = false):Promise<Bool> {
        if (file == null) return Promise.reject(new js.lib.Error('JsonDb "$id" has no bound path; call load() first.'));
        var json = serialize();
        if (!force && json == savedJson) return Promise.resolve(false);
        return file.write(json, force).then(written -> {
            savedJson = json;
            warnedDiskChange = false;
            return written;
        });
    }

    /** Alias of `save`. */
    @:keep public function flush(force:Bool = false):Promise<Bool> {
        return save(force);
    }

    /**
     * Re-read the bound file, replace `data` and fire `onReload` listeners. Rejects with an
     * `UNSAVED_CHANGES` error if `data` has unsaved changes, unless `force`. If parsing or a listener
     * fails, `data` is restored and the disk state forgotten, so the next access tries again.
     */
    @:keep public function reload(force:Bool = false):Promise<JsonDb> {
        if (file == null) return Promise.reject(new js.lib.Error('JsonDb "$id" has no bound path; call load() first.'));
        if (!force && isDirty()) {
            var err = new js.lib.Error('JsonDb "$id" has unsaved changes; save them, or reload with force to discard.');
            (cast err).code = UNSAVED_CHANGES;
            return Promise.reject(err);
        }
        var prevData = data;
        var prevSaved = savedJson;
        return readFile().then(_ -> {
            var all:Array<Promise<Dynamic>> = [for (l in reloadListeners.copy()) Promise.resolve(null).then(_ -> l())];
            return Promise.all(all);
        }).then(_ -> this).catchError(e -> {
            data = prevData;
            savedJson = prevSaved;
            file.forget();
            return Promise.reject(e);
        });
    }

    /**
     * The lazy freshness check, run on every access: if the bound file changed on disk, reload it —
     * unless `data` has unsaved changes, which are kept (and `save` will then report the conflict).
     * Resolves true if it reloaded.
     */
    @:keep public function refresh():Promise<Bool> {
        if (file == null) return Promise.resolve(false);
        if (refreshing != null) return refreshing;
        var p = file.changed().then(changed -> {
            if (!changed) return Promise.resolve(false);
            if (isDirty()) {
                if (!warnedDiskChange) {
                    warnedDiskChange = true;
                    Log.warn('DB file changed on disk, but there are unsaved changes; keeping them.', { path: path });
                }
                return Promise.resolve(false);
            }
            Log.info('DB file changed on disk, reloading.', { path: path });
            return reload().then(_ -> true);
        });
        refreshing = p;
        var clear = () -> if (refreshing == p) refreshing = null;
        p.then(_ -> clear(), _ -> clear());
        return p;
    }

    /** Register `fn` to run after every `reload`. Returns an unsubscribe function. */
    @:keep public function onReload(fn:Void->Dynamic):Void->Void {
        reloadListeners.push(fn);
        return () -> reloadListeners.remove(fn);
    }

    function readFile():Promise<Nothing> {
        return file.read().then(content -> {
            if (content == null) {
                Log.warn('DB file does not exist, using default data.', { path: path });
                // A copy: edits to `data` must not leak into the config's default.
                data = config.defaultData != null ? js.Syntax.code('structuredClone({0})', config.defaultData) : [];
            } else {
                data = haxe.Json.parse(content);
            }
            savedJson = serialize();
            warnedDiskChange = false;
            return null;
        });
    }

    inline function serialize():String return haxe.Json.stringify(data, null, '  ');

    /**
     * Reference `configSchema()` (the convention `StoneRegistry` picks up): a shallow, permissive
     * JSON-Schema fragment describing this stone's editable config. `defaultData` is free-form JSON,
     * so it is described only as "present" without a shape. Intentionally omits
     * `additionalProperties:false` (permissive-by-default convention).
     */
    @:keep public static function configSchema():Dynamic {
        return {
            type: "object",
            properties: {
                defaultData: { description: "Fallback contents when the loaded file is missing." }
            }
        };
    }

}

typedef JsonDbConfig = StoneConfig & {

    /** Fallback contents when `load`'s target file is missing. Defaults to `[]`. */
    var ?defaultData:Dynamic;

}
