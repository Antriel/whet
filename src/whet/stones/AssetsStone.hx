package whet.stones;

import whet.Whetstone;
#if tink_io
import tink.io.Source;

class AssetsStone extends Whetstone {

    public var config:AssetsConfig;

    public function new(project:WhetProject, config:AssetsConfig = null) {
        super(project);
        this.config = config;
    }

    override function getSource(id:SourceId):WhetSource {
        for (source in config.sources) {
            var found = source.getSource(id);
            if (found != null) return found;
        }
        return null;
    }

}

@:structInit class AssetsConfig {

    public var sources:Array<Whetstone> = [];

}
#end
