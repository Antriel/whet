import test from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFileSync } from "node:fs";

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

test("unknown option exits non-zero", async () => {
  const { exitCode } = await whet("--not-a-real-option");
  assert.notEqual(exitCode, 0);
});
