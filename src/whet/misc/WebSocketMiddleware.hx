package whet.misc;

import whet.stones.ServerStone.WhetServerMiddleware;
#if (tink_websocket && tink_http_middleware)
import tink.http.middleware.WebSocket;
import tink.streams.Stream;
import tink.websocket.MessageStream;
import tink.websocket.RawMessage;
import tink.websocket.servers.TinkServer.TinkConnectedClient;
import tink.websocket.servers.TinkServer;
#end

class WebSocketMiddleware implements WhetServerMiddleware {

    public var hasClients(get, never):Bool;

    public function new() { }

    #if (tink_websocket && tink_http_middleware)
    public var server:TinkServer;

    public function getMiddleware():WebSocket {
        server = new TinkServer();
        server.clientConnected.handle(function(client) {
            client.messageReceived.handle(function(msg) {
                switch msg {
                    case Text('ping'):
                        client.send(Text('pong'));
                    case _:
                }
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

    function get_hasClients() return server != null && server.clients.length > 0;
    #else
    public function broadcast(msg) { }

    function get_hasClients() return false;
    #end

}
