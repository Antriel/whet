---
# whet-3v0m
title: 'Bug: SourceData.getFilePath creates Error but does not throw'
status: todo
type: bug
priority: normal
created_at: 2026-02-14T08:29:35Z
updated_at: 2026-02-14T08:29:57Z
parent: whet-4ve1
---

SourceData.getFilePath checks if source is null and constructs an Error, but does not throw it (src/whet/Source.hx:136). This silently continues with invalid state and can produce follow-on null/path issues.
