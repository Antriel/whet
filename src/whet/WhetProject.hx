package whet;

import haxe.Constraints.Function;
import haxe.DynamicAccess;
import haxe.PosInfos;
import haxe.rtti.Meta;

#if !macro
@:autoBuild(whet.Macros.addDocsMeta())
#end
class WhetProject {

    public final config:WhetProjectConfig;

    public final commands:Map<String, CommandMetadata>;
    public final commandsMeta:Array<CommandMetadata>;

    public var rootDir(get, never):SourceId;

    @:allow(whet) private static final projects:Map<String, WhetProject> = [];

    public function new(config:WhetProjectConfig, ?posInfos:PosInfos) {
        this.config = config;
        if (config.id == null) config.id = StringTools.replace(config.name, ' ', '-').toLowerCase();
        if (config.rootDir == null) config.rootDir = (posInfos.fileName:SourceId).dir;
        if (config.cache == null) config.cache = { project: this };
        commands = new Map();
        commandsMeta = [];
        projects.set(posInfos.fileName, this);
    }

    public function addCommands(ctx:Dynamic) {
        var meta:DynamicAccess<Dynamic> = Meta.getFields(Type.getClass(ctx));
        for (name => val in meta) {
            var command:Array<Dynamic> = val.command;
            if (command != null && command.length == 2) {
                var hasArg = command[0] == true;
                var meta:CommandMetadata = {
                    names: [],
                    description: command[1],
                    fnc: function(arg) Reflect.callMethod(ctx, Reflect.field(ctx, name), hasArg ? [arg] : [])
                };
                if (!commands.exists(name)) meta.names.push(name);
                if (Reflect.hasField(ctx, 'id')) {
                    var alias = Std.string(Reflect.field(ctx, 'id')) + "." + name;
                    if (!commands.exists(alias)) meta.names.push(alias);
                }
                for (name in meta.names) commands.set(name, meta);
                commandsMeta.push(meta);
            }
        }
    }

    inline function get_rootDir() return config.rootDir;

}

@:structInit class WhetProjectConfig {

    public var name:String;
    public var id:String = null;
    public var description:String = null;
    public var cache:CacheManager = null;
    public var rootDir:SourceId = null;

}

typedef CommandMetadata = {

    var fnc:Function;
    var names:Array<String>;
    var description:String;

}
