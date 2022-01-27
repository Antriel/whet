package whet.stones;

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
    @command public function serve() {
        final server = Http.createServer(handler);
        final port = if (config.port != null) config.port else 7000;
        server.listen(port, () -> Log.info('Started web server.', { port: port }));
    }

    function handler(req:IncomingMessage, res:ServerResponse) {
        Log.info('Handling request.', { url: req.url, method: req.method });
        inline function err(e) {
            res.writeHead(500, 'Error happened.');
            res.write(Std.string(e), 'utf-8');
            res.end();
        }
        // TODO gzip support.
        var id:SourceId = req.url;
        switch req.method {
            case "GET":
                if (id.isDir()) id.withExt = "index.html";
                else if (id.ext == '') id = '$id/index.html';
                router.find(cast id).then(routeResult -> {
                    var sourcePromise = if (routeResult.length > 0) routeResult[0].get();
                    else if (routeDynamic != null) routeDynamic(cast id);
                    else null;
                    if (sourcePromise != null) {
                        sourcePromise.then(source -> {
                            res.writeHead(200, {
                                'Content-Type': Mime.getType(id.ext.toLowerCase()),
                                'Last-Modified': new js.lib.Date(source.source.ctime * 1000).toUTCString(),
                                'Content-Length': Std.string(source.data.length),
                                'Cache-Control': 'no-store, no-cache',
                            });
                            // TODO last modified should be the file stat.mtime, if it has a file and it's not cached.
                            // TODO instead of global no-cache, it would be nice if we had revalidation instead.
                            res.write(source.data, 'binary');
                            res.end();
                        }).catchError(e -> err(e));
                    } else {
                        res.writeHead(404, "File not found.");
                        res.end();
                    }
                }).catchError(e -> err(e));
            // case "PUT":
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

}
