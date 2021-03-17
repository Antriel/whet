import utest.Assert;
import utest.Test;
import whet.WhetProject;
import whet.WhetSource;
import whet.WhetSourceHash;
import whet.Whetstone;
import whet.cache.CacheManager;

class TestMultiData extends Test {

    public function testBasics() {
        var sub = new MultiStone({ vals: ['a', 'b', 'c'] });
        var s1 = sub.getSource();
        Assert.isTrue(s1.hash.equals(sub.getSource().hash));
        sub.config.vals = ['1', '2', '3'];
        var s2 = sub.getSource();
        Assert.isTrue(s1 != s2);
        sub.config.vals = ['a', 'b', 'c'];
        Assert.isTrue(s1.hash.equals(sub.getSource().hash));
        Assert.equals('2', s2.get('sub/sub1').data.toString());
    }

    public function testRouting() {
        var sub = new MultiStone({ vals: ['a', 'b', 'c'] });
        // TODO:
        // p.route([
        //     'all.csv' => sub,
        //     'subs/' => [sub, 'sub/']
        //     'first' => [sub, 'sub/sub0']
        // ]);
        // p.find('all.csv') == "a, b, c"
        // p.find('first') == "a"
        // p.find('subs/sub1') == "b"
        // new WhetSourceRouter(['subs/ => [sub, 'sub/]]).getAll().length == 3
    }

}

class MultiStone extends Whetstone<MultiStoneConfig> {

    public function new(config:MultiStoneConfig) {
        if (config.cacheStrategy == null) config.cacheStrategy = CacheManager.defaultFileStrategy;
        super(config);
    }

    override function getHash():WhetSourceHash {
        return WhetSourceHash.merge(...config.vals.map(v -> WhetSourceHash.fromString(v)));
    }

    function generate(hash):Array<WhetSourceData> {
        var data = [WhetSourceData.fromString('all.csv', config.vals.join(', '))];
        for (i => v in config.vals) {
            data.push(WhetSourceData.fromString('sub/sub$i', v));
        }
        return data;
    }

}

@:structInit class MultiStoneConfig extends WhetstoneConfig {

    public var vals:Array<String>;

}
