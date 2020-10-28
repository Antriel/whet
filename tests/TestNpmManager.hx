import sys.FileSystem;
import utest.Assert;
import utest.Test;
import whet.npm.NpmManager;

class TestNpmManager extends Test {

    public function testSimple() {
        NpmManager.assureInstalled("left-pad", "1.1.3");
        Assert.isTrue(NpmManager.isInstalled("left-pad", "1.1.3"));
        Assert.isTrue(FileSystem.exists(NpmManager.NODE_MODULES));
        Assert.isTrue(FileSystem.exists(NpmManager.NODE_MODULES + '/left-pad'));
    }

}
