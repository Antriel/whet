import { createRequire, syncBuiltinESMExports } from "node:module";

const fs = createRequire(import.meta.url)("fs");

/**
 * Hold back `fs.rename` callbacks until `release()`: the rename happens on disk, but the caller
 * doesn't hear about it yet. A `TrackedFile` write renames its temp file into place as the last
 * step, so this pins it in the window between "new bytes on disk" and "new state recorded" —
 * a slow write on a watched folder, made deterministic. Always `release()` (in a `finally`).
 */
export function holdRenames() {
  const real = fs.rename;
  const held = [];
  const waiters = [];
  const check = () => {
    for (const w of [...waiters]) if (held.length >= w.count) {
      waiters.splice(waiters.indexOf(w), 1);
      w.resolve();
    }
  };
  fs.rename = (from, to, cb) =>
    real(from, to, (err) => {
      held.push(() => cb(err));
      check();
    });
  syncBuiltinESMExports();
  return {
    /** Resolves once `count` renames have happened on disk (and are being held). */
    renamed(count = 1) {
      return new Promise((resolve) => {
        waiters.push({ count, resolve });
        check();
      });
    },
    /** Restore `fs.rename` and deliver every held callback. */
    release() {
      fs.rename = real;
      syncBuiltinESMExports();
      for (const deliver of held.splice(0)) deliver();
    },
  };
}

/**
 * Defer the next `fs[name]` call itself (not just its callback) until `run()`, so an operation that
 * started earlier can be made to look at the disk later — e.g. a `stat` landing after a rename.
 * Only that one call is deferred; later calls go straight through.
 */
export function deferNext(name) {
  const real = fs[name];
  let run;
  const gate = new Promise((r) => (run = r));
  let markCalled;
  const called = new Promise((r) => (markCalled = r));
  const restore = () => {
    if (fs[name] === real) return;
    fs[name] = real;
    syncBuiltinESMExports();
  };
  fs[name] = (...args) => {
    restore();
    markCalled();
    gate.then(() => real(...args));
  };
  syncBuiltinESMExports();
  return {
    /** Resolves once the deferred call was made. */
    called,
    /** Let the deferred call run. */
    run: () => run(),
    restore,
  };
}

/** Count calls to `fs[name]` (passing them through) until `restore()`. */
export function countCalls(name) {
  const real = fs[name];
  const spy = { count: 0, restore() {
    fs[name] = real;
    syncBuiltinESMExports();
  } };
  fs[name] = (...args) => {
    spy.count++;
    return real(...args);
  };
  syncBuiltinESMExports();
  return spy;
}
