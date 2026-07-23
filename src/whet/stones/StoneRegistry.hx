package whet.stones;

import whet.Log;
import whet.Stone.AnyStone;
import whet.stones.Zip.ZipStone;
import whet.stones.StoneFactory.FactoryEntry;

using js.lib.HaxeIterator;

/**
 * Named registry of stone-type **builders**. A registered type is a `StoneBuilder`: given an entry
 * key and a revived config, it produces one or more live stones (plus optional routes/mainStone/
 * update hook). This lets a single JSON entry declare a multi-stone chain, and lets builders skip
 * stages conditionally.
 *
 * `register` is single-stone sugar over `registerBuilder`. Built-ins (`Files`, `JsonStone`, `Zip`,
 * `RemoteFile`) self-register on module load.
 */
@:expose
class StoneRegistry {

    static final registry:js.lib.Map<String, StoneTypeEntry> = new js.lib.Map();

    /**
     * Builtins are registered lazily on first access rather than at module-evaluation time. Doing it
     * eagerly (in `__init__`) references the builtin class bindings while this module evaluates, which
     * TDZ-crashes ("Cannot access 'Files' before initialization") whenever an import cycle pulls this
     * module in ahead of those classes (e.g. the CLI's `stone-schema` command importing the registry
     * from the entry module). Deferring to first access means the class bindings are only touched at
     * runtime, once the whole module graph is initialized. Still synchronous, so "registered on import"
     * holds: the first `get`/`list`/`register` call materializes them.
     */
    static var builtinsRegistered = false;

    static inline function ensureBuiltins():Void {
        if (!builtinsRegistered) registerBuiltins();
    }

    /**
     * Register a single-stone type. The builder instantiates `new ctor({...config, id: key})`
     * (config shallow-copied — the caller's object is never mutated). When `schema` is omitted and
     * `ctor.configSchema` is a function, it is called to obtain the schema (convention wired here;
     * lands in a sibling bean).
     */
    @:keep public static function register(name:String, ctor:Dynamic, ?schema:Dynamic):Void {
        if (schema == null)
            schema = js.Syntax.code("(typeof {0}.configSchema === 'function') ? {0}.configSchema() : null", ctor);
        var builder:StoneBuilder = (key, config) -> {
            var merged:Dynamic = js.Syntax.code("Object.assign({}, {0}, { id: {1} })", config, key);
            var stone:AnyStone = js.Syntax.code("new {0}({1})", ctor, merged);
            return { stones: [stone], mainStone: stone };
        };
        registerBuilder(name, builder, schema);
    }

    /**
     * Register a raw builder for a composite chain (e.g. a wav→sox→…→ogg audio type that may skip
     * stages). Builders return their own `routes`; `mainStone` is optional.
     */
    @:keep public static function registerBuilder(name:String, builder:StoneBuilder, ?schema:Dynamic):Void {
        ensureBuiltins();
        if (registry.has(name))
            Log.warn('Stone type "$name" is already registered; overwriting.');
        registry.set(name, { name: name, builder: builder, schema: schema });
    }

    /** Look up a registered type, or null if unknown. */
    @:keep public static function get(name:String):Null<StoneTypeEntry> {
        ensureBuiltins();
        return registry.has(name) ? registry.get(name) : null;
    }

    /** List registered types with whether each carries a schema. */
    @:keep public static function list():Array<{name:String, hasSchema:Bool}> {
        ensureBuiltins();
        var out = [];
        for (entry in registry.values()) out.push({ name: entry.name, hasSchema: entry.schema != null });
        return out;
    }

    /** Register Whet's built-in stone types. Idempotent (re-registration just overwrites). */
    @:keep public static function registerBuiltins():Void {
        // Set the flag *before* registering so the re-entrant `register` calls below (which each call
        // `ensureBuiltins`) don't recurse.
        builtinsRegistered = true;
        register("Files", Files);
        register("JsonStone", JsonStone);
        register("JsonDb", JsonDb);
        register("Zip", ZipStone);
        register("RemoteFile", RemoteFile);
    }

}

typedef BuiltEntry = FactoryEntry & {
    /** The primary stone for this entry (implicit `"$self"` mount target). */
    var ?mainStone:AnyStone;
    /** Optional in-place update hook for a re-synced config (skips destroy+recreate). */
    var ?update:(key:String, revivedConfig:Dynamic, existing:Dynamic)->Void;
};

typedef StoneBuilder = (key:String, revivedConfig:Dynamic)->BuiltEntry;

typedef StoneTypeEntry = {
    var name:String;
    var builder:StoneBuilder;
    var ?schema:Dynamic;
};
