import test from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFileSync } from "node:fs";
import { writeFile, mkdir, rm } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const exec = promisify(execFile);

async function whet(...args) {
  try {
    const { stdout, stderr } = await exec("node", ["bin/whet.js", ...args]);
    return { stdout, stderr, exitCode: 0 };
  } catch (e) {
    return { stdout: e.stdout ?? "", stderr: e.stderr ?? "", exitCode: e.code };
  }
}

const { version } = JSON.parse(readFileSync("package.json", "utf-8"));

test("--version prints version and exits 0", async () => {
  const { stdout, exitCode } = await whet("--version");
  assert.equal(exitCode, 0);
  assert.ok(stdout.includes(version), `expected "${version}" in stdout: ${stdout}`);
});

test("--help prints usage and exits 0", async () => {
  const { stdout, exitCode } = await whet("--help");
  assert.equal(exitCode, 0);
  assert.ok(stdout.includes("Usage:"), `expected "Usage:" in stdout: ${stdout}`);
  assert.ok(stdout.includes("--project"), `expected "--project" in stdout: ${stdout}`);
});

test("invalid log level exits non-zero with error message", async () => {
  const { stderr, exitCode } = await whet("-l", "not-a-level");
  assert.notEqual(exitCode, 0);
  assert.ok(stderr.includes("--log-level"), `expected error about --log-level in stderr: ${stderr}`);
});

test("top-level --help lists project commands (after loading project)", async (t) => {
  const tmpDir = resolve("test/.tmp/cli-help-" + Date.now());
  await mkdir(tmpDir, { recursive: true });
  t.after(() => rm(tmpDir, { recursive: true, force: true }));

  const whetUrl = pathToFileURL(resolve("bin/whet.js")).href;
  const projectFile = resolve(tmpDir, "Project.mjs");
  await writeFile(
    projectFile,
    `import { Project } from "${whetUrl}";
const project = new Project({ name: "test", rootDir: "./" });
project.addCommand("my-command").description("a custom command").action(() => {});
`
  );

  // The `--help` option must defer until the project is loaded, just like the `help`
  // command, so it surfaces project-registered commands (not only global options).
  for (const helpArg of ["--help", "-h"]) {
    const { stdout, exitCode } = await whet("-p", projectFile, helpArg);
    assert.equal(exitCode, 0, `${helpArg} should exit 0`);
    assert.ok(stdout.includes("my-command"), `expected "my-command" in ${helpArg} output: ${stdout}`);
    assert.ok(stdout.includes("Commands:"), `expected "Commands:" section in ${helpArg} output: ${stdout}`);
  }
});

test("registered command runs when invoked via CLI", async (t) => {
  const tmpDir = resolve("test/.tmp/cli-subprocess-" + Date.now());
  await mkdir(tmpDir, { recursive: true });
  t.after(() => rm(tmpDir, { recursive: true, force: true }));

  const whetUrl = pathToFileURL(resolve("bin/whet.js")).href;
  const projectFile = resolve(tmpDir, "Project.mjs");
  await writeFile(
    projectFile,
    `import { Project } from "${whetUrl}";
const project = new Project({ name: "test", rootDir: "./" });
project.addCommand("my-command").action(() => process.exit(42));
`
  );

  const { exitCode } = await whet("-p", projectFile, "my-command");
  assert.equal(exitCode, 42, "expected sentinel exit code from command action");
});

// stone-schema is registered alongside the project (initProjects), so real invocations resolve a
// project — which is also where project-registered types (e.g. SharpStone) become visible. These
// smoke tests supply a minimal one and pass -p, mirroring the pattern above.
async function withProject(t) {
  const tmpDir = resolve("test/.tmp/cli-stoneschema-" + Date.now() + "-" + Math.random().toString(36).slice(2));
  await mkdir(tmpDir, { recursive: true });
  t.after(() => rm(tmpDir, { recursive: true, force: true }));
  const whetUrl = pathToFileURL(resolve("bin/whet.js")).href;
  const projectFile = resolve(tmpDir, "Project.mjs");
  await writeFile(projectFile, `import { Project } from "${whetUrl}";\nnew Project({ name: "t", rootDir: "./" });\n`);
  return ["-p", projectFile];
}

test("stone-schema with a known schema-carrying type prints the schema JSON", async (t) => {
  const p = await withProject(t);
  const { stdout, exitCode } = await whet(...p, "stone-schema", "JsonDb");
  assert.equal(exitCode, 0);
  const schema = JSON.parse(stdout);
  assert.equal(schema.type, "object");
  assert.ok(schema.properties, "expected a properties object in JsonDb's schema");
});

test("stone-schema with a schema-less known type reports it (exit 0)", async (t) => {
  const p = await withProject(t);
  const { stdout, exitCode } = await whet(...p, "stone-schema", "Files");
  assert.equal(exitCode, 0);
  assert.ok(/has no schema/.test(stdout), `expected 'has no schema' message: ${stdout}`);
});

test("stone-schema with an unknown type lists registered types and exits 1", async (t) => {
  const p = await withProject(t);
  const { stderr, exitCode } = await whet(...p, "stone-schema", "NopeStone");
  assert.notEqual(exitCode, 0);
  assert.ok(/Unknown stone type/.test(stderr), `expected error: ${stderr}`);
  assert.ok(/JsonDb/.test(stderr), `expected registered-type listing: ${stderr}`);
});

test("stone-schema with no arg lists the registry", async (t) => {
  const p = await withProject(t);
  const { stdout, exitCode } = await whet(...p, "stone-schema");
  assert.equal(exitCode, 0);
  const list = JSON.parse(stdout);
  assert.ok(Array.isArray(list), "expected an array");
  const names = list.map((e) => e.name);
  assert.ok(names.includes("JsonDb"), `expected JsonDb in ${JSON.stringify(names)}`);
  // hasSchema flag is reported per-entry.
  assert.equal(list.find((e) => e.name === "JsonDb").hasSchema, true);
});
