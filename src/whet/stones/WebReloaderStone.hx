package whet.stones;

import whet.Whetstone;

class WebReloaderStone extends Whetstone {

    public var config:WebReloaderConfig;

    public function new(project:WhetProject, id:WhetstoneID = null, config:WebReloaderConfig = null) {
        super(project, id);
        this.config = config != null ? config : {};
        this.config.init(project);
        enableWebReload();
    }

    @command public function launchOrReload() {
        if (config.websocket.hasClients) {
            config.websocket.broadcast('reload');
        } else config.chrome.launchChrome();
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
            </script>'
        );
    }

}

@:structInit class WebReloaderConfig {

    public var websocket:WebSocketStone = null;
    public var chrome:ChromeStone = null;
    public var html:HtmlStone = null;

    public function init(project:WhetProject) {
        if (websocket == null) websocket = project.stone(WebSocketStone);
        if (chrome == null) chrome = project.stone(ChromeStone);
        if (html == null) html = project.stone(HtmlStone);
    }

}
