import haxe.iterators.MapKeyValueIterator;
import haxe.ds.Map;
import whet.Whetstone;
import whet.WhetProject;
import utest.Assert;
import utest.Test;
import whet.WhetSourceRouter;
import whet.SourceId;

class TestRouter extends Test {

    var p:WhetProject;

    public function setup() {
        p = new WhetProject({ name: 'test' });
    }

    public function testSimple() {
        var a = new Whetstone(p, 'A');
        var b = new Whetstone(p, 'B');
        var r:WhetSourceRouter = ([
            '/a' => a,
            '/b' => b,
        ]:Map<SourceId, Whetstone>);
        Assert.equals('A', r.find('/a').id);
        Assert.equals('B', r.find('/b').id);
        Assert.equals(null, r.find('/c'));
    }

    public function testNested() {
        var a = new Whetstone(p, 'A');
        a.route([
            'b' => new Whetstone(p, 'B')
        ]);
        var r:WhetSourceRouter = ([
            'a' => a,
        ]:Map<SourceId, Whetstone>);
        Assert.equals('A', r.find('/a').id);
        Assert.equals('B', r.find('/a/b').id);
        Assert.equals(null, r.find('/c'));
    }

    public function testDynamic() {
        var a = new Whetstone(p);
        var r:WhetSourceRouter = ([
            'replay' => a,
        ]:Map<SourceId, Whetstone>);
        a.routeDynamic = path -> {
            Assert.equals('/logic/1', path);
            null;
        }
        Assert.equals(null, r.find('/replay/logic/1'));
        var onlyOnce = true;
        a.routeDynamic = path -> {
            if (path.asDir().toRelPath().split('/').length != 3) return a.findStone(path.asDir() + '1');
            if (!path.isDir()) return a.findStone(path.asDir());
            Assert.isTrue(onlyOnce);
            onlyOnce = false;
            return new Whetstone(p, path.toRelPath().split('/')[1]);
        }
        Assert.equals('1', r.find('/replay/logic').id);
        Assert.equals('1', r.find('/replay/logic/').id);
        Assert.equals('1', r.find('/replay/logic/1').id);
        Assert.equals('1', r.find('/replay/logic/1/').id);
        onlyOnce = true;
        Assert.equals('2', r.find('/replay/logic/2').id);

    }

}
