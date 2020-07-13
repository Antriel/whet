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

}
