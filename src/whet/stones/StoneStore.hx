package whet.stones;

import haxe.DynamicAccess;
import whet.Log;
import whet.Utils;
import whet.ConfigStore;
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

    /**
     * Per-group scan results (files + derived names) from the last `syncEntries()` expansion, keyed by
     * group entry id. Mirror of AudioDb.groupMatches; read via `getExpansion` by the future editor
     * plugin. NOT refreshed by `previewEntry` (previews never rescan — see the perf invariant).
     */
    final groupMatches:js.lib.Map<String, {files:Array<String>, names:Array<String>}> = new js.lib.Map();

    /** `scanParamsOf(each)` per group in `groupMatches`, so `expandRaw` knows when the cached scan still applies. */
    final groupScanParams:js.lib.Map<String, String> = new js.lib.Map();

    public function new(?config:StoneStoreConfig) {
        super();
        if (config == null) config = {};
        var dbId:String = config.dbId != null ? config.dbId : 'stone-store.json';
        db = new JsonDb({ id: dbId, project: config.project });
        // An external edit of the DB file (picked up by `db.refresh`, or an explicit `db.reload`)
        // re-syncs the entries.
        db.onReload(() -> syncEntries());
        clearCacheOnRemove = config.clearCacheOnRemove == true;
    }

    /** Load the DB file (project-relative), sync entries, and resolve with `this`. */
    @:keep public function load(path:String):Promise<StoneStore> {
        return db.load(path).then(_ -> syncEntries()).then(_ -> this);
    }

    /**
     * Persist the DB's canonical data back to its file. Rejects with a `TrackedFile.CONFLICT` error if
     * the file changed on disk since it was last read, unless `force`. Resolves true if bytes were written.
     */
    @:keep public function flushDb(force:Bool = false):Promise<Bool> {
        return db.save(force);
    }

    /**
     * Pick up external edits of the DB file: if it changed on disk and `db.data` has no unsaved
     * changes, reload and re-sync. Resolves true if it reloaded. Routing calls this itself; code that
     * reads entries outside the router (`entryMap`, `dataMap`, `getExpansion`, ...) must call it first.
     */
    @:keep public function refresh():Promise<Bool> {
        return db.refresh();
    }

    // --- Router overrides: pick up external edits of the DB file before resolving routes ---
    // Requests for entry outputs never touch the db stone, so its own `generateHash` check isn't enough.

    override function getResults(mainFilters:whet.route.Router.Filters, results:Array<whet.route.RouteResult>):Promise<Array<whet.route.RouteResult>> {
        return refresh().then(_ -> superGetResults(mainFilters, results));
    }

    override function getUnfilteredHash():Promise<SourceHash> {
        return refresh().then(_ -> superGetUnfilteredHash());
    }

    function superGetResults(mainFilters, results) return super.getResults(mainFilters, results);

    function superGetUnfilteredHash() return super.getUnfilteredHash();

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
            validateSchemas(flat);
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
     * Expand raw entries into the flat list `sync` consumes. Entries without an `each` clause pass
     * through 1:1. An `each` clause scans `each.dir` (see `expandGroup` for keys, overrides and
     * tokens). Scans run only here — never during `previewEntry` (the perf invariant).
     *
     * `config` for non-each entries is passed by reference: `db.data` is the owned canonical baseline,
     * and `dataMap` is a live view of it (revert re-applies `db.data`, so no snapshot is kept — see the
     * y4be design). Callers update by *replacing* entries/the array (as the WS client does), not by
     * editing fields in place; an in-place field edit aliases the change-detection baseline. Expanded
     * entries always get a fresh (token-substituted) config, so they never alias `db.data`.
     */
    function expandEntries(entries:Array<Dynamic>):Promise<Array<FlatEntryData>> {
        groupMatches.clear();
        groupScanParams.clear();
        var out:Array<FlatEntryData> = [];
        var sources:Array<String> = []; // parallel to `out`, for collision reporting

        // Chain scans so groupMatches / output order stay deterministic (entries in db order).
        var chain:Promise<Nothing> = Promise.resolve(Nil);
        for (e in entries) {
            var entry = e;
            chain = chain.then(_ -> {
                if (entry.each == null) {
                    out.push(singleEntry(entry));
                    sources.push('(single entry)');
                    return Promise.resolve(Nil);
                }
                return scanGroup(entry.each).then(matches -> {
                    groupMatches.set((entry.id:String), matches);
                    groupScanParams.set((entry.id:String), scanParamsOf(entry.each));
                    for (fe in expandGroup(entry, matches)) out.push(fe);
                    for (f in matches.files) sources.push(f);
                    return Nil;
                });
            });
        }

        return chain.then(_ -> {
            assertUniqueKeys(out, sources);
            return out;
        });
    }

    /** A non-`each` entry as the flat entry `sync` consumes (config by reference, see `expandEntries`). */
    static function singleEntry(entry:Dynamic):FlatEntryData {
        return {
            key: (entry.id:String),
            type: (entry.type:String),
            config: entry.config != null ? entry.config : {},
            mount: entry.mount,
        };
    }

    function scanGroup(each:Dynamic):Promise<{files:Array<String>, names:Array<String>}> {
        return Utils.scanFiles(cast project.rootDir, each.dir, each.pattern, each.nameTemplate);
    }

    /** Identity of an `each` scan: a cached scan is reusable only while these are unchanged. */
    static function scanParamsOf(each:Dynamic):String {
        return haxe.Json.stringify([each.dir, each.pattern, each.nameTemplate]);
    }

    /**
     * Expand one `each` group over already-scanned `matches` (no I/O), one flat entry per file, in
     * `matches.files` order. The key is the `each.nameTemplate` expansion verbatim when a template is
     * given, else `groupId/name` (bare stems as project-wide ids would collide by accident). Sparse
     * per-file `overrides`, keyed by derived name, merge over `config` (`mergeOverride`), then
     * `$file`/`$name` are substituted throughout (config, `$router` route arrays, and mount).
     */
    static function expandGroup(entry:Dynamic, matches:{files:Array<String>, names:Array<String>}):Array<FlatEntryData> {
        var groupId:String = entry.id;
        // Typo guard: an override keyed by a name no file produced is almost always a typo.
        if (entry.overrides != null) {
            var ov:DynamicAccess<Dynamic> = entry.overrides;
            for (ovKey in ov.keys())
                if (matches.names.indexOf(ovKey) == -1)
                    Log.warn('StoneStore group "$groupId" has an override for "$ovKey", which '
                        + 'matches no scanned file (typo?).', { group: groupId });
        }
        var templated = entry.each.nameTemplate != null;
        var out:Array<FlatEntryData> = [];
        for (i in 0...matches.files.length) {
            var name = matches.names[i];
            var file = matches.files[i];
            var base:Dynamic = entry.config != null ? entry.config : {};
            var ovr:Dynamic = entry.overrides != null ? Reflect.field(entry.overrides, name) : null;
            var raw = ovr == null ? base : mergeOverride(base, ovr, '', (path, msg) ->
                Log.warn('StoneStore group "$groupId" override for "$name"' + (path != '' ? ' @ $path' : '')
                    + ': $msg', { group: groupId }));
            var key = templated ? name : groupId + '/' + name;
            out.push({
                key: key,
                type: (entry.type:String),
                config: substituteTokens(raw, file, name),
                mount: substituteTokens(entry.mount, file, name),
            });
        }
        return out;
    }

    /** Throws one aggregated error naming every key produced by more than one source. */
    static function assertUniqueKeys(flat:Array<FlatEntryData>, sources:Array<String>):Void {
        var keySources = new Map<String, Array<String>>();
        for (i in 0...flat.length) {
            var key = flat[i].key;
            if (!keySources.exists(key)) keySources.set(key, []);
            keySources.get(key).push(sources[i]);
        }
        var errors:Array<String> = [];
        for (key => fs in keySources)
            if (fs.length > 1)
                errors.push('expanded key "$key" produced ${fs.length}× (from: ' + fs.join(', ') + ')');
        if (errors.length > 0)
            throw new js.lib.Error('StoneStore expansion failed:\n - ' + errors.join('\n - '));
    }

    /**
     * Merge a per-file override over a group's base config. Like `ConfigStore.deepMerge` (plain
     * objects recurse, everything else replaces), except for a base array whose items are all objects
     * with a string `id`: that merges **by id**. Each override item deep-merges (this same function)
     * into the base item with its id, any field included (`type` too). The base owns membership and
     * order: an override item with no id, or an id no base item has, is warned about and ignored.
     * Arrays without ids still replace. Deliberately not `ConfigStore.deepMerge`, whose patches are
     * a separate contract. Never mutates its inputs; may share unpatched subtrees with `base`.
     */
    static function mergeOverride(base:Dynamic, patch:Dynamic, path:String, warn:(path:String, msg:String)->Void):Dynamic {
        if (isPlainObject(base) && isPlainObject(patch)) {
            var result = new DynamicAccess<Dynamic>();
            for (k => v in (base:DynamicAccess<Dynamic>)) result.set(k, v);
            for (k => v in (patch:DynamicAccess<Dynamic>))
                result.set(k, mergeOverride(result.get(k), v, path == '' ? k : path + '.' + k, warn));
            return result;
        }
        if (base is Array && patch is Array && mergesById(base, patch)) {
            var baseArr:Array<Dynamic> = base;
            var patchArr:Array<Dynamic> = patch;
            var known = [for (b in baseArr) (b.id:String) => true];
            var byId = new Map<String, Dynamic>();
            for (i in 0...patchArr.length) {
                var item = patchArr[i];
                if (!hasStringId(item))
                    warn(path + '[$i]', 'item has no "id", so it can\'t address a base item; ignored.');
                else if (!known.exists(item.id))
                    warn(path, 'no base item has id "${item.id}"; ignored (an override tunes items, it '
                        + 'can\'t add them).');
                else byId.set(item.id, item);
            }
            return [for (b in baseArr) byId.exists(b.id)
                ? mergeOverride(b, byId.get(b.id), path + '[' + b.id + ']', warn) : b];
        }
        return patch;
    }

    /** An array pair merges by id when the base is a list of id'd items (an empty base counts only if the patch is one). */
    static function mergesById(base:Array<Dynamic>, patch:Array<Dynamic>):Bool {
        function keyed(a:Array<Dynamic>) {
            for (item in a) if (!hasStringId(item)) return false;
            return a.length > 0;
        }
        return keyed(base) || (base.length == 0 && keyed(patch));
    }

    static inline function hasStringId(v:Dynamic):Bool {
        return isPlainObject(v) && v.id is String && (v.id:String).length > 0;
    }

    /**
     * Recursively copy `value`, replacing the substrings `$file`→`file` and `$name`→`name` in every
     * string (plain substring replacement — literal `$file`/`$name` text is unsupported; there is no
     * escape). Always returns fresh structures, so an expanded entry's config never aliases `db.data`.
     */
    static function substituteTokens(value:Dynamic, file:String, name:String):Dynamic {
        if (value == null) return null;
        if (value is String) {
            var s:String = value;
            // NB: double quotes — single-quoted Haxe strings would $-interpolate the token names.
            s = StringTools.replace(s, "$file", file);
            s = StringTools.replace(s, "$name", name);
            return s;
        }
        if (value is Array) return [for (item in (value:Array<Dynamic>)) substituteTokens(item, file, name)];
        if (isPlainObject(value)) {
            var obj:DynamicAccess<Dynamic> = value;
            var result = new DynamicAccess<Dynamic>();
            for (key => v in obj) result.set(key, substituteTokens(v, file, name));
            return result;
        }
        return value; // numbers / bools
    }

    /**
     * Scan results (files + derived names) for a group entry from the last `syncEntries()`, or null if
     * the id names no group (or was never expanded). For the future editor plugin's introspection.
     */
    @:keep public function getExpansion(entryId:String):Null<{files:Array<String>, names:Array<String>}> {
        return groupMatches.has(entryId) ? groupMatches.get(entryId) : null;
    }

    /**
     * Expand one raw (e.g. unsaved, editor-held) entry exactly as a sync would, without touching any
     * stone: structure and schema are validated, overrides merged, tokens substituted. Resolves with
     * the flat entries — `[]` for a disabled entry. A group reuses the last sync's scan of its id
     * (no rescan, the preview perf invariant) unless its `each` dir/pattern/nameTemplate differ from
     * that scan's, or it has none (a new group); then it scans, without caching the result.
     */
    @:keep public function expandRaw(raw:Dynamic):Promise<Array<FlatEntryData>> {
        return refresh().then(_ -> {
            validateData([raw]);
            if (isDisabled(raw)) return Promise.resolve([]);
            if (raw.each == null) return Promise.resolve([singleEntry(raw)]);
            var id:String = raw.id;
            var scan = groupMatches.has(id) && groupScanParams.get(id) == scanParamsOf(raw.each)
                ? Promise.resolve(groupMatches.get(id)) : scanGroup(raw.each);
            return scan.then(matches -> {
                var flat = expandGroup(raw, matches);
                assertUniqueKeys(flat, matches.files);
                validateSchemas(flat);
                return flat;
            });
        });
    }

    /**
     * `expandRaw`, then `previewEntry` each expanded entry (or only those whose key is in `keys`).
     * This is how an editor previews an unsaved group edit without knowing the merge rules. Resolves
     * with **all** expanded entries, previewed or not, so the editor can show effective configs.
     * An invalid entry rejects before any stone is touched. Undo with `revertEntry`/`revertAllPreviews`.
     */
    @:keep public function previewRaw(raw:Dynamic, ?keys:Array<String>):Promise<Array<FlatEntryData>> {
        return expandRaw(raw).then(flat -> {
            for (fe in flat) if (keys == null || keys.indexOf(fe.key) != -1) previewEntry(fe.key, fe);
            return flat;
        });
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
            // `false` means the hook can't apply this change in place (e.g. it alters which stones
            // exist): fall through to the recreate.
            if (js.Syntax.code("{0} !== false", existing.update(key, revived, existing))) return;
        }
        // Id-stable recreate: same id + same config → same cache keys, so recreate is
        // cache-neutral. Remove before create (Stone ctor warns on duplicate explicit ids).
        removeEntry(key);
        entryMap.set(key, createEntry(key, data));
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

    /**
     * Schema-validate each expanded entry's config against its registered type's `configSchema()`
     * (when one exists), post-expansion and post-token-substitution but pre-revive. `$stone`/`$router`
     * sentinels are skipped by the validator. All findings are aggregated into one thrown error
     * (all-or-nothing), each prefixed with the entry key and JSON path, so an LLM/JSON-authored
     * `stone-store.json` fails at sync with a path-specific message instead of a generate-time crash.
     */
    function validateSchemas(flat:Array<FlatEntryData>):Void {
        var errors:Array<String> = [];
        for (e in flat) {
            var typeEntry = StoneRegistry.get(e.type);
            if (typeEntry == null || typeEntry.schema == null) continue;
            for (f in SchemaValidator.validate(e.config, typeEntry.schema))
                errors.push('entry "${e.key}"' + (f.path != "" ? ' @ ${f.path}' : '') + ': ${f.message}');
        }
        if (errors.length > 0)
            throw new js.lib.Error('StoneStore schema validation failed:\n - ' + errors.join('\n - '));
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

            if (e.each != null) {
                var each:Dynamic = e.each;
                if (!isPlainObject(each)) errors.push('$where "each" must be an object');
                else {
                    var dir:Dynamic = each.dir;
                    if (!(dir is String) || (dir:String).length == 0)
                        errors.push('$where "each.dir" must be a non-empty string');
                    var pat:Dynamic = each.pattern;
                    if (!(pat is String) || (pat:String).length == 0)
                        errors.push('$where "each.pattern" must be a non-empty string');
                    else
                        try js.Syntax.code('new RegExp({0})', pat)
                        catch (err:Dynamic) errors.push('$where "each.pattern" is not a valid RegExp: ' + Std.string(err));
                    if (each.nameTemplate != null && !(each.nameTemplate is String))
                        errors.push('$where "each.nameTemplate" must be a string');
                }
            }
            if (e.overrides != null && e.each == null)
                errors.push('$where has "overrides" without "each" (overrides are only valid with an "each" clause)');
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
