import utest.Assert;
import utest.Test;
import whet.WhetProject;
import whet.WhetSource;
import whet.WhetSourceHash;
import whet.Whetstone;
import whet.cache.CacheManager;

class TestSubStone extends Test {

    public function testSimpleCache() {
        var p = new WhetProject({ name: 'test' });
        var sub = new SubStone(p, { vals: ['a', 'b', 'c'] });
        var s1 = sub.getSource();
        // b1.get(); // Should throw?
        // b1.list(); // Array of Ids? Or some structure?
        // b1.get('a'); // Runtime value? Bytes? It shouldn't be another resource.
        // Actually, source should be just one, and we should make a router handle the getting of stuff.
        // And for stones needing other sources, we could use a router, which will make it all easier, decoupled, and flexible.
        // So we could pass in a router with correct routing/types/filtering.
        // And the router goes through the cache, so it all works out.
        // `list` could return the same structure with data being null, or not if it had to go through generation.
        // So list result is the same as generate result.
        // Do we even need the 'list' to not go through generation? It's just an optimization, and there might not be cases where it's
        // actually needed.
        Assert.isTrue(s1 == sub.getSource());
        sub.config.vals = ['1', '2', '3'];
        var s2 = sub.getSource();
        Assert.isTrue(s1 != s2);
        sub.config.vals = ['a', 'b', 'c'];
        Assert.isTrue(s1 == sub.getSource());

        // switch s2.structure {
        //     case Multi('/', rootSources):
        //         for (s in rootSources) switch s.structure {
        //             case Multi('sub/', subs): switch subs[1] {
        //                     case Single(data): Assert.equals('2', data.data.toString());
        //                     case _: Assert.fail();
        //                 }
        //             case _:
        //         }
        //     case _: Assert.fail();
        // }
        // TODO test routing, get root, get subs, etc.
    }

}

class SubStone extends Whetstone {

    public var config:SubStoneConfig;

    public function new(p:WhetProject, config:SubStoneConfig) {
        super(p, null, InMemory(KeepForever));
        this.config = config;
    }

    override function getHash():WhetSourceHash {
        return WhetSourceHash.merge(...config.vals.map(v -> WhetSourceHash.fromString(v)));
    }

    function generate():Array<WhetSourceData> {
        // TODO some way to get a folder to generate stuff in, without having to get and pass the hash.
        trace('generating');
        var data = [WhetSourceData.fromString('all.csv', config.vals.join(', '))];

        for (i => v in config.vals) {
            data.push(WhetSourceData.fromString('sub/sub$i', v));
        }
        return data;
        // return Multi('/', [
        //     Multi('sub/', [for (v in config.vals) Single(WhetSourceItem.fromString(v))]),
        //     Single(WhetSourceItem.fromString(this, config.vals.join('')))
        // ]);
    }

}

@:structInit class SubStoneConfig {

    public var vals:Array<String>;

}
