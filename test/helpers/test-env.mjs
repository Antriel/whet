import { mkdir, rm, writeFile, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { Log, Project } from "../../bin/whet.js";

Log.logLevel = 60;

function toPosix(input) {
  return input.replaceAll("\\", "/");
}

function uniqueSuffix() {
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export async function createTestProject(name = "test") {
  const rootDir = toPosix(path.join("test", ".tmp", `${name}-${uniqueSuffix()}`)) + "/";
  await mkdir(rootDir, { recursive: true });
  const project = new Project({
    name: `whet-${name}`,
    id: `whet-${name}-${uniqueSuffix()}`,
    rootDir,
  });
  return {
    rootDir,
    project,
    async write(relPath, content) {
      const filePath = path.join(rootDir, relPath);
      await mkdir(path.dirname(filePath), { recursive: true });
      await writeFile(filePath, content);
    },
    async read(relPath) {
      return readFile(path.join(rootDir, relPath), "utf-8");
    },
    async exists(relPath) {
      try {
        await stat(path.join(rootDir, relPath));
        return true;
      } catch {
        return false;
      }
    },
    async cleanup() {
      await rm(rootDir, { recursive: true, force: true });
    },
  };
}

