import utest.Assert;
import utest.Test;
import whet.SourceId;
import whet.WhetSource.WhetSourceData;
import whet.Whetstone;
import whet.route.Router;

class TestRouter extends Test {

    public function testSimple() {
        var r = new Router([
            '/a' => new DummyStone({ contents: Simple('A') }),
            '/b' => new DummyStone({ contents: Simple('B') }),
        ]);
        Assert.equals(1, r.find('a').length);
        Assert.equals('a', r.find('a')[0].serveId.toRelPath());
        Assert.equals('data', r.find('a')[0].sourceId.toRelPath());
        Assert.equals('A', r.find('a')[0].get().data.toString());
        Assert.equals('B', r.find('b')[0].get().data.toString());
        Assert.equals(0, r.find('c').length);
    }

    public function testSimpleServeUnder() {
        var r = new Router([
            '/' => new DummyStone({ contents: Simple('A') }),
            'foo/' => [
                new DummyStone({ contents: Simple('B') }),
                new DummyStone({ contents: Simple('C') })
            ],
            'bar/baz/' => [
                new DummyStone({ contents: Simple('D') }),
                new DummyStone({ contents: Simple('E') })
            ],
            'foobar/foodata' => new DummyStone({ contents: Simple('F') })
        ]);
        Assert.equals(1, r.find('/data').length);
        Assert.equals('A', r.find('/data')[0].get().data.toString());
        Assert.equals(2, r.find('/foo/').length);
        Assert.equals(1, r.find('/foo/data').length);
        Assert.equals(2, r.find('/foo/data', false).length);
        Assert.equals(0, r.find('/c').length);
        Assert.equals(2, r.find('bar/').length);
        Assert.equals("baz/", r.find('bar/')[0].serveId.dir.toRelPath());
        Assert.equals(1, r.find('foobar/').length);
        Assert.equals("foodata", r.find('foobar/')[0].serveId.toRelPath());
    }

    public function testDirServe() {
        var r = new Router([
            '/foo/' => new DummyStone({ contents: Arr(['a', 'b', 'c'], '/bar/') }),
            '/foobar/' => [new DummyStone({ contents: Arr(['a', 'b', 'c'], '/bar/') }) => '/bar/'],
        ]);
        Assert.equals(3, r.find('/foo/').length);
        Assert.equals(3, r.find('/foobar/').length);
        Assert.equals('item0', r.find('/foobar/')[0].serveId.toRelPath());
    }

    // public function testDynamic() {
    //     var a = new Whetstone(p);
    //     var r:WhetSourceRouter = ([
    //         'replay' => a,
    //     ]:Map<SourceId, Whetstone>);
    //     a.routeDynamic = path -> {
    //         Assert.equals('/logic/1', path);
    //         null;
    //     }
    //     Assert.equals(null, r.find('/replay/logic/1'));
    //     var onlyOnce = true;
    //     a.routeDynamic = path -> {
    //         if (path.asDir().toRelPath().split('/').length != 3) return a.findStone(path.asDir() + '1');
    //         if (!path.isDir()) return a.findStone(path.asDir());
    //         Assert.isTrue(onlyOnce);
    //         onlyOnce = false;
    //         return new Whetstone(p, path.toRelPath().split('/')[1]);
    //     }
    //     Assert.equals('1', r.find('/replay/logic').id);
    //     Assert.equals('1', r.find('/replay/logic/').id);
    //     Assert.equals('1', r.find('/replay/logic/1').id);
    //     Assert.equals('1', r.find('/replay/logic/1/').id);
    //     onlyOnce = true;
    //     Assert.equals('2', r.find('/replay/logic/2').id);
    // }

}

class DummyStone extends Whetstone<DummyStoneConfig> {

    function generate(hash) return switch config.contents {
        case Simple(data): [WhetSourceData.fromString('data', data)];
        case Arr(data, dir): [for (i => item in data) WhetSourceData.fromString('$dir/item$i', item)];
    }

}

@:structInit class DummyStoneConfig extends WhetstoneConfig {

    public var contents:DummyContent;

}

enum DummyContent {

    Simple(data:String);
    Arr(data:Array<String>, dir:SourceId);

}
