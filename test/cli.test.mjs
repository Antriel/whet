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
