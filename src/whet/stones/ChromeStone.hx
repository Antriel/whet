package whet.stones;

import whet.Whetstone;

class ChromeStone extends Whetstone {

    public var config:ChromeConfig;

    public function new(project:WhetProject, id:WhetstoneID = null, config:ChromeConfig = null) {
        super(project, id);
        this.config = config != null ? config : {};
    }

    @command public function launchChrome() {
        #if !macro
        var args = [
            '--app=http://localhost:7000/${config.launchPath}',
            '--user-data-dir=${config.userDataDir}',
        ];
        if (config.remoteDebuggingPort != null) args.push('--remote-debugging-port=${config.remoteDebuggingPort}');
        if (config.startFullScreen) args.push('--start-fullscreen');
        if (config.startMaximized) args.push('--start-maximized');
        for (flag in config.additionalFlags) args.push(flag);
        #if hxnodejs
        js.node.ChildProcess.spawn(config.chromePath, args, {
            stdio: 'ignore',
            detached: true
        }).unref();
        #elseif sys
        new sys.io.Process(config.chromePath, args, true);
        #else
        Whet.error("Not implemented.");
        #end
        #end
    }

}

@:structInit class ChromeConfig {

    public var chromePath:String = 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe'; // TODO make more crossplatform
    public var launchPath:String = "";
    public var remoteDebuggingPort:Null<Int> = 9222;
    public var additionalFlags:Array<String> = [];

    /** Specifies if the browser should start in fullscreen mode, like if the user had pressed F11 right after startup. */
    public var startFullScreen:Bool = false;

    /** Starts the browser maximized, regardless of any previous settings. ↪ */
    public var startMaximized:Bool = false;

    public var userDataDir:String = '/tmp/chrome-debug';

}
