package whet;

import whet.Whetstone;

class WhetProject {

    public final config:WhetProjectConfig;
    public final commands:Map<String, String->Void>;

    final stones:Map<WhetstoneID, Whetstone>;

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

    public function stone<T:Whetstone>(cls:Class<T>):T return
        cast stones.get(WhetstoneID.fromClass(cast cls)); // Not sure why we need to cast the cls.

    public function stoneByID(id:WhetstoneID) return stones.get(id);

    @:allow(whet.Whetstone) function add(stone:Whetstone, id:WhetstoneID):WhetstoneID {
        var uniqueId = id;
        var counter = 1;
        while (stones.exists(uniqueId))
            uniqueId = (id:String) + ++counter;
        stones.set(uniqueId, stone);
        return uniqueId;
    }

}

typedef WhetProjectConfig = {

    var name:String;
    @:optional var id:String;
    @:optional var description:String;

}
