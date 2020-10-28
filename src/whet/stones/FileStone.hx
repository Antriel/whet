package whet.stones;

import sys.FileSystem;
import whet.Whetstone;

class FileStone extends Whetstone {

    final filePath:String;

    public function new(project:WhetProject, filePath:String) {
        super(project, filePath);
        this.filePath = filePath;
    }

    override function generateSource():WhetSource {
        return WhetSource.fromFile(this, filePath, null);
    }

}

class AsyncFileStone extends Whetstone {

    final filePath:String;
    final parent:Whetstone;

    public function new(parent:Whetstone, filePath:String) {
        super(parent.project, filePath);
        this.parent = parent;
        this.filePath = filePath;
    }

    override function generateSource():WhetSource {
        if (!FileSystem.exists(filePath)) parent.getSource();
        return WhetSource.fromFile(this, filePath, null);
    }

}
