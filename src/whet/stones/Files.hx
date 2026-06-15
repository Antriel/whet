package whet.stones;

import whet.cache.HashCache;
import whet.magic.MaybeArray.makeArray;

class Files extends Stone<FilesConfig> {

    /** Reuse an existing Files stone for this path, or create a new one. */
    public static function fromPath(path:String):Files {
        final project = Project.projects[Project.projects.length - 1];
        if (project != null) {
            for (stone in project.stones) {
                if (stone.id == path && Std.isOfType(stone, Files)) return cast stone;
            }
        }
        return new Files({ paths: [path] });
    }

    override function initConfig() {
        this.config.recursive ??= true;
        this.config.id ??= makeArray(this.config.paths)[0];
    }

    override function generateHash():Promise<SourceHash> {
        var hashCache = HashCache.get();
        return walk(
            (path) -> hashCache.getFileHash(cwdPath(path)),
            (dir, dirFile) -> hashCache.getFileHash(dirFile)
        ).then(hashProms -> cast Promise.all(hashProms))
            .then((hashes:Array<SourceHash>) -> SourceHash.merge(...hashes));
    }

    override function list():Promise<Null<Array<SourceId>>> {
        return walk(
            (path) -> path.withExt,
            (dir, dirFile) -> fromCwd(dirFile, dir).id
        );
    }

    override function generate(hash:SourceHash):Promise<Array<SourceData>> {
        return walk(
            (path) -> SourceData.fromFile(path.withExt, cwdPath(path), path),
            (dir, dirFile) -> {
                var p = fromCwd(dirFile, dir);
                SourceData.fromFile(p.id, dirFile, p.pathId);
            }
        ).then(fileProms -> cast Promise.all(fileProms));
    }

    override function generatePartial(sourceId:SourceId, hash:SourceHash):Promise<Null<Array<SourceData>>> {
        // Resolve the requested id back to its file via the same listing walk() uses, then read
        // ONLY that file — instead of falling back to generate(), which reads the whole directory.
        return walk(
            (path) -> { id: (path.withExt:SourceId), cwd: (cwdPath(path):String), pathId: (path:SourceId) },
            (dir, dirFile) -> {
                var p = fromCwd(dirFile, dir);
                { id: p.id, cwd: (dirFile:String), pathId: p.pathId };
            }
        ).then(entries -> {
            var match = Lambda.find(entries, e -> e.id == sourceId);
            if (match == null) return cast Promise.resolve(null);
            return cast SourceData.fromFile(match.id, match.cwd, match.pathId).then(sd -> [sd]);
        });
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
            id: dir == '/' ? pathId : pathId.getRelativeTo(dir)
        }
    }

}

typedef FilesConfig = StoneConfig & {

    /** Can be either a file, or a directory. */
    var paths:MaybeArray<SourceId>;

    /** Whether to recurse directories. Defaults to `true`. */
    @:optional var recursive:Bool;

}
