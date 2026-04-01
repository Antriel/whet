package whet.cache;

@:allow(whet)
class MemoContext {

    // Dedicated ALS instance — independent of profiler's ALS.
    static final als = new AsyncLocalStorage<MemoContext>();

    // Use js.lib.Map for object-identity keys (Stone instances).
    final sources:js.lib.Map<AnyStone, Promise<Source>> = new js.lib.Map();
    final hashes:js.lib.Map<AnyStone, Promise<SourceHash>> = new js.lib.Map();
    // Nested map: Stone → (SourceId string → Promise<Null<Source>>)
    final partials:js.lib.Map<AnyStone, js.lib.Map<String, Promise<Null<Source>>>> = new js.lib.Map();

    public function new() { }

    public static inline function getStore():Null<MemoContext>
        return als.getStore();

    /**
     * Run callback within this context. Returns the callback's return value.
     * ALS.run is synchronous — it sets the store, runs the callback, restores.
     * Promises created inside inherit the context for their async continuations.
     */
    public static inline function run<T>(ctx:MemoContext, fn:() -> T):T
        return als.run(ctx, fn);

    /** Execute fn within a MemoContext. Reuses existing context or creates a new one. */
    public static function ensure<T>(fn:() -> T):T {
        if (als.getStore() != null) return fn();
        return als.run(new MemoContext(), fn);
    }

}
