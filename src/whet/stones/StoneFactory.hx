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

    /** Canonical (last-synced) data per key. Baseline that `revertEntry` re-applies. */
    public final dataMap:js.lib.Map<String, D> = new js.lib.Map();

    /** Keys whose live stones diverge from `dataMap` due to a preview. */
    public final previewedKeys:js.lib.Set<String> = new js.lib.Set();

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
                if (shouldUpdateEntry(key, item)) updateEntry(key, item, entryMap.get(key));
            } else {
                entryMap.set(key, createEntry(key, item));
            }

            // Record canonical data (a sync always reasserts the baseline, even on skip).
            dataMap.set(key, item);

            // Add routes for this entry (regardless of whether the update was skipped).
            var entry = entryMap.get(key);
            if (entry.routes != null) route(cast entry.routes);
        }

        // Remove entries not present in new data.
        var toRemove:Array<String> = [];
        for (key in entryMap.keys()) if (!newKeys.has(key)) toRemove.push(key);
        for (key in toRemove) {
            removeEntry(key);
            dataMap.delete(key);
            previewedKeys.delete(key);
        }

        // A completed sync reasserts canonical state over any lingering previews.
        previewedKeys.clear();
        return toRemove;
    }

    /**
     * Whether an existing key's `updateEntry` should run this sync. Default: `true` when the
     * incoming data differs (by JSON) from the canonical `dataMap` entry, OR the key is currently
     * previewed (a sync must always reassert canonical over a preview). A spurious `true` from a
     * key-order difference is harmless — it just runs `updateEntry` as every sync did before.
     * Subclasses may override (e.g. StoneStore adds a dependency cascade).
     */
    function shouldUpdateEntry(key:String, newData:D):Bool {
        return previewedKeys.has(key)
            || haxe.Json.stringify(cast newData) != haxe.Json.stringify(cast dataMap.get(key));
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

    /**
     * Apply `data` to a key's live stones without recording it as canonical. If the key exists it is
     * updated in place; otherwise a new entry is created and routed (previewing a not-yet-synced key
     * must work). Never touches `dataMap`. No regeneration is triggered here — whet's hash cache
     * regenerates affected sub-stones lazily on next `getSource()` because their configs (and thus
     * hashes) changed.
     */
    @:keep public function previewEntry(key:String, data:D):Void {
        if (entryMap.has(key)) {
            updateEntry(key, data, entryMap.get(key));
        } else {
            var entry = createEntry(key, data);
            entryMap.set(key, entry);
            if (entry.routes != null) route(cast entry.routes);
        }
        previewedKeys.add(key);
    }

    /**
     * Undo a preview on a key, restoring canonical state. If the key has canonical data, re-apply it
     * via `updateEntry`. If it was preview-created (no canonical), remove it and rebuild routes.
     * @return true if anything was reverted, false if the key was neither previewed nor known.
     */
    @:keep public function revertEntry(key:String):Bool {
        if (dataMap.has(key)) {
            updateEntry(key, dataMap.get(key), entryMap.get(key));
            previewedKeys.delete(key);
            return true;
        } else if (entryMap.has(key)) {
            removeEntry(key);
            previewedKeys.delete(key);
            rebuildRoutes();
            return true;
        }
        return false;
    }

    /** Revert every previewed key back to canonical state. */
    @:keep public function revertAllPreviews():Void {
        // Copy first — revertEntry mutates previewedKeys.
        var keys:Array<String> = [];
        for (key in previewedKeys.keys()) keys.push(key);
        for (key in keys) revertEntry(key);
    }

    /** With `key`: whether that key is previewed. Without: whether any key is previewed. */
    @:keep public function isPreviewDirty(?key:String):Bool {
        return if (key != null) previewedKeys.has(key) else previewedKeys.size > 0;
    }

    /**
     * Rebuild the Router's routes from scratch: base routes, then each entry's routes in `entryMap`
     * insertion order. Used by the revert-removal path (`sync()` keeps its own inline route building).
     */
    @:keep public function rebuildRoutes():Void {
        clearRoutes();
        addBaseRoutes();
        for (entry in entryMap.values()) {
            if (entry.routes != null) route(cast entry.routes);
        }
    }

}

typedef FactoryEntry = {

    /** Stones owned by this entry — deregistered from project on removal. */
    var stones:Array<AnyStone>;

    /** Route definitions for this entry — added to the factory's Router on sync. */
    var ?routes:RoutePathType;

}
