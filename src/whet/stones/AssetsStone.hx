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

    /**
     * Add a file/directory to assets.
     * @param src   Source file or directory. If a directory, all files inside, recursively, will be available.
     * @param serve Serving destination. Must be a directory if source is a directory,
     *              otherwise directory assumes the same assets name or pass in custom name.
     */
    public function add(src:SourceId, serve:SourceId):AssetsStone {
        if (!src.isDir() && serve.isDir())
            serve.withExt = src.withExt;
        if (src.isDir()) if (!serve.isDir()) Whet.error('If source is a directory, serve destination must be too.');

        config.routes.push({
            src: src,
            serve: serve
        });
        return this;
    }

    override function getSource(id:SourceId):WhetSource {
        for (source in config.sources) {
            var found = source.getSource(id);
            if (found != null) return found;
        }
        for (route in config.routes) {
            var path = null;
            if (route.serve.isDir()) {
                if (id.isInDir(route.serve)) {
                    path = (route.src:String).substring(1) // Remove start slash -> make relative to CWD.
                        + (id:String).substring((route.serve:String).length);
                }
            } else { // not a dir
                if (id == route.serve) path = route.src;
            }
            if (path != null && FileSystem.exists(path)) {
                var data = File.getBytes(path);
                return {
                    data: data,
                    length: data.length
                }
            }
        }
        return null;
    }

}

@:structInit class AssetsConfig {

    public var sources:Array<Whetstone> = [];
    public var routes:Array<Routing> = [];

}

typedef Routing = {

    src:SourceId,
    serve:SourceId

}
#end
