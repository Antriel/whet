package whet.npm;

import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class NpmManager {

    public static final NODE_ROOT:SourceId = '.whet/npm/';
    public static final NODE_MODULES:SourceId = '.whet/npm/node_modules/';

    public static function assureInstalled(module:String, version:String) {
        if (!isInstalled(module, version)) {
            // We are not supporting multiple version installs.
            Utils.deleteRecursively(Path.join([NODE_MODULES, module]));
            install(module, version);
        }
    }

    public static function isInstalled(module:String, version:String):Bool {
        Utils.ensureDirExist(NODE_MODULES);
        var moduleFolder:SourceId = Path.join([NODE_MODULES, module]) + '/';
        var modulePackage:SourceId = Path.join([moduleFolder, 'package.json']);
        if (FileSystem.exists(moduleFolder) && FileSystem.exists(modulePackage)) {
            return Json.parse(File.getContent(modulePackage)).version == version;
        } else return false;
    }

    public static function install(module:String, version:String) {
        trace('Installing $module@$version from npm.');
        Utils.ensureDirExist(NODE_ROOT);
        #if hxnodejs
        js.node.ChildProcess.spawnSync('npm', ['--prefix', NODE_ROOT.toRelPath(), 'install', '$module@$version'],
            { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new sys.io.Process('npm --prefix $NODE_ROOT install $module@$version');
        p.exitCode(true);
        #end
    }

}
