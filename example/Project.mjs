import { Project, JsonStone, Router, Log } from "../bin/whet.js";
import { CacheDurability, CacheStrategy, DurabilityCheck } from "../bin/whet/cache/Cache.js";
import { Server } from "../bin/whet/stones/Server.js";

// Log.logLevel = 10;

// await (await import('fs')).promises.rm('example/.whet', {force: true, recursive: true});

const project = new Project({name: "Test Project"});

const json = new JsonStone({mergeFiles: ["/data/"]}).addProjectData();
// json.cacheStrategy = CacheStrategy.InMemory(CacheDurability.KeepForever, DurabilityCheck.AllOnUse);
json.cacheStrategy = CacheStrategy.InFile(CacheDurability.LimitCountByLastUse(2), DurabilityCheck.AllOnUse);
// console.log((await json.getSource()).get().data.toString(('utf-8')));
json.data.foo = 'bar';
// console.log((await json.getSource()).get().data.toString(('utf-8')));

const unique = new JsonStone({id: 'unique'}).addProjectData()
await unique.setAbsolutePath('myJson.json');

const router = new Router([
    ['myUnique.json', unique],
    ['filtered/', '/data/', 'sample.json'],
    ['prepended/', '/data/'],
    ['rewired.json', '/data/', 'sample2.json'],
    ['picked.json', '/data/sample2.json'],
]);
console.log(await router.listContents());

const s = new Server({router: router});
// s.serve();
