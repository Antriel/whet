package whet.stones;

import whet.magic.MaybeArray.makeArray;

class Files extends Stone<FilesConfig> {

    override function initConfig() {
        this.config.recursive = true;
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        var sources:Array<Promise<Array<SourceData>>> = [for (pathString in makeArray(config.paths)) {
            var path:SourceId = pathString;
            if (path.isDir()) {
                Utils.listDirectoryFiles(cwdPath(pathString), config.recursive).then(arr -> [
                    for (file in arr) { // `file` is CWD relative.
                        var pathId:SourceId = SourceId.fromCwdPath(file, project);
                        var id:SourceId = pathId.relativeTo(path);
                        SourceData.fromFile(cast id, file, cast pathId);
                    }
                ]).then(f -> (cast Promise.all(f):Promise<Array<SourceData>>));
            } else {
                SourceData.fromFile(path.withExt, cwdPath(cast path), cast path).then(src -> [src]);
            }
        }];
        return Promise.all(sources).then(allSources -> Lambda.flatten(allSources));
    }

}

typedef FilesConfig = StoneConfig & {

    /** Can be either a file, or a directory. */
    var paths:MaybeArray<String>;

    /** Whether to recurse directories. Defaults to `true`. */
    @:optional var recursive:Bool;

}
