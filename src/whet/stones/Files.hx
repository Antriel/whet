package whet.stones;

import whet.magic.MaybeArray.makeArray;

class Files extends Stone<FilesConfig> {

    override function initConfig() {
        this.config.recursive = true;
    }

    override function list():Promise<Array<SourceId>> { // TODO deduplicate
        var paths = [for (path in makeArray(config.paths)) {
            if (path.isDir()) {
                Utils.listDirectoryFiles(cwdPath(path), config.recursive).then(arr -> arr.map(file -> {
                    // `file` is CWD relative.
                    var pathId = (file:SourceId).fromCwdPath(project);
                    pathId.getRelativeTo(path);
                }));
            } else {
                Promise.resolve([path.withExt]);
            }
        }];
        return Promise.all(paths).then(allPaths -> Lambda.flatten(allPaths));
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        var sources:Array<Promise<Array<SourceData>>> = [for (path in makeArray(config.paths)) {
            if (path.isDir()) {
                Utils.listDirectoryFiles(cwdPath(path), config.recursive).then(arr -> [
                    for (file in arr) { // `file` is CWD relative.
                        var pathId = (file:SourceId).fromCwdPath(project);
                        var id = pathId.getRelativeTo(path);
                        SourceData.fromFile(id, file, pathId);
                    }
                ]).then(f -> (cast Promise.all(f):Promise<Array<SourceData>>));
            } else {
                SourceData.fromFile(path.withExt, cwdPath(path), path).then(src -> [src]);
            }
        }];
        return Promise.all(sources).then(allSources -> Lambda.flatten(allSources));
    }

}

typedef FilesConfig = StoneConfig & {

    /** Can be either a file, or a directory. */
    var paths:MaybeArray<SourceId>;

    /** Whether to recurse directories. Defaults to `true`. */
    @:optional var recursive:Bool;

}
