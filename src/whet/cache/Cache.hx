package whet.cache;

interface Cache {

    public function get(stone:AnyStone, durability:CacheDurability, check:DurabilityCheck):Promise<Source>;
    public function getPartial(stone:AnyStone, sourceId:SourceId, durability:CacheDurability, check:DurabilityCheck):Promise<Null<Source>>;
    public function getUniqueDir(stone:AnyStone, baseDir:SourceId, ?hash:SourceHash):SourceId;

}

enum CacheStrategy {

    None;
    InMemory(durability:CacheDurability, ?check:DurabilityCheck);
    InFile(durability:CacheDurability, ?check:DurabilityCheck);
    AbsolutePath(path:SourceId, durability:CacheDurability, ?check:DurabilityCheck);
    // TODO combined file+memory cache?

}

enum CacheDurability {

    KeepForever;
    LimitCountByLastUse(count:Int);
    LimitCountByAge(count:Int);
    MaxAge(seconds:Int);
    Custom(keep:AnyStone->Dynamic->Bool);
    All(keepIfAll:Array<CacheDurability>);
    Any(keepIfAny:Array<CacheDurability>);

}

enum DurabilityCheck {

    /** Checks all cached sources for a stone, whenever the cache is used. The default. */
    AllOnUse;

    /**
     * Checks all cached sources for a stone, whenever any resource is being added to the cache.
     * Improves performance, but can leave behind invalid files.
     */
    AllOnSet;

    /** 
     * Checks just the cached source when receiving it. Useful for custom durability checks
     * and situations where the hash isn't ensuring validity.
     */
    SingleOnGet;

}
