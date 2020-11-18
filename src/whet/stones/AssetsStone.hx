package whet.stones;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import whet.Whetstone;

class AssetsStone extends Whetstone {

    public var config:AssetsConfig;

    public function new(project:WhetProject, id:WhetstoneID = null, config:AssetsConfig = null) {
        super(project, id);
        this.config = config != null ? config : {};
    }

    /**
     * Add a file/directory to assets.
     * @param src   Source file or directory. If a directory, all files inside, recursively, will be available.
     * @param serve Serving destination. Must be a directory if source is a directory,
     *              otherwise directory assumes the same assets name or pass in custom name.
     */
    public function addPath(src:SourceId, serve:SourceId):AssetsStone {
        if (!src.isDir() && serve.isDir())
            serve.withExt = src.withExt;
        if (src.isDir() && !serve.isDir()) Whet.error('If source is a directory, serve destination must be too.');
        config.files.set(src, serve);
        return this;
    }

    /** Lists all files currently available under the supplied dir. */
    public function list(dir:SourceId):Array<SourceId> {
        var files:Array<SourceId> = [];
        for (src => serve in config.files) {
            if (serve.isDir()) {
                var path = getRealPath(dir, src, serve);
                if (path != null) for (file in getFilesFrom(path))
                    files.push(Path.join([serve, dir, file]));
            }
        }
        return files;
    }

    function getFilesFrom(root:String):Array<String> {
        var arr = [];
        function search(dir:String, relativePath:String) {
            if (FileSystem.exists(dir)) {
                for (file in FileSystem.readDirectory(dir)) {
                    var filePath = Path.join([dir, file]);
                    if (FileSystem.isDirectory(filePath)) {
                        search(filePath, Path.join([relativePath, file]));
                    } else {
                        arr.push(Path.join([relativePath, file]));
                    }
                }
            }
        }
        search(root, ".");
        return arr.map(p -> Path.normalize(p));
    }

    override function findStone(id:SourceId):Whetstone {
        var routeResult = super.findStone(id);
        if (routeResult != null) return routeResult;
        for (src => serve in config.files) {
            var path = null;
            if (serve.isDir()) {
                path = getRealPath(id, src, serve);
            } else { // not a dir
                if (id == serve) path = src;
            }
            if (path != null && FileSystem.exists(path)) {
                return new FileStone(project, path);
            }
        }
        return null;
    }

    function getRealPath(id:SourceId, src:SourceId, serve:SourceId):String {
        var rel = id.relativeTo(serve);
        if (rel != null) return src.toRelPath() + rel.toRelPath();
        else return null;
    }

}

@:structInit class AssetsConfig {

    public var files:Map<SourceId, SourceId> = [];

}
