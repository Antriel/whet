import { Project, JsonStone, Log } from "../bin/whet.js";
import { CacheDurability, CacheStrategy, DurabilityCheck } from "../bin/whet/cache/Cache.js";

// Log.logLevel = 10;

// await (await import('fs')).promises.rm('example/.whet', {force: true, recursive: true});

const project = new Project({name: "Test Project"});

const json = new JsonStone({mergeFiles: ["/data/"]}).addProjectData();
// json.cacheStrategy = CacheStrategy.InMemory(CacheDurability.KeepForever, DurabilityCheck.AllOnUse);
json.cacheStrategy = CacheStrategy.InFile(CacheDurability.LimitCountByLastUse(2), DurabilityCheck.AllOnUse);
console.log((await json.getSource()).get().data.toString(('utf-8')));
json.data.foo = 'bar';
console.log((await json.getSource()).get().data.toString(('utf-8')));

await new JsonStone({id: 'unique'}).addProjectData().setAbsolutePath('myJson.json');
