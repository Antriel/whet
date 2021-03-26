package whet.npm;

import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class NpmManager {

    static final NODE_ROOT:SourceId = '.whet/npm/';
    static final NODE_MODULES:SourceId = '.whet/npm/node_modules/';

    public static inline function getNodeRoot(rootDir:RootDir):String return NODE_ROOT.toRelPath(rootDir);

    public static inline function getNodeModules(rootDir:RootDir):String return NODE_MODULES.toRelPath(rootDir);

    public static function assureInstalled(rootDir:RootDir, module:String, version:String) {
        if (!isInstalled(rootDir, module, version)) {
            // We are not supporting multiple version installs.
            Utils.deleteRecursively(Path.join([getNodeModules(rootDir), module]));
            install(rootDir, module, version);
        }
    }

    public static function isInstalled(rootDir:RootDir, module:String, version:String):Bool {
        var modules = getNodeModules(rootDir);
        Utils.ensureDirExist(modules);
        var moduleFolder = Path.join([modules, module]);
        var modulePackage = Path.join([moduleFolder, 'package.json']);
        if (FileSystem.exists(moduleFolder) && FileSystem.exists(modulePackage)) {
            return Json.parse(File.getContent(modulePackage)).version == version;
        } else return false;
    }

    public static function install(rootDir:RootDir, module:String, version:String) {
        trace('Installing $module@$version from npm.');
        var nodeRoot = getNodeRoot(rootDir);
        Utils.ensureDirExist(nodeRoot);
        #if hxnodejs
        js.node.ChildProcess.spawnSync('npm', ['--prefix', nodeRoot, 'install', '$module@$version'],
            { shell: true, stdio: 'inherit' });
        #elseif sys
        var p = new sys.io.Process('npm --prefix $nodeRoot install $module@$version');
        p.exitCode(true);
        #end
    }

}
