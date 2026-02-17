import test from "node:test";
import assert from "node:assert/strict";

import { Project } from "../bin/whet.js";
import { createTestProject } from "./helpers/test-env.mjs";
import { MockStone } from "./helpers/mock-stone.mjs";

test("Project requires a config with name", () => {
  assert.throws(() => new Project(null));
  assert.throws(() => new Project({}));
});

test("Project generates default id from name", async () => {
  const env = await createTestProject("project-default-id");
  const project = new Project({ name: "Hello World", rootDir: env.rootDir });
  assert.equal(project.id, "hello-world");
  await env.cleanup();
});

test("Project uses explicit rootDir and addCommand stone alias", async () => {
  const env = await createTestProject("project-command");
  const stone = new MockStone({ project: env.project, id: "alias-stone" });
  const command = env.project.addCommand("build", stone);
  assert.ok(command.aliases().includes("alias-stone.build"));
  assert.equal(env.project.rootDir, env.rootDir);
  await env.cleanup();
});

