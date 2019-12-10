package whet.stones;

@:require("tink_web")
class ServerStone extends whet.Whetstone {
    
    public function new(project:WhetProject) {
        super(project);
        #if !tink_web Whet.error('ServerStone requires tink_web library.'); #end
    }
    
    #if tink_web
    @command public function start(_) {
        
    }
    #end
    
}
