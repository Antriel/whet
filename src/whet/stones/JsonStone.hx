package whet.stones;

import haxe.DynamicAccess;
import whet.magic.MaybeArray.makeArray;
import whet.magic.RouteType.makeRoute;

class JsonStone extends Stone<JsonStoneConfig> {

    public var data:DynamicAccess<Dynamic> = {};

    public function addProjectData():JsonStone {
        data["name"] = project.name;
        data["id"] = project.id;
        data["description"] = project.description;
        return this;
    }

    public function addMergeFiles(files:MaybeArray<RouteType>):JsonStone {
        config.mergeFiles = makeArray(config.mergeFiles).concat(makeArray(files));
        return this;
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        var obj:DynamicAccess<Dynamic> = { }
        for (field => val in data) obj[field] = val; // Copy our data first.
        return Promise.all(makeArray(config.mergeFiles).map(rt -> makeRoute(rt).getData()))
            .then((dataArr:Array<Array<SourceData>>) -> {
                for (data in dataArr) for (d in data) {
                    var file:DynamicAccess<Dynamic> = haxe.Json.parse(d.data.toString());
                    for (field => val in file) obj[field] = val;
                }
                return [SourceData.fromString(config.name, haxe.Json.stringify(obj, null, '  '))];
            });
    }

    override function generateHash():Promise<SourceHash> {
        return Promise.all(makeArray(config.mergeFiles).map(rt -> makeRoute(rt).getHash()))
            .then((hashes:Array<SourceHash>) -> {
                hashes.push(SourceHash.fromString(haxe.Json.stringify(data)));
                return SourceHash.merge(...hashes);
            });
    }

    override function list():Promise<Array<SourceId>>
        return Promise.resolve([(config.name:SourceId)]);

    override function initConfig() {
        if (config.name == null) config.name = 'data.json';
        if (config.mergeFiles == null) config.mergeFiles = [];
        super.initConfig();
    }

}

typedef JsonStoneConfig = StoneConfig & {

    public var ?name:String;
    public var ?mergeFiles:MaybeArray<RouteType>;

}
