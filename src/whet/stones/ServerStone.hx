package whet.stones;

#if (tink_web && hxnodejs)
import tink.CoreApi;
import tink.http.Request;
import tink.http.Response;
import tink.http.containers.*;
import tink.web.routing.*;
import tink.http.Header.HeaderField;

@:require("tink_web")
class ServerStone extends whet.Whetstone {

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
    #end

    function handler(req:IncomingRequest):Future<OutgoingResponse> {
        var id:SourceId = req.header.url.toString();
        var res:OutgoingResponse = null;
        for (dir => source in config.sources) {
            if (id.isInDir(dir, true)) { // TODO might need to actually route this
                var find = source.getSource(id);
                if (find != null) {
                    res = new OutgoingResponse(new ResponseHeader(OK, OK, [new HeaderField(CONTENT_TYPE, 'text/plain')]), find);
                    break;
                }
            }
        }
        // var res = Promise.resolve(('Hello!':OutgoingResponse));
        if (res == null) res = OutgoingResponse.reportError(new Error(NotFound, 'File Not Found'));
        return res;
    }

}
#else
@:require("tink_web")
class ServerStone extends whet.Whetstone {

    public function new(project:WhetProject) {
        Whet.error('ServerStone requires tink_web library.');
        super(project);
    }

}
#end

@:structInit
class ServerConfig {

    public final port:Int = 7000;
    public var sources:Map<SourceId, Whetstone> = new Map();

}
