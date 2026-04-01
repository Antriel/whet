package whet.cache;

@:jsRequire("node:async_hooks", "AsyncLocalStorage")
extern class AsyncLocalStorage<T> {

    function new();

    /** Returns the current store. Undefined if called outside of an async context initialized by `run`. */
    function getStore():Null<T>;

    /** Runs a function synchronously within a context and returns its return value. */
    function run<R>(store:T, callback:Void->R):R;

}
