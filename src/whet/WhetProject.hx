package whet;

import whet.Whetstone;

class WhetProject {

    public final config:WhetProjectConfig;
    public final stones:Map<WhetstoneID, Array<Whetstone>>;
    public final commands:Map<String, String->Void>;

    public function new(config:WhetProjectConfig) {
        this.config = config;
        if (config.id == null) config.id = StringTools.replace(config.name, ' ', '-').toLowerCase();
        stones = new Map();
        commands = new Map();
        var fields = Type.getInstanceFields(Type.getClass(this));
        for (origField in Type.getInstanceFields(WhetProject)) fields.remove(origField);
        fields = fields.filter(f -> Reflect.isFunction(Reflect.field(this, f)));
        for (f in fields) commands.set(f, function(arg)
            Reflect.callMethod(this, Reflect.field(this, f), [arg])); // TODO deduplicate with whetstone?
    }

}

typedef WhetProjectConfig = {

    var name:String;
    @:optional var id:String;
    @:optional var description:String;

}
