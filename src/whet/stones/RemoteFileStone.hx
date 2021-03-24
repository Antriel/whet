package whet.stones;

import whet.Whetstone;

class RemoteFileStone extends Whetstone<RemoteFileStoneConfig> {

    public function new(config) {
        if (config.cacheStrategy == null) config.cacheStrategy = InFile(KeepForever);
        super(config);
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        // TODO should support non string files too. Should be async. Etc...
        trace('Downloading ${config.url}.');
        #if tests
        var file = '' + TestRemoteFileStone.counter++;
        #else
        #if nodejs
        // Temporary hack...
        var file = js.node.ChildProcess.execFileSync('curl', ['--silent', '-L', config.url], {
            encoding: 'utf8',
            maxBuffer: (cast Math.POSITIVE_INFINITY:Int)
        });
        #else
        var file = haxe.Http.requestUrl(config.url);
        #end
        #end
        return [WhetSourceData.fromString(urlToFilename(config.url), file)];
    }

    override function list():Array<SourceId> return [urlToFilename(config.url)];

    override public function getHash():WhetSourceHash {
        return WhetSourceHash.fromString(config.url);
    }

    static function urlToFilename(url:String):String {
        return url.split('/').pop().split('?')[0];
    }

}

@:structInit class RemoteFileStoneConfig extends WhetstoneConfig {

    public var url:String;

}
