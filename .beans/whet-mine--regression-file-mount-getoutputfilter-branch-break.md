---
# whet-mine
title: 'Regression: file-mount getOutputFilter branch breaks match-all routers'
status: completed
type: bug
priority: high
created_at: 2026-07-21T15:55:55Z
updated_at: 2026-07-21T16:04:06Z
---

0.6.3 file-mount handling makes a previously-unfiltered router (containing file-mounted sources without getOutputFilter) return a non-null filter, causing a wrong couldMatch prune. gooye-2 test command returns [] for assets/logo.avif regardless of soundbank.

## Summary of Changes

**Root cause: dangling-else in Router.getOutputFilter (src/whet/route/Router.hx).**
```
if (childFilter.extensions != null)
    for (ext in childFilter.extensions)
        if (allExtensions.indexOf(ext) == -1) allExtensions.push(ext);
        else hasExtensionlessChild = true;   // bound to inner if, not the null-check
```
The `else` bound to `if (indexOf == -1)`, so `hasExtensionlessChild` was set on any DUPLICATE extension across siblings. gooye's assets.router has two png stones (assetsOpt + msdfOpt) -> second png tripped it -> assets.router extensions nulled -> propagated up -> bundle.router advertised only [html,js,mjs] -> couldMatch skipped the whole assets subtree -> [].

**Why it only appeared in 0.6.3:** the bug existed in the first fix too but was masked — without the file-mount branch, bundle.router had unfiltered file-mounted children (index.html/esbuild/string routes) that forced getOutputFilter to return null (no pruning). The file-mount branch (correct + desired) stopped those forcing null, unmasking the dangling-else.

**Fix:** braced both extension and pattern blocks so `else` binds to the childFilter-null check.

**Diagnosis:** temporary WHET_TRACE_PRUNE instrumentation in getResults, run against the real gooye Project.mjs via npm link -> pinpointed `mount='' exts=[html,js,mjs]`. Verified fix in gooye: assets/logo.avif resolves both with and without the soundbank route.

**Test added:** "duplicate extension across siblings keeps extensions" (test/router.test.mjs) — two png siblings + one avif, asserts avif still resolves through a mounted parent. Full suite 184/184.
