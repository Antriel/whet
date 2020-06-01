package whet.stones;

import haxe.DynamicAccess;
import haxe.Json;
import whet.Whetstone;

class JsonStone extends Whetstone {

    public var data:DynamicAccess<Dynamic> = {};

    public function new(project:WhetProject, id:WhetstoneID = null) {
        if (id == null) id = project.config.id;
        super(project, id, CacheManager.defaultFileStrategy);
    }

    public function addProjectData():JsonStone {
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

    override function generateSource():WhetSource {
        return WhetSource.fromString(this, Json.stringify(data, null, '  '), null);
    }

}
