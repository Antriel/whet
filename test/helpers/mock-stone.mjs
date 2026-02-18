import { Stone } from "../../bin/whet.js";
import { SourceData } from "../../bin/whet/Source.js";
import { SourceHash } from "../../bin/whet/SourceHash.js";

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export class MockStone extends Stone {
  constructor({
    project,
    id = "mock-stone",
    outputs = [{ id: "out.txt", content: "out" }],
    delayMs = 0,
    hashKey = "static",
    dependencies = null,
    cacheStrategy = null,
    configStore = null,
  } = {}) {
    super({ project, id, outputs, delayMs, hashKey, dependencies, cacheStrategy, configStore });
    this.generateCount = 0;
  }

  setOutputs(outputs) {
    this.config.outputs = outputs;
    return this;
  }

  setHashKey(hashKey) {
    this.config.hashKey = hashKey;
    return this;
  }

  async generateHash() {
    if (this.config.hashKey === null) return null;
    const key =
      typeof this.config.hashKey === "function"
        ? this.config.hashKey(this)
        : this.config.hashKey;
    return SourceHash.fromString(String(key));
  }

  async generate() {
    this.generateCount += 1;
    if (this.config.delayMs > 0) await sleep(this.config.delayMs);
    const defs =
      typeof this.config.outputs === "function"
        ? this.config.outputs(this.generateCount)
        : this.config.outputs;
    return defs.map((entry) =>
      SourceData.fromString(
        entry.id,
        typeof entry.content === "function"
          ? String(entry.content(this.generateCount))
          : String(entry.content),
      ),
    );
  }
}

