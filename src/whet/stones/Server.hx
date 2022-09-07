package whet.stones;

import haxe.DynamicAccess;
import js.node.Http;
import js.node.http.IncomingMessage;
import js.node.http.ServerResponse;
import whet.extern.Mime;

class Server extends Stone<ServerConfig> {

    public var router(get, never):Router;

    private inline function get_router() return config.router;

    public var routeDynamic:String->Promise<SourceData> = null;

    function generate(hash:SourceHash):Promise<Array<SourceData>> throw new js.lib.Error("Does not generate.");

    /** Starts a static server hosting attached resources. */
    public function serve() {
        final server = Http.createServer(handler);
        server.listen(config.port, () -> Log.info('Started web server.', { port: config.port }));
    }

    override function initConfig() {
        super.initConfig();
        if (config.port == null) config.port = 7000;
    }

    override function addCommands():Void {
        project.addCommand('serve', this)
            .option('-p, --port <port>', 'server port', '' + config.port)
            .action((args) -> {
                if (args[0].port != null) config.port = Std.parseInt(args[0].port);
                serve();
                return null;
            });
    }

    function handler(req:IncomingMessage, res:ServerResponse) {
        Log.info('Handling request.', { url: req.url, method: req.method });
        inline function err(e:Dynamic) {
            Log.warn("Server error.", { error: e });
            res.writeHead(500, 'Error happened.', this.config.headers);
            if (e is js.lib.Error) {
                res.write((e:js.lib.Error).stack, 'utf-8');
            } else {
                res.write(Std.string(e), 'utf-8');
            }
            res.end();
        }
        // TODO gzip support.
        // Remove search params for now.
        final searchIndex = req.url.indexOf('?');
        var id:SourceId = searchIndex > 0 ? req.url.substring(0, searchIndex) : req.url;
        switch req.method {
            case "GET":
                if (id.isDir()) id.withExt = "index.html";
                else if (id.ext == '') id = '$id/index.html';
                router.get(cast id).then(routeResult -> {
                    var sourcePromise = if (routeResult.length > 0) routeResult[0].get();
                    else if (routeDynamic != null) routeDynamic(cast id);
                    else Promise.resolve(null);
                    sourcePromise.then(source -> {
                        if (source == null) {
                            res.writeHead(404, "File not found.");
                            res.end();
                            return;
                        }
                        var headers:DynamicAccess<String> = {
                            'Content-Type': Mime.getType(id.ext.toLowerCase()),
                            'Last-Modified': new js.lib.Date(source.source.ctime * 1000).toUTCString(),
                            'Content-Length': Std.string(source.data.length),
                            'Cache-Control': 'no-store, no-cache',
                        }
                        // TODO last modified should be the file stat.mtime, if it has a file and it's not cached.
                        // TODO instead of global no-cache, it would be nice if we had revalidation instead.
                        if (config.headers != null) for (key => val in config.headers) headers[key] = val;
                        res.writeHead(200, headers);
                        res.write(source.data, 'binary');
                        res.end();
                    }).catchError(e -> err(e));
                }).catchError(e -> err(e));
            case "PUT":
                var cmd = [id.toCwdPath('/')];
                var body = '';
                req.on('data', chunk -> body += chunk);
                req.on('end', () -> {
                    if (body != '') cmd.push(body); // Assuming a single arg for now.
                    whet.Whet.executeCommand(cmd).then(_ -> {
                        res.writeHead(200, config.headers);
                        res.end();
                    }).catchError(e -> err(e));
                });
            case "OPTIONS":
                res.writeHead(200, this.config.headers);
                res.end();
            case _:
                res.writeHead(400, "Unsupported method.");
                res.end();
        }
    }

}

typedef ServerConfig = StoneConfig & {

    /** Defaults to 7000. */
    var port:Int;

    var router:Router;
    @:optional var headers:DynamicAccess<String>;

}
