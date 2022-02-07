package whet;

import whet.Log.LogLevel;

var program = new commander.Command('whet');

function main() {
    program.enablePositionalOptions().passThroughOptions()
        .description('Project tooling.')
        .usage('[options] [command] [+ [command]...]')
        .version(Macros.getVersion(), '-v, --version')
        .showSuggestionAfterError(true)
        .option('-p, --project <file>', 'project to run', 'Project.mjs')
        .option('-l, --log-level <level>', 'log level, a string/number', 'info');

    program.parse();
    final options = program.opts();
    if (options.logLevel != null) { // Handle logLevel immediately.
        var n = Std.parseInt(options.logLevel);
        if (n == null) n = LogLevel.fromString(options.logLevel);
        if (n == null) program.error('Invalid value for --log-level');
        else Log.logLevel = n;
    }
    js.Node.setImmediate(init, options); // Init next tick, in case the project file was executed directly.
}

private function init(options:Dynamic) {
    if (Project.projects.length > 0) { // Project already loaded.
        initProject();
    } else { // Load project.
        Log.info('Loading project.', { file: options.project });
        var path = js.node.Url.pathToFileURL(options.project).href;
        Log.trace('Resolved project path.', { path: path });

        var projectProm:Promise<js.node.Module> = js.Syntax.code('import({0})', path);
        projectProm.then(module -> {
            initProject();
        }).catchError(e -> {
            Log.error("Error loading project.", { error: e });
            program.help();
        });
    }
}

private function initProject() {
    Log.trace('Parsing remaining arguments.', { args: program.args });

    var commands = getCommands(program.args);
    for (c in commands) {
        Log.trace('Executing command.', { commandArgs: c });
        program.parse(c, { from: 'user' });
    }
}

private function getCommands(args:Array<String>):Array<Array<String>> {
    var commands = [];
    var from = 0;
    var to;
    do {
        to = args.indexOf('+', from);
        commands.push(to < 0 ? args.slice(from) : args.slice(from, to));
        from = to + 1;
    } while (to >= 0);
    return commands;
}
