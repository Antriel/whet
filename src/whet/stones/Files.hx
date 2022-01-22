package whet.stones;

import js.node.Fs;
import sys.FileSystem;
import whet.magic.MaybeArray.makeArray;

class Files extends Stone<FilesConfig> {

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        for (pathString in makeArray(config.paths)) {
            var path:SourceId = pathString;
            return (if (path.isDir()) {
                new Promise((res, rej) -> Fs.readdir(path.toRelPath(project), (err, files) -> {
                    if (err != null) rej(err);
                    else res([for (file in files) {
                        var filepath = (file:SourceId).getPutInDir(path);
                        {
                            id: filepath.relativeTo(path),
                            pathId: filepath
                        }
                    }]);
                }));
            } else Promise.resolve([{
                id: (path.withExt:SourceId),
                pathId: path
            }]))
                .then((files:Array<{id:SourceId, pathId:SourceId}>) -> cast Promise.all([for (f in files)
                    SourceData.fromFile(f.id, f.pathId.toRelPath(project), f.pathId)])
                );
        }
        return null;
    }
    // TODO should also support nested directories and being able to configure what the sourceId will include.

}

typedef FilesConfig = StoneConfig & {

    /** Can be either a file, or a directory that won't be recursed. */
    var paths:MaybeArray<String>; // TODO support glob patterns, or regex or something.

}
