package whet.stones;

import whet.Whetstone;

class WebReloaderStone extends Whetstone {

    public var config:WebReloaderConfig;

    public function new(project:WhetProject, id:WhetstoneID = null, config:WebReloaderConfig = null) {
        super(project, id);
        this.config = config != null ? config : {};
        project.postInit.handle(_ -> {
            this.config.init(project);
            enableWebReload();
        });
    }

    @command public function launchOrReload() {
        if (config.websocket != null && config.websocket.hasClients) {
            config.websocket.broadcast('reload');
        } else if (config.chrome != null) {
            config.chrome.launchChrome();
        } else {
            var url = 'http://localhost:${config.port}';
            switch Sys.systemName() {
                case "Linux", "BSD":
                    Sys.command("xdg-open", [url]);
                case "Mac":
                    Sys.command("open", [url]);
                case "Windows":
                    Sys.command("cmd", ['/s', '/c', 'start', url, '/b']);
                case _:
            }
        }
    }

    function enableWebReload() {
        config.html.config.bodyElements.unshift('
            <script>
                let ws = new WebSocket("ws://" + location.host);
                ws.onmessage = function(e) {
                    if(e.data == "reload") {
                        location.reload();
                    }
                }
                ws.onerror = function(e) {
                    console.log(e);
                }
                ws.onopen = function() {
                    setInterval(function() {ws.send("ping");}, 60*1000);
                }
            </script>'
        );
    }

}

@:structInit class WebReloaderConfig {

    public var websocket:WebSocketStone = null;
    public var chrome:ChromeStone = null;
    public var html:HtmlStone = null;
    public var port:Null<Int> = null;

    public function init(project:WhetProject) {
        if (websocket == null) websocket = project.stone(WebSocketStone);
        if (chrome == null) chrome = project.stone(ChromeStone);
        if (html == null) html = project.stone(HtmlStone);
        if (port == null) {
            var server = project.stone(ServerStone);
            if (server != null) port = server.config.port;
            else port = 7000;
        }
    }

}
