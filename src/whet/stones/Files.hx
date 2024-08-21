package whet.stones;

import whet.magic.MaybeArray.makeArray;

class Files extends Stone<FilesConfig> {

    override function initConfig() {
        this.config.recursive ??= true;
    }

    override function list():Promise<Array<SourceId>> {
        return walk(
            (path) -> path.withExt,
            (dir, dirFile) -> fromCwd(dirFile, dir).id
        );
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        return walk(
            (path) -> SourceData.fromFile(path.withExt, cwdPath(path), path),
            (dir, dirFile) -> {
                var p = fromCwd(dirFile, dir);
                SourceData.fromFile(p.id, dirFile, p.pathId);
            }
        ).then(fileProms -> cast Promise.all(fileProms));
    }

    inline function walk<T>(onFile:SourceId->T, onDirFile:SourceId->SourceId->T):Promise<Array<T>> {
        var files:Array<T> = [];
        var dirs = [];
        for (path in makeArray(config.paths)) {
            if (path.isDir()) {
                dirs.push(Utils.listDirectoryFiles(cwdPath(path), config.recursive).then(arr -> for (file in arr) {
                    files.push(onDirFile(path, file));
                }));
            } else {
                files.push(onFile(path));
            }
        }
        return Promise.all(dirs).then(_ -> files);
    }

    inline function fromCwd(file:SourceId, dir:SourceId) {
        var pathId = (file:SourceId).fromCwdPath(project); // `file` is CWD relative.
        return {
            pathId: pathId,
            id: pathId.getRelativeTo(dir)
        }
    }

}

typedef FilesConfig = StoneConfig & {

    /** Can be either a file, or a directory. */
    var paths:MaybeArray<SourceId>;

    /** Whether to recurse directories. Defaults to `true`. */
    @:optional var recursive:Bool;

}
