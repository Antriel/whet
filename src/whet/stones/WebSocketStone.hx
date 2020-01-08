package whet.stones;

import whet.Whetstone;
import whet.stones.ServerStone.WhetServerMiddleware;
#if (tink_websocket && tink_http_middleware)
import tink.websocket.servers.TinkServer;
import tink.websocket.servers.TinkServer.TinkConnectedClient;
import tink.websocket.RawMessage;
import tink.websocket.MessageStream;
import tink.streams.Stream;
import tink.http.middleware.WebSocket;
#end

class WebSocketStone extends Whetstone implements WhetServerMiddleware {

    #if (tink_websocket && tink_http_middleware)
    var server:TinkServer;

    public function getMiddleware():WebSocket {
        var server = new TinkServer();
        server.clientConnected.handle(function(client) {
            client.messageReceived.handle(function(msg) {
                // TODO
            });
        });
        return new WebSocket(server.handle);
    }

    @command public function broadcast(msg) {
        if (server != null) {
            for (client in server.clients) {
                client.send(Text(msg));
            }
        }
    }
    #end

}
