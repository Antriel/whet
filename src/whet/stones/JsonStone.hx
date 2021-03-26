package whet.stones;

import haxe.DynamicAccess;
import haxe.Json;

class JsonStone extends FileWhetstone<JsonConfig> {

    public var data:DynamicAccess<Dynamic> = {};

    public function addProjectData():JsonStone {
        data["name"] = config.project.config.name;
        data["id"] = config.project.config.id;
        data["description"] = config.project.config.description;
        return this;
    }

    public function mergeJson(path:SourceId):JsonStone {
        var obj:DynamicAccess<Dynamic> = Json.parse(sys.io.File.getContent(path.toRelPath(project)));
        for (field => val in obj) data[field] = val;
        return this;
    }

    function content() return Json.stringify(data, null, '  ');

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        return [WhetSourceData.fromString(config.filename, content())];
    }

    override function generateHash():WhetSourceHash {
        return WhetSourceHash.fromString(content());
    }

    override function list():Array<SourceId> return [config.filename];

}

@:structInit class JsonConfig extends WhetstoneConfig {

    public var filename:SourceId = 'data.json';

}
