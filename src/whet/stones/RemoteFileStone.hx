package whet.stones;

import whet.Whetstone;

class RemoteFileStone extends Whetstone {

    final url:String;

    public function new(project:WhetProject, url:String, id:WhetstoneID = null) {
        this.url = url;
        super(project, id, CacheManager.defaultFileStrategy);
        defaultFilename = urlToFilename(url);
    }

    override function generateSource():WhetSource {
        // TODO should support non string files too. Should be async. Etc...
        trace('Downloading $url.');
        #if tests
        var file = '' + TestRemoteFileStone.counter++;
        #else
        #if nodejs
        var file = null;
        throw "Not implemented.";
        #else
        var file = haxe.Http.requestUrl(url);
        #end
        #end
        return WhetSource.fromString(this, file, getHash());
    }

    override public function getHash():WhetSourceHash {
        return WhetSourceHash.fromString(url);
    }

    static function urlToFilename(url:String):String {
        return url.split('/').pop().split('?')[0];
    }

}
