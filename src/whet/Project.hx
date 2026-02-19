package whet;

import whet.Stone.OutputFilter;
import whet.magic.StoneId.getTypeName;

@:expose var addOption = commander.Option.new;

@:expose
class Project {

    public final name:String;
    public final id:String;
    public final description:String;
    public final rootDir:SourceId;
    public final cache:CacheManager = null;
    public final configStore:ConfigStore = null;
    public final stones:Array<AnyStone> = [];
    public var onInit:(config:Dynamic) -> Promise<Any>;
    /** The object passed to `onInit`. */
    public var config:Dynamic;

    @:allow(whet) private final options:Array<commander.Option>;

    @:allow(whet) private static final projects:Array<Project> = [];

    public function new(config:ProjectConfig) {
        Log.debug('Instantiating new Project.');
        if (config == null || config.name == null) throw new js.lib.Error("Must supply config and a name.");
        name = config.name;
        if (config.id == null) id = StringTools.replace(config.name, ' ', '-').toLowerCase();
        else id = config.id;
        description = config.description;
        this.options = if (config.options == null) [] else config.options;
        this.onInit = config.onInit;

        if (config.rootDir == null) {
            final oldValue = js.Syntax.code('Error').prepareStackTrace;
            js.Syntax.code('Error').prepareStackTrace = (_, stack) -> stack;
            // 0 us, 1 genes.Register, 2 us again, 3 is the caller.
            var file:String = untyped new js.lib.Error().stack[3].getFileName();
            js.Syntax.code('Error').prepareStackTrace = oldValue;
            file = js.Syntax.code('decodeURI({0})', file);
            file = StringTools.replace(file, 'file:///', '');
            rootDir = (IdUtils.normalize(js.node.Path.relative(js.Node.process.cwd(), file)):SourceId).dir;
            // TODO write tests for this.
        } else rootDir = config.rootDir;
        configStore = config.configStore;
        cache = config.cache == null ? new CacheManager(this) : config.cache;
        projects.push(this);
        Log.info('New project created.', { project: this, projectCount: projects.length });
    }

    public function getStone(id:String):Null<AnyStone> {
        for (stone in stones) {
            if (stone.id == id) return stone;
        }
        return null;
    }

    public function describeStones():Array<StoneDescription> {
        return [for (stone in stones) {
            id: stone.id,
            className: getTypeName(stone),
            outputFilter: stone.getOutputFilter(),
            cacheStrategy: stone.cacheStrategy,
        }];
    }

    public function listStoneOutputs(id:String):Promise<Null<Array<SourceId>>> {
        final stone = getStone(id);
        return if (stone == null) Promise.resolve(null) else stone.listIds();
    }

    public function getStoneSource(id:String, ?sourceId:SourceId):Promise<Null<Source>> {
        final stone = getStone(id);
        return if (stone == null) Promise.resolve(null)
        else if (sourceId != null) stone.getPartialSource(sourceId)
        else stone.getSource();
    }

    public function getStoneConfig(id:String):Promise<Null<StoneConfigView>> {
        final stone = getStone(id);
        if (stone == null) return Promise.resolve(null);
        final store:ConfigStore = stone.config.configStore ?? configStore;
        // Ensure patches are applied before reading config.
        var init = if (store != null) store.ensureApplied(stone) else Promise.resolve(null);
        return init.then(_ -> {
            var editable = new haxe.DynamicAccess<Dynamic>();
            var configObj:haxe.DynamicAccess<Dynamic> = cast stone.config;
            for (key => val in configObj) {
                if (ConfigStore.BASE_CONFIG_KEYS.contains(key)) continue;
                if (ConfigStore.isJsonSerializable(val))
                    editable.set(key, ConfigStore.deepClone(val));
            }
            var depIds:Array<String> = [];
            if (stone.config.dependencies != null) {
                var deps:Array<AnyStone> = whet.magic.MaybeArray.makeArray(stone.config.dependencies);
                depIds = [for (d in deps) d.id];
            }
            var view:StoneConfigView = {
                id: stone.id,
                editable: editable,
                meta: {
                    className: getTypeName(stone),
                    cacheStrategy: stone.cacheStrategy,
                    dependencyIds: depIds,
                    hasStoneConfigStore: stone.config.configStore != null,
                    hasProjectConfigStore: configStore != null,
                }
            };
            return view;
        });
    }

    public function setStoneConfig(id:String, patch:Dynamic, mode:ConfigPatchMode):Promise<Bool> {
        final stone = getStone(id);
        if (stone == null) return Promise.resolve(false);
        final store:ConfigStore = stone.config.configStore ?? configStore;
        if (store == null) return Promise.resolve(false);
        store.setEntry(stone.id, patch);
        return if (mode == Persist) store.flush().then(_ -> true) else Promise.resolve(true);
    }

    public function clearStoneConfigPreview(id:String):Promise<Bool> {
        final stone = getStone(id);
        if (stone == null) return Promise.resolve(false);
        final store:ConfigStore = stone.config.configStore ?? configStore;
        if (store == null) return Promise.resolve(false);
        store.clearEntry(stone.id);
        return Promise.resolve(true);
    }

    public function addCommand(name:String, ?stone:AnyStone):commander.Command {
        var cmd = new commander.Command(name);
        if (stone != null) cmd.alias(stone.id + '.' + cmd.name());
        whet.Whet.program.addCommand(cmd);
        return cmd;
    }

    public function toString() return '$name@$rootDir';

}

typedef ProjectConfig = {

    public var name:String;
    public var ?id:String;
    public var ?description:String;
    public var ?cache:CacheManager;
    public var ?rootDir:String;

    /**
     * Array of Commander.js options this project supports. Use `addOption` to get Option instance.
     */
    /** Project-level ConfigStore, applies to any stone without an explicit configStore. */
    public var ?configStore:ConfigStore;

    public var ?options:Array<commander.Option>;

    /**
     * Called before first command is executed, but after configuration was parsed.
     */
    public var ?onInit:(config:Dynamic) -> Promise<Any>;

}

typedef StoneDescription = {

    var id:String;
    var className:String;
    var ?outputFilter:OutputFilter;
    var ?cacheStrategy:CacheStrategy;

}

enum abstract ConfigPatchMode(String) {
    var Preview = "preview";
    var Persist = "persist";
}

typedef StoneConfigView = {
    var id:String;
    var editable:Dynamic;
    var meta:StoneConfigMeta;
}

typedef StoneConfigMeta = {
    var className:String;
    var cacheStrategy:CacheStrategy;
    var dependencyIds:Array<String>;
    var hasStoneConfigStore:Bool;
    var hasProjectConfigStore:Bool;
    var ?uiHints:Dynamic;
}
