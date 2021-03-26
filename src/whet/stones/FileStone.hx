package whet.stones;

import sys.FileSystem;

class FileStone extends Whetstone<FileStoneConfig> {

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        return [for (path in config.paths) {
            if (path.isDir()) {
                for (file in FileSystem.readDirectory(path.toRelPath(project))) {
                    var filepath = (file:SourceId).getPutInDir(path);
                    WhetSourceData.fromFile(filepath.relativeTo(path), filepath.toRelPath(project), filepath);
                }
            } else WhetSourceData.fromFile(path.withExt, path.toRelPath(project), path);
        }];
    }
    // TODO should also support nested directories and being able to configure what the sourceId will include.

}

@:structInit class FileStoneConfig extends WhetstoneConfig {

    /** Can be either a file, or a directory that won't be recursed. */
    public var paths:Array<SourceId>; // TODO support glob patterns, or regex or something.

}
