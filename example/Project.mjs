import { Project, JsonStone } from "../bin/whet.js";


const project = new Project({name: "Test Project"});

const json = new JsonStone({mergeFiles: ["/data/"]}).addProjectData();
console.log((await json.generate())[0].data.toString(('utf-8')));

