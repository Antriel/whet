package whet.stones;

import haxe.DynamicAccess;
import whet.magic.RoutePathType;

class JsonStone extends Stone<JsonStoneConfig> {

    public var data:DynamicAccess<Dynamic> = {};

    public function addProjectData():JsonStone {
        data["name"] = project.name;
        data["id"] = project.id;
        data["description"] = project.description;
        return this;
    }

    override function generate(hash:SourceHash):Promise<Array<SourceData>> {
        var obj:DynamicAccess<Dynamic> = { }
        for (field => val in data) obj[field] = val; // Copy our data first.
        return config.mergeFiles.get().then(list -> Promise.all(list.map(r -> r.get())))
            .then(dataArr -> {
                for (data in dataArr) {
                    var file:DynamicAccess<Dynamic> = haxe.Json.parse(data.data.toString());
                    for (field => val in file) obj[field] = val;
                }
                return [SourceData.fromString(config.name, haxe.Json.stringify(obj, null, '  '))];
            });
    }

    override function generateHash():Promise<SourceHash> {
        return config.mergeFiles.getHash().then(hash -> hash.add(SourceHash.fromString(haxe.Json.stringify(data))));
    }

    override function list():Promise<Null<Array<SourceId>>>
        return Promise.resolve([(config.name:SourceId)]);

    override function initConfig() {
        if (config.name == null) config.name = 'data.json';
        if (config.mergeFiles == null) config.mergeFiles = new Router();
        super.initConfig();
    }

}

typedef JsonStoneConfig = StoneConfig & {

    public var ?name:String;
    public var ?mergeFiles:Router;

}
