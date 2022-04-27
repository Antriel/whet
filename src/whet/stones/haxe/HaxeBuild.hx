package whet.stones.haxe;

import whet.magic.MaybeArray;

class HaxeBuild extends Stone<BuildConfig> {

    /** Build the given hxml. */
    public function build():Promise<Nothing> {
        return new Promise(function(res, rej) {
            final cwd = js.node.Path.join(js.Node.process.cwd(), project.rootDir.toRelPath('/'));
            var cmd = Lambda.flatten(config.hxml.getBuildArgs());
            cmd.unshift(if (config.useNpx) 'npx haxe' else 'haxe');
            cmd = cmd.map(c -> StringTools.replace(c, '"', '\\"'));
            js.node.ChildProcess.exec(cmd.join(' '), cast {
                cwd: cwd,
                windowsHide: true
            }, function(err, stdout, stderr) {
                if (err != null) rej(err);
                else res(null);
            });
        });
    }

    function generate(hash:SourceHash):Promise<Array<SourceData>> {
        if (config.hxml.isSingleFile()) {
            var pathId = config.hxml.getBuildExportPath();
            var path = pathId.toRelPath(project);
            // Clear the file, so if compilation fails, we don't serve old version.
            return Utils.deleteAll(path).then(_ -> build()).then(_ -> {
                SourceData.fromFile(pathId.withExt, path, pathId).then(file -> {
                    return [file];
                });
            }).catchError(err -> {
                Log.error("Error during Haxe build.", { error: err });
                null;
            });
        } else {
            throw new js.lib.Error('Cannot get source of a multi-file build. Not implemented yet.');
        }
    }

    override function getCommands():Array<commander.Command> {
        return [new commander.Command('build')
            .action(_ -> build())
        ];
    }

    override function list():Promise<Array<SourceId>> {
        if (config.hxml.isSingleFile()) {
            return Promise.resolve([config.hxml.getBuildFilename()]);
        } else return super.list();
    }

    override function generateHash():Promise<SourceHash> {
        // Not perfect, as it doesn't detect changes to library versions, but good enough.
        var hxmlHashP = config.hxml.generateHash();
        var fileHashesP:Promise<Array<SourceHash>> = Promise.all([for (src in makeArray(config.hxml.config.paths))
            Utils.listDirectoryRecursively((src:SourceId).toRelPath(config.hxml.project))])
            .then((arrFiles:Array<Array<String>>) -> {
                arrFiles.map(files -> {
                    (untyped files).sort(); // Keep deterministic.
                    return (cast Promise.all(files.map(f -> SourceHash.fromFile(f))):Promise<Array<SourceHash>>);
                });
            })
            .then(proms -> Promise.all(proms))
            .then((allHashes:Array<Array<SourceHash>>) -> Lambda.flatten(allHashes));

        return Promise.all([hxmlHashP, fileHashesP]).then(r -> {
            var hxmlHash:SourceHash = r[0];
            var fileHashes:Array<SourceHash> = r[1];
            var r = Lambda.fold(fileHashes, (i, r:SourceHash) -> r.add(i), hxmlHash);
            return r;
        });
    }

}

typedef BuildConfig = StoneConfig & {

    var hxml:Hxml;
    var ?useNpx:Bool;
    var ?filename:String;

}
