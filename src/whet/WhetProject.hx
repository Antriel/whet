package whet;

import haxe.Constraints.Function;
import haxe.DynamicAccess;
import haxe.rtti.Meta;
import tink.CoreApi;
import whet.Whetstone;

#if !macro
@:autoBuild(whet.Macros.addDocsMeta())
@:autoBuild(whet.Macros.injectConfig())
#end
class WhetProject {

    public final config:WhetProjectConfig;
    public final commands:Map<String, CommandMetadata>;
    public final commandsMeta:Array<CommandMetadata>;
    public final postInit:Future<Noise>;

    // final stones:Map<WhetstoneID, Whetstone>;
    @:allow(whet.Whet) final postInitTrigger:FutureTrigger<Noise>;

    public function new(config:WhetProjectConfig) {
        this.config = config;
        if (config.id == null) config.id = StringTools.replace(config.name, ' ', '-').toLowerCase();
        postInit = postInitTrigger = Future.trigger();
        // stones = new Map();
        commands = new Map();
        commandsMeta = [];
        addCommands(this);
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

    // public function stone<T:Whetstone>(cls:Class<T>):T return
    //     cast stones.get(WhetstoneID.fromClass(cast cls)); // Not sure why we need to cast the cls.
    // public function stoneByID(id:WhetstoneID) return stones.get(id);
    // @:allow(whet.Whetstone) function add(stone:Whetstone, id:WhetstoneID):WhetstoneID {
    //     var uniqueId = Utils.makeUniqueString(id, id -> stones.exists(id));
    //     stones.set(uniqueId, stone);
    //     return uniqueId;
    // }

}

typedef WhetProjectConfig = {

    var name:String;
    @:optional var id:String;
    @:optional var description:String;

}

typedef CommandMetadata = {

    var fnc:Function;
    var names:Array<String>;
    var description:String;

}
