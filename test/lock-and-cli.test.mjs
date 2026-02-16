import test from "node:test";
import assert from "node:assert/strict";
import { setTimeout as sleep } from "node:timers/promises";

import { Project } from "../bin/whet/Project.js";
import { Stone } from "../bin/whet/Stone.js";
import { SourceData } from "../bin/whet/Source.js";
import { CacheStrategy } from "../bin/whet/cache/Cache.js";
import { Whet_Fields_, program } from "../bin/whet/Whet.js";
import { createTestProject } from "./helpers/test-env.mjs";

class LockStone extends Stone {
  constructor(project, id) {
    super({ project, id, cacheStrategy: CacheStrategy.None });
    this.generateCount = 0;
    this.active = 0;
    this.maxActive = 0;
  }

  async generateHash() {
    return null;
  }

  async generate() {
    this.generateCount += 1;
    this.active += 1;
    this.maxActive = Math.max(this.maxActive, this.active);
    await sleep(25);
    this.active -= 1;
    return [SourceData.fromString("lock.txt", `v${this.generateCount}`)];
  }
}

test("Stone acquire lock serializes concurrent getSource calls", async () => {
  const env = await createTestProject("stone-lock");
  const stone = new LockStone(env.project, `lock-${Date.now()}`);

  await Promise.all([
    stone.getSource(),
    stone.getSource(),
    stone.getSource(),
    stone.getSource(),
    stone.getSource(),
  ]);

  assert.equal(stone.generateCount, 5);
  assert.equal(stone.maxActive, 1);
  await env.cleanup();
});

test("Whet command splitter separates chained commands by +", () => {
  const commands = Whet_Fields_.getCommands(["build", "--x", "1", "+", "serve", "+", "clean", "--all"]);
  assert.deepEqual(commands, [
    ["build", "--x", "1"],
    ["serve"],
    ["clean", "--all"],
  ]);
});

test("Project.onInit runs before chained commands execute (in-process CLI path)", async () => {
  const env = await createTestProject("cli-oninit-chain");
  const tag = Date.now().toString(36);
  const cmdA = `cmdA_${tag}`;
  const cmdB = `cmdB_${tag}`;

  let onInitCount = 0;
  const order = [];
  let doneResolve;
  const done = new Promise((resolve) => {
    doneResolve = resolve;
  });

  const project = new Project({
    name: `cli-${tag}`,
    id: `cli-${tag}`,
    rootDir: env.rootDir,
    onInit: async () => {
      onInitCount += 1;
      order.push("init");
    },
  });

  project
    .addCommand(cmdA)
    .action(async () => {
      order.push("a");
    });

  project
    .addCommand(cmdB)
    .action(async () => {
      order.push("b");
      doneResolve();
    });

  program.args = [cmdA, "+", cmdB];
  Whet_Fields_.initProjects();
  await Promise.race([
    done,
    sleep(1000).then(() => {
      throw new Error("Timed out waiting for chained commands to run.");
    }),
  ]);

  assert.equal(onInitCount, 1);
  assert.deepEqual(order, ["init", "a", "b"]);
  await env.cleanup();
});

