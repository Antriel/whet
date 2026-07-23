package whet.stones;

import whet.Log;
import whet.Stone.AnyStone;
import whet.stones.StoneFactory;
import whet.stones.StoneRegistry.BuiltEntry;

using js.lib.HaxeIterator;

/**
 * A `StoneFactory` whose entries are generic JSON stone declarations, backed by a `JsonDb` file
 * (e.g. `assets/stone-store.json`). Each entry names a `StoneRegistry` type and a JSON config whose
 * `$stone`/`$router` references are revived into live stones — so one JSON file can describe a whole
 * data-driven stone graph. Preview/revert is inherited from `StoneFactory` (live editing of an
 * unsaved config), extended here with a reference-consistency cascade.
 *
 * File format (a JSON array; see the epic/bean for the annotated form):
 * ```jsonc
 * [
 *   { "id": "sharpstone-ui", "type": "SharpStone",
 *     "config": { "pngs": { "$router": [["/", "assets/ui/", "**\/*.png"]] } },
 *     "mount": "ui/" }
 * ]
 * ```
 *
 * Script usage:
 * ```js
 * const store = await new StoneStore({ id: 'assets-store' }).load('assets/stone-store.json');
 * bundle.route([['/', store]]); // single mount point; the store IS a Router
 * ```
 * A script must reference the store (or entry outputs via routes), never capture inner store-created
 * stone instances — recreate-on-sync invalidates captured instances by design.
 */
class StoneStore extends StoneFactory<FlatEntryData, BuiltEntry> {

    /** The JSON-file-backed data stone holding the entry array; also served via the base route. */
    public var db:JsonDb;

    /** When true, a removed entry's stones have their caches cleared on sync (doc 01 §4). */
    public final clearCacheOnRemove:Bool;

    /** The owning project, resolved via the db stone (the store itself is a Router, not a Stone). */
    public var project(get, never):Project;

    inline function get_project():Project return db.project;

    /** Keys created/updated during the current sync pass — drives the dependent-update cascade. */
    final touchedKeys:js.lib.Set<String> = new js.lib.Set();

    public function new(?config:StoneStoreConfig) {
        super();
        if (config == null) config = {};
        var dbId:String = config.dbId != null ? config.dbId : 'stone-store.json';
        db = new JsonDb({ id: dbId, project: config.project });
        clearCacheOnRemove = config.clearCacheOnRemove == true;
    }

    /** Load the DB file (project-relative), sync entries, and resolve with `this`. */
    @:keep public function load(path:String):Promise<StoneStore> {
        return db.load(path).then(_ -> syncEntries()).then(_ -> this);
    }

    /** Persist the DB's canonical data back to its file. */
    @:keep public function flushDb():Promise<Source> {
        return db.flush();
    }

    // --- StoneFactory overrides ---

    override function addBaseRoutes():Void {
        var baseRoute:Array<Dynamic> = [db.id, db];
        route((cast [baseRoute]:whet.magic.RoutePathType));
    }

    /**
     * Validate + expand + topo-sort `db.data`, then sync. Validation is all-or-nothing: on any
     * structural problem the current stones stay untouched. The build phase (`sync`) is wrapped so a
     * builder-time error (e.g. a mount on a mainStone-less type) also leaves state untouched.
     * @return Array of removed keys.
     */
    @:keep public function syncEntries():Promise<Array<String>> {
        validateData(db.data);
        var enabled:Array<Dynamic> = [];
        for (e in (db.data:Array<Dynamic>)) if (!isDisabled(e)) enabled.push(e);
        return expandEntries(enabled).then(flat -> {
            var sorted = topoSort(flat);
            // Cache cleanup: capture the stones of keys that will be removed, before sync drops them.
            var removedStones:Array<AnyStone> = null;
            if (clearCacheOnRemove) {
                var newKeys = new js.lib.Set<String>();
                for (e in sorted) newKeys.add(e.key);
                removedStones = [];
                for (key in entryMap.keys()) if (!newKeys.has(key)) {
                    var entry = entryMap.get(key);
                    if (entry.stones != null) for (s in entry.stones) removedStones.push(s);
                }
            }
            var removed = withRollback(() -> sync(sorted, e -> e.key));
            if (removedStones != null) for (s in removedStones) project.cache.clearStone(s);
            return removed;
        });
    }

    /**
     * Expand raw entries into the flat list `sync` consumes. v1 is 1:1 identity; the `each` bean
     * replaces this with directory-scan expansion.
     *
     * `config` is passed by reference: `db.data` is the owned canonical baseline, and `dataMap` is a
     * live view of it (revert re-applies `db.data`, so no snapshot is kept — see y4be design). Callers
     * update by *replacing* entries/the array (as the WS client does), not by editing fields in place;
     * an in-place field edit aliases the change-detection baseline and would be missed.
     */
    function expandEntries(entries:Array<Dynamic>):Promise<Array<FlatEntryData>> {
        return Promise.resolve([for (e in entries) {
            key: (e.id:String),
            type: (e.type:String),
            config: e.config != null ? e.config : {},
            mount: e.mount,
        }]);
    }

    override public function sync(data:Array<FlatEntryData>, keyFn:FlatEntryData->String):Array<String> {
        touchedKeys.clear();
        return super.sync(data, keyFn);
    }

    override function createEntry(key:String, data:FlatEntryData):BuiltEntry {
        touchedKeys.add(key);
        var typeEntry = StoneRegistry.get(data.type);
        if (typeEntry == null) // Guarded by validateData, but keep the error local & explicit.
            throw new js.lib.Error('StoneStore entry "$key" has unknown type "${data.type}".');
        var revived = ConfigReviver.revive(data.config, makeResolve(key));
        var entry:BuiltEntry = typeEntry.builder(key, revived);

        // Append mount routes (implicit mainStone target).
        if (data.mount != null) {
            if (entry.mainStone == null)
                throw new js.lib.Error('StoneStore entry "$key" declares a mount, but its type '
                    + '"${data.type}" produced no mainStone (composite types route via the builder).');
            var mountRoutes = buildMountRoutes(data.mount, entry.mainStone);
            var existing:Array<Dynamic> = if (entry.routes == null) []
                else if ((entry.routes:Dynamic) is Array) (cast entry.routes) else [cast entry.routes];
            entry.routes = cast existing.concat(mountRoutes);
        }

        // ConfigStore-overlap warning: two sources of truth for the same stone id (doc 03 rule).
        var store = project.configStore;
        if (store != null && entry.stones != null) {
            for (s in (entry.stones:Array<AnyStone>))
                if (store.getEntryById(s.id) != null)
                    Log.warn('StoneStore-defined stone also has a ConfigStore patch — two sources of '
                        + 'truth; edit the store entry instead.', { id: s.id });
        }
        return entry;
    }

    override function updateEntry(key:String, data:FlatEntryData, existing:BuiltEntry):Void {
        touchedKeys.add(key);
        if (existing.update != null) {
            var revived = ConfigReviver.revive(data.config, makeResolve(key));
            existing.update(key, revived, existing);
        } else {
            // Id-stable recreate: same id + same config → same cache keys, so recreate is
            // cache-neutral. Remove before create (Stone ctor warns on duplicate explicit ids).
            removeEntry(key);
            entryMap.set(key, createEntry(key, data));
        }
    }

    /**
     * Reference-consistency cascade: an existing key updates if its own data changed (or it is
     * previewed), OR any store ref it depends on was touched this pass. Topo order guarantees
     * dependencies are processed first, so a single forward pass suffices. Without this, an unchanged
     * entry keeps a dead instance of a recreated dependency.
     */
    override function shouldUpdateEntry(key:String, newData:FlatEntryData):Bool {
        if (super.shouldUpdateEntry(key, newData)) return true;
        for (id in ConfigReviver.collectStoneRefs(newData.config)) if (touchedKeys.has(id)) return true;
        return false;
    }

    override public function previewEntry(key:String, data:FlatEntryData):Void {
        super.previewEntry(key, data);
        cascadeDependents(key);
        // The default update path recreates instances, so the Router must be re-pointed at them.
        rebuildRoutes();
    }

    override public function revertEntry(key:String):Bool {
        var reverted = super.revertEntry(key);
        if (reverted) {
            cascadeDependents(key);
            rebuildRoutes();
        }
        return reverted;
    }

    // --- Internals ---

    /** Resolver for `$stone` refs in an entry's config: sibling store entries first, then project. */
    function makeResolve(referrer:String):(id:String)->AnyStone {
        return id -> {
            if (entryMap.has(id)) {
                var main = entryMap.get(id).mainStone;
                if (main == null)
                    throw new js.lib.Error('StoneStore entry "$referrer" references "$id", but that '
                        + 'entry produced no mainStone.');
                return main;
            }
            var stone = project.getStone(id);
            if (stone != null) return stone;
            throw new js.lib.Error('StoneStore entry "$referrer" references unknown stone id "$id".');
        };
    }

    /** `mount` (string dir/file, or array of `[routeUnder, filter?, extractDirs?]`) → factory routes. */
    function buildMountRoutes(mount:Dynamic, mainStone:AnyStone):Array<Dynamic> {
        if (mount is String) return [[mount, mainStone]];
        var out:Array<Dynamic> = [];
        for (m in (mount:Array<Dynamic>)) {
            var arr:Array<Dynamic> = m;
            var route:Array<Dynamic> = [arr[0], mainStone];
            if (arr.length > 1 && arr[1] != null) route.push(arr[1]);          // filter
            if (arr.length > 2 && arr[2] != null) route.push(arr[2]);          // extractDirs
            out.push(route);
        }
        return out;
    }

    /**
     * Re-update every synced entry that (transitively) references `key`, in topological order, so a
     * dependent re-revives and captures `key`'s recreated instance. Dependents are NOT marked
     * previewed — their canonical data is unchanged. Used by both `previewEntry` and `revertEntry`.
     */
    function cascadeDependents(key:String):Void {
        var keys:Array<String> = [for (k in dataMap.keys()) k];
        var refsOf = new Map<String, Array<String>>();
        var keySet = new Map<String, Bool>();
        for (k in keys) keySet.set(k, true);
        for (k in keys)
            refsOf.set(k, ConfigReviver.collectStoneRefs(dataMap.get(k).config).filter(r -> keySet.exists(r)));

        // Transitive dependents of `key` (keys that reach it), computed to a fixpoint.
        var dependents = new Map<String, Bool>();
        var changed = true;
        while (changed) {
            changed = false;
            for (k in keys) {
                if (k == key || dependents.exists(k)) continue;
                for (r in refsOf.get(k)) {
                    if (r == key || dependents.exists(r)) { dependents.set(k, true); changed = true; break; }
                }
            }
        }
        for (k in topoOrder(keys, refsOf))
            if (dependents.exists(k)) updateEntry(k, dataMap.get(k), entryMap.get(k));
    }

    /** Structural validation of `data`; collects ALL problems into one thrown error (all-or-nothing). */
    function validateData(data:Dynamic):Void {
        if (!(data is Array))
            throw new js.lib.Error('StoneStore data must be a JSON array.');
        var arr:Array<Dynamic> = data;
        var errors:Array<String> = [];
        var idCounts = new Map<String, Int>();
        var registered = [for (t in StoneRegistry.list()) t.name];

        for (i in 0...arr.length) {
            var e:Dynamic = arr[i];
            var where = 'entry [$i]';
            if (!isPlainObject(e)) { errors.push('$where is not an object'); continue; }

            var id:Dynamic = e.id;
            if (!(id is String) || (id:String).length == 0) errors.push('$where has a missing or empty "id"');
            else { where = 'entry "$id"'; idCounts.set(id, (idCounts.exists(id) ? idCounts.get(id) : 0) + 1); }

            var type:Dynamic = e.type;
            if (!(type is String) || (type:String).length == 0) errors.push('$where has a missing or empty "type"');
            else if (StoneRegistry.get(type) == null)
                errors.push('$where has unknown type "$type"; registered types: ' + registered.join(', '));

            if (e.mount != null) {
                var m:Dynamic = e.mount;
                if (!(m is String)) {
                    if (m is Array) {
                        for (route in (m:Array<Dynamic>))
                            if (!(route is Array) || !((route:Array<Dynamic>)[0] is String))
                                errors.push('$where has a malformed mount route (expected '
                                    + '[routeUnder, filter?, extractDirs?])');
                    } else errors.push('$where "mount" must be a string or an array');
                }
            }
        }
        for (id => count in idCounts) if (count > 1) errors.push('Duplicate entry id "$id" ($count occurrences)');

        if (errors.length > 0)
            throw new js.lib.Error('StoneStore validation failed:\n - ' + errors.join('\n - '));
    }

    /** Topologically sort flat entries (dependencies first); throws on a cycle, naming the path. */
    function topoSort(flat:Array<FlatEntryData>):Array<FlatEntryData> {
        var byKey = new Map<String, FlatEntryData>();
        var keys:Array<String> = [];
        var keySet = new Map<String, Bool>();
        for (e in flat) { byKey.set(e.key, e); keys.push(e.key); keySet.set(e.key, true); }
        var refsOf = new Map<String, Array<String>>();
        for (e in flat)
            refsOf.set(e.key, ConfigReviver.collectStoneRefs(e.config).filter(r -> keySet.exists(r)));
        return [for (k in topoOrder(keys, refsOf)) byKey.get(k)];
    }

    /** Post-order DFS over `refsOf` yielding a dependencies-first ordering; throws on a cycle. */
    function topoOrder(keys:Array<String>, refsOf:Map<String, Array<String>>):Array<String> {
        var result:Array<String> = [];
        var state = new Map<String, Int>(); // 1 = visiting, 2 = done
        var stack:Array<String> = [];
        function visit(k:String):Void {
            var st = state.get(k);
            if (st == 2) return;
            if (st == 1) {
                var idx = stack.indexOf(k);
                throw new js.lib.Error('Cycle detected in StoneStore refs: '
                    + stack.slice(idx).concat([k]).join(' -> '));
            }
            state.set(k, 1);
            stack.push(k);
            var refs = refsOf.get(k);
            if (refs != null) for (r in refs) visit(r);
            stack.pop();
            state.set(k, 2);
            result.push(k);
        }
        for (k in keys) visit(k);
        return result;
    }

    /**
     * Run `fn` (a mutating sync); on failure restore entryMap/dataMap/project.stones and rebuild
     * routes, then rethrow — so a build-time error leaves existing stones untouched.
     */
    function withRollback<R>(fn:Void->R):R {
        var stonesSnapshot = project.stones.copy();
        var entrySnapshot:Array<{k:String, v:BuiltEntry}> = [for (k in entryMap.keys()) { k: k, v: entryMap.get(k) }];
        var dataSnapshot:Array<{k:String, v:FlatEntryData}> = [for (k in dataMap.keys()) { k: k, v: dataMap.get(k) }];
        try {
            return fn();
        } catch (err:Dynamic) {
            project.stones.splice(0, project.stones.length);
            for (s in stonesSnapshot) project.stones.push(s);
            entryMap.clear();
            for (e in entrySnapshot) entryMap.set(e.k, e.v);
            dataMap.clear();
            for (e in dataSnapshot) dataMap.set(e.k, e.v);
            rebuildRoutes();
            throw err;
        }
    }

    static inline function isDisabled(e:Dynamic):Bool return e != null && e.disabled == true;

    static inline function isPlainObject(v:Dynamic):Bool {
        return v != null
            && js.Syntax.code('typeof {0} === "object"', v)
            && !(v is Array)
            && js.Syntax.code('(Object.getPrototypeOf({0}) === null || Object.getPrototypeOf({0}) === Object.prototype)', v);
    }

}

typedef StoneStoreConfig = {
    /** Identifier for the store (script-side reference); optional. */
    var ?id:String;
    /** DB filename / stone id. Defaults to `stone-store.json`. */
    var ?dbId:String;
    /** Clear removed entries' caches on sync (default false). */
    var ?clearCacheOnRemove:Bool;
    /** Owning project; defaults to the last-created project (via the db stone). */
    var ?project:Project;
};

/** A flattened, ready-to-build entry: the shape `sync` consumes (`each` expansion runs before this). */
typedef FlatEntryData = {
    var key:String;
    var type:String;
    var config:Dynamic;
    var ?mount:Dynamic;
};
