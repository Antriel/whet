package whet.stones;

import sys.FileSystem;

class FileStone extends Whetstone<FileStoneConfig> {

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        return [for (path in config.paths) {
            if (path.isDir()) {
                for (file in FileSystem.readDirectory(path)) {
                    var filepath = (file:SourceId).getPutInDir(path);
                    WhetSourceData.fromFile(filepath.relativeTo(path), filepath);
                }
            } else WhetSourceData.fromFile(path.withExt, path);
        }];
    }
    // TODO should also support nested directories and being able to configure what the sourceId will include.

}

@:structInit class FileStoneConfig extends WhetstoneConfig {

    /** Can be either a file, or a directory that won't be recursed. */
    public var paths:Array<SourceId>; // TODO support glob patterns, or regex or something.

}

// class AsyncFileStone extends Whetstone {
//     final filePath:String;
//     final parent:Whetstone;
//     public function new(parent:Whetstone, filePath:String) {
//         super(parent.project, filePath);
//         this.parent = parent;
//         this.filePath = filePath;
//     }
//     override function generateSource():WhetSource {
//         if (!FileSystem.exists(filePath)) parent.getSource();
//         return WhetSource.fromFile(this, filePath, null);
//     }
// }
