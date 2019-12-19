package whet.stones;

import whet.Whetstone;
#if (tink_web && hxnodejs && mime)
import tink.CoreApi;
import tink.http.Request;
import tink.http.Response;
import tink.http.containers.*;
import tink.web.routing.*;
import tink.http.Header;
import tink.io.Source.RealSourceTools;

class ServerStone extends Whetstone {

    var config:ServerConfig;

    public function new(project:WhetProject, config:ServerConfig = null) {
        super(project);
        this.config = config == null ? { } : config;
    }

    #if !macro
    @command public function start(_) {
        var container = new NodeContainer(config.port);
        container.run(handler).handle(function(state) switch state {
            case Running(_):
                Whet.msg('Started web server at port ${config.port}.');
            case Failed(e):
                Whet.msg('Error: could not start web server:');
                Whet.msg(e.toString());
            case Shutdown:
        });
    }

    function handler(req:IncomingRequest):Future<OutgoingResponse> {
        var id:SourceId = req.header.url.path;
        var res:OutgoingResponse = null;
        switch req.header.method {
            case GET:
                if (id.isDir()) id.withExt = "index.html";
                else if (id.ext == '') id = '$id/index.html';
                var data = findSource(id);
                if (data != null) {
                    var mime = mime.Mime.lookup(id);
                    res = partial(req.header, data, mime, id.withExt);
                } else res = OutgoingResponse.reportError(new Error(NotFound, 'File Not Found'));
            case PUT:
                var cmd = haxe.io.Path.removeTrailingSlashes(id);
                if (project.commands.exists(cmd)) {
                    return switch req.body {
                        case Plain(source): // TODO: this should all be more async and properly handle errors, possibly return results.
                            RealSourceTools.all(source).next(function(p) {
                                project.commands.get(cmd)(p.toString());
                                return OutgoingResponse.blob(OK, tink.Chunk.EMPTY, "");
                            }).recover(e -> OutgoingResponse.reportError(new Error(InternalError, 'InternalError')));
                        case Parsed(parts): throw "Not implemented.";
                    }
                } else res = OutgoingResponse.reportError(new Error(NotFound, 'Command not found.'));

            case _:
                res = OutgoingResponse.reportError(new Error(NotImplemented, 'Unrecognized command.'));
        }
        return res;
    }

    // Adapted from https://github.com/haxetink/tink_http_middleware/blob/master/src/tink/http/middleware/Static.hx.
    function partial(header:Header, source:WhetSource, contentType:String, filename:String) {
        var headers = [
            new HeaderField('Accept-Ranges', 'bytes'),
            new HeaderField('Vary', 'Accept-Encoding'),
            new HeaderField('Content-Type', contentType),
            new HeaderField('Content-Disposition', 'inline; filename="$filename"'),
            new HeaderField('Surrogate-Control', 'no-store'), // No cache headers.
            new HeaderField('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate'),
            new HeaderField('Pragma', 'no-cache'),
            new HeaderField('Expires', '0'),
        ];

        // ref: https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.35
        return switch header.byName('range') {
            case Success(v):
                switch (v:String).split('=') {
                    case ['bytes', range]:
                        function res(pos:Int, len:Int) {
                            return new OutgoingResponse(
                                new ResponseHeader(206, 'Partial Content', headers.concat([
                                    new HeaderField('Content-Range', 'bytes $pos-${pos + len - 1}/${source.length}'),
                                    new HeaderField('Content-Length', len),
                                ])),
                                source.data.skip(pos).limit(len)
                            );
                        }

                        switch range.split('-') {
                            case ['', Std.parseInt(_) => len]: res(source.length - len, len);
                            case [Std.parseInt(_) => pos, '']: res(pos, source.length - pos);
                            case [Std.parseInt(_) => pos, Std.parseInt(_) => end]: res(pos, end - pos + 1);
                            default: OutgoingResponse.reportError(new Error(RangeNotSatisfiable, 'Invalid byte range.'));
                        }
                    default: OutgoingResponse.reportError(new Error(RangeNotSatisfiable, 'Unrecognized range unit.'));
                }
            case Failure(_):
                new OutgoingResponse(
                    new ResponseHeader(200, 'OK', headers.concat([
                        new HeaderField('Content-Length', source.length),
                    ])), source.data
                );
        }
    }
    #end

}
#else
class ServerStone extends Whetstone {

    public function new(project:WhetProject, config:ServerConfig = null) {
        super(project);
    }

    @command public function start(_) {
        Whet.error('ServerStone requires tink_web and mime libraries.');
    }

}
#end

@:structInit
class ServerConfig {

    public final port:Int = 7000;

}
