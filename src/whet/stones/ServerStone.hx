package whet.stones;

#if (tink_web && hxnodejs)
import tink.http.containers.*;
import tink.http.Response;
import tink.web.routing.*;

@:require("tink_web")
class ServerStone extends whet.Whetstone {
    
    var config:ServerConfig;
    
    public function new(project:WhetProject, config:ServerConfig = null) {
        super(project);
        this.config = config == null ? {} : config;
    }
    
    #if !macro
    @command public function start(_) {
        Whet.msg('Starting web server at port ${config.port}.');
        var container = new NodeContainer(config.port);
        var router = new Router<Root>(new Root());
        container.run(function(req) {
            return router.route(Context.ofRequest(req))
                .recover(OutgoingResponse.reportError);
        });
    }
    #end
    
}

class Root {
    public function new() {}

    @:get('/')
    @:get('/$name')
    public function hello(name = 'World')
        return 'Hello, $name!';
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
    
    public final port:Int;
    
    public function new(port:Int = 7000) {
        this.port = port;
    }
}
