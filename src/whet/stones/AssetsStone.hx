package whet.stones;

import sys.FileSystem;
import sys.io.File;
import whet.Whetstone;
#if tink_io
import tink.io.Source;

class AssetsStone extends Whetstone {

    public var config:AssetsConfig;

    public function new(project:WhetProject, config:AssetsConfig = null) {
        super(project);
        this.config = config == null ? { } : config;
    }

    public function addStaticFiles(srcDir:SourceId, serveDir:SourceId):AssetsStone {
        if (!srcDir.isDir()) throw 'Source directory "$srcDir" is not a directory';
        if (!serveDir.isDir()) throw 'Serve directory "$serveDir" is not a directory';
        config.staticDirs.push({
            src: srcDir,
            serve: serveDir
        });
        return this;
    }

    override function getSource(id:SourceId):WhetSource {
        for (source in config.sources) {
            var found = source.getSource(id);
            if (found != null) return found;
        }
        for (route in config.staticDirs) {
            if (id.isInDir(route.serve)) {
                var realPath = getRealPath(id, route);
                if (FileSystem.exists(realPath)) {
                    var data = File.getBytes(realPath);
                    return {
                        data: data,
                        length: data.length
                    }
                }
            }
        }
        return null;
    }

    function getRealPath(file:SourceId, route:DirRouting):String {
        return (route.src:String).substring(1) // Remove start slash -> make relative to CWD.
            + (file:String).substring((route.serve:String).length);
    }

}

@:structInit class AssetsConfig {

    public var sources:Array<Whetstone> = [];
    public var staticDirs:Array<DirRouting> = [];

}

typedef DirRouting = {

    src:SourceId,
    serve:SourceId

}
#end
