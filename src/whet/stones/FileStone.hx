package whet.stones;

import whet.Whetstone;

class FileStone extends Whetstone {

    final filePath:String;

    public function new(project:WhetProject, filePath:String) {
        super(project);
        this.filePath = filePath;
    }

    override function generateSource():WhetSource {
        return WhetSource.fromFile(filePath, null);
    }

}
