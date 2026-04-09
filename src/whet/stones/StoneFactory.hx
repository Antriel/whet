package whet.stones;

import whet.magic.RoutePathType;
import whet.route.Router;

using js.lib.HaxeIterator;

/**
 * Base class for dynamic stone lifecycle management.
 *
 * Manages creation, update, and removal of stones based on external data.
 * Extends Router so it can be used directly as a route source.
 *
 * JS subclasses override `createEntry`, `updateEntry`, and `addBaseRoutes`.
 */
class StoneFactory<D, E:FactoryEntry> extends Router {

    public final entryMap:js.lib.Map<String, E> = new js.lib.Map();

    /**
     * Sync factory state with data. Calls `createEntry` for new keys,
     * `updateEntry` for existing keys, and removes entries whose keys are absent.
     * @return Array of removed keys (caller can use for cache cleanup via `cache.clearStone`).
     */
    @:keep public function sync(data:Array<D>, keyFn:D->String):Array<String> {
        var newKeys = new js.lib.Set<String>();
        clearRoutes();
        addBaseRoutes();

        for (item in data) {
            var key:String = keyFn(item);
            newKeys.add(key);

            if (entryMap.has(key)) {
                updateEntry(key, item, entryMap.get(key));
            } else {
                entryMap.set(key, createEntry(key, item));
            }

            // Add routes for this entry.
            var entry = entryMap.get(key);
            if (entry.routes != null) route(cast entry.routes);
        }

        // Remove entries not present in new data.
        var toRemove:Array<String> = [];
        for (key in entryMap.keys()) if (!newKeys.has(key)) toRemove.push(key);
        for (key in toRemove) {
            removeEntry(key);
        }
        return toRemove;
    }

    /** Override in subclass: create stones and routes for a new data entry. */
    function createEntry(key:String, data:D):E {
        throw new js.lib.Error("StoneFactory.createEntry must be overridden");
    }

    /**
     * Override in subclass: update an existing entry's stone configs in-place.
     * Default implementation destroys and recreates the entry.
     */
    function updateEntry(key:String, data:D, existing:E):Void {
        removeEntry(key);
        entryMap.set(key, createEntry(key, data));
    }

    /** Override in subclass: add routes that are present on every sync (e.g., a database JSON file). */
    function addBaseRoutes():Void { }

    /** Remove an entry, deregistering its stones from the project. */
    @:keep public function removeEntry(key:String):Void {
        var entry = entryMap.get(key);
        if (entry == null) return;
        if (entry.stones != null) {
            var stones:Array<AnyStone> = entry.stones;
            for (s in stones) s.project.removeStone(s);
        }
        entryMap.delete(key);
    }

}

typedef FactoryEntry = {

    /** Stones owned by this entry — deregistered from project on removal. */
    var stones:Array<AnyStone>;

    /** Route definitions for this entry — added to the factory's Router on sync. */
    var ?routes:RoutePathType;

}
