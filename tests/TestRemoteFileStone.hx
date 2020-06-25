import whet.stones.RemoteFileStone;
import whet.WhetProject;
import utest.Assert;
import utest.Test;

class TestRemoteFileStone extends Test {

    public static var counter:Int = 0;

    public function testSimpleCache() {
        var p = new WhetProject({ name: 'test' });
        var remoteFile = new RemoteFileStone(p, 'foobar');
        var source = remoteFile.getSource();
        var source2 = remoteFile.getSource();
        Assert.equals(0, source.data.compare(source2.data));
    }

}
