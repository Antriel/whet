package whet.stones;

import js.node.Buffer;
import js.node.Https;
import js.node.Path;
import js.node.url.URL;

class RemoteFile extends Stone<RemoteFileConfig> {

    override function initConfig() {
        if (config.cacheStrategy == null) config.cacheStrategy = InFile(KeepForever);
    }

    override function generate(hash:SourceHash):Promise<Array<SourceData>> {
        Log.info('Downloading file.', { url: config.url });
        #if tests
        var file = '' + TestRemoteFileStone.counter++;
        #else
        return new Promise((res, rej) -> get(config.url, res, rej));
        #end
    }

    function get(url:String, res, rej) {
        final req = Https.get(url, response -> {
            if (response.statusCode == 301 || response.statusCode == 302) {
                return get(response.headers.get('location'), res, rej);
            }
            if (response.statusCode < 200 || response.statusCode >= 300) {
                // Must consume response data to free up memory.
                response.resume();
                rej(new js.lib.Error('Error downloading file. ${response.statusCode} – ${response.statusMessage}'));
                return;
            }
            final bufs = [];
            response.on('data', d -> bufs.push(d));
            response.on('error', rej);
            response.on('end', function() {
                final data = Buffer.concat(bufs);
                res([SourceData.fromBytes(getId(), data)]);
            });
        });
        req.on('error', rej);
    }

    override function list():Promise<Null<Array<SourceId>>> return Promise.resolve([getId()]);

    override public function generateHash():Promise<SourceHash> {
        return Promise.resolve(SourceHash.fromString(config.url));
    }

    function getId():SourceId {
        return Path.basename(new URL(config.url).pathname);
    }

}

typedef RemoteFileConfig = StoneConfig & {

    var url:String;

}
