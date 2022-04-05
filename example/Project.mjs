import { RemoteFile } from "../bin/whet.js";
import { ZipStone } from "../bin/whet.js";
import { Project, JsonStone, Router, Log } from "../bin/whet.js";
import { CacheDurability, CacheStrategy, DurabilityCheck } from "../bin/whet/cache/Cache.js";
import { Server } from "../bin/whet/stones/Server.js";
import { Command, Option } from 'commander';

// Log.logLevel = 10;

// await (await import('fs')).promises.rm('example/.whet', {force: true, recursive: true});

const project = new Project({
    name: "Test Project",
    options: [new Option('-b, --build <type>', 'build type').choices(['debug', 'release']).makeOptionMandatory()],
    onInit: async config => {
        if(config.build == 'debug') {
            project.addCommand(new Command('list')
            .option('-s, --search <route>', 'route to filter the search', '/')
            .action(async (args) => {
                console.log(await router.listContents(args.search));
            }));
        }
    }
});

const json = new JsonStone({mergeFiles: ["/data/"]}).addProjectData();
// json.cacheStrategy = CacheStrategy.InMemory(CacheDurability.KeepForever, DurabilityCheck.AllOnUse);
json.cacheStrategy = CacheStrategy.InFile(CacheDurability.LimitCountByLastUse(2), DurabilityCheck.AllOnUse);
// console.log((await json.getSource()).get().data.toString(('utf-8')));
json.data.foo = 'bar';
// console.log((await json.getSource()).get().data.toString(('utf-8')));

const unique = new JsonStone({id: 'unique'}).addProjectData()
// await unique.setAbsolutePath('myJson.json');

const phaser = new RemoteFile({url: 'https://cdn.jsdelivr.net/npm/phaser@3.55.2/dist/phaser.min.js' });

const router = new Router([
    ['myUnique.json', unique],
    ['filtered/', '/data/', 'sample.json'],
    ['prepended/', '/data/'],
    ['rewired.json', '/data/', 'sample2.json'],
    ['picked.json', '/data/sample2.json'],
    ['phaser.js', phaser]
]);
// console.log(await router.listContents());

// await new ZipStone({sources: router}).setAbsolutePath('bundle.zip');

const s = new Server({router: router});
