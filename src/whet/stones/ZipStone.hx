package whet.stones;

class ZipStone extends FileWhetstone<ZipStoneConfig> {

    /** Print contents of this ZipStone to console. */
    @command public function print() {
        var files = config.sources.find('/').map(f -> f.serveId);
        files.sort((a, b) -> a.compare(b));
        Whet.msg('Contents of ${config.id}:');
        Whet.msg(files.join('\n'));
    }

    override function generateHash():WhetSourceHash {
        return WhetSourceHash.merge(
            config.sources.getHashOfEverything(),
            WhetSourceHash.fromString((cast config.filename:String) + config.level)
        );
    }

    function generate(hash:WhetSourceHash):Array<WhetSourceData> {
        var files = config.sources.find('/');
        Whet.msg('Zipping ${files.length} files.');
        var entries = new List<haxe.zip.Entry>();
        for (file in files) {
            var data = file.get();
            var entry:haxe.zip.Entry = {
                fileName: file.serveId.toRelPath('/'),
                fileSize: data.data.length,
                fileTime: Date.fromTime(data.source.ctime * 1000),
                compressed: false,
                dataSize: data.data.length,
                data: data.data,
                crc32: haxe.crypto.Crc32.make(data.data)
            };
            entries.push(entry);
        }
        for (entry in entries) haxe.zip.Tools.compress(entry, config.level);
        var out = new haxe.io.BytesOutput();
        var w = new haxe.zip.Writer(out);
        w.write(entries);
        return [WhetSourceData.fromBytes(list()[0], out.getBytes())];
    }

    override function list():Array<SourceId> {
        return [config.filename];
    }

}

@:structInit class ZipStoneConfig extends WhetstoneConfig {

    public var sources:Router;
    public var filename:SourceId = 'data.zip';
    public var level:Int = 9;

}
