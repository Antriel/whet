package whet.stones;

import haxe.DynamicAccess;
import haxe.Json;

class JsonStone extends Whetstone<JsonConfig> {

    public var data:DynamicAccess<Dynamic> = {};

    public function new(config:JsonConfig = null) {
        if (config == null) config = {};
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultFileStrategy;
        super(config);
    }

    public function addProjectData(project:WhetProject):JsonStone {
        data["name"] = project.config.name;
        data["id"] = project.config.id;
        data["description"] = project.config.description;
        return this;
    }

    public function mergeJson(path:String):JsonStone {
        var obj:DynamicAccess<Dynamic> = Json.parse(sys.io.File.getContent(path));
        for (field => val in obj) data[field] = val;
        return this;
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        return [WhetSourceData.fromString(config.filename, Json.stringify(data, null, '  '))];
    }

    override function getHash():WhetSourceHash {
        return WhetSourceHash.fromString(Json.stringify(data));
    }

}

@:structInit class JsonConfig extends WhetstoneConfig {

    public var filename:SourceId = 'data.json';

}
