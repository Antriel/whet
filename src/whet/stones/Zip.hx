package whet.stones;

import js.node.Buffer;

class ZipStone extends Stone<ZipConfig> {

    override function initConfig() {
        if (config.filename == null) config.filename = 'data.zip';
        if (config.level == null) config.level = 9;
        /** Keep last used 5 for a day and last used 1 indefinitely. */
        if (config.cacheStrategy == null) config.cacheStrategy = InFile(Any([
            LimitCountByLastUse(1),
            All([MaxAge(24 * 60 * 60), LimitCountByLastUse(5)])
        ]), AllOnUse);
    }

    override function generateHash():Promise<SourceHash> {
        return config.sources.getHash().then(hash -> {
            SourceHash.fromString(config.filename + config.level).add(hash);
        });
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        Log.info('Zipping files.');
        final level = config.level;
        return config.sources.get().then(files -> {
            Promise.all([for (file in files) file.get().then(data -> {
                final bytes = data.data.hxToBytes();
                final entry:haxe.zip.Entry = {
                    fileName: file.serveId.toCwdPath('./'),
                    fileSize: data.data.length,
                    fileTime: Date.fromTime(data.source.ctime * 1000),
                    compressed: false,
                    dataSize: data.data.length,
                    data: bytes,
                    crc32: haxe.crypto.Crc32.make(bytes)
                };
                haxe.zip.Tools.compress(entry, level);
                return entry;
            })]).then(entries -> {
                var out = new haxe.io.BytesOutput();
                var w = new haxe.zip.Writer(out);
                w.write(Lambda.list(entries));
                return [SourceData.fromBytes(config.filename, Buffer.hxFromBytes(out.getBytes()))];
            });
        });
    }

    override function list():Promise<Null<Array<SourceId>>> {
        return Promise.resolve([(config.filename:SourceId)]);
    }

}

typedef ZipConfig = StoneConfig & {

    var sources:Router;
    /* Defaults to `'data.zip'`. */
    var ?filename:String;
    /* Zip compression level. Defaults to 9. */
    var ?level:Int;

}
